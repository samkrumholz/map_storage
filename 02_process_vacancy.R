# 02_process_vacancy.R
# Share of vacant housing units by Census tract, 1950–2020
# All data comes from the same NHGIS extract already downloaded
# (housing/occupancy tables were bundled with the race data)
#
# 1940 skipped: extract only has vacancy subtypes (BU4001/BU4002), no occupied
#   count or total housing units — can't compute a vacancy rate.

library(tidyverse)
library(sf)
library(rmapshaper)

BASE <- "C:/Users/krumh/Claude/white_map"
OUT  <- file.path(BASE, "data")
dir.create(OUT, showWarnings = FALSE)

# ── Codebook parser (same as 01_process_nhgis.R) ─────────────────────────────
parse_codebook <- function(cb_path) {
  lines <- readLines(cb_path, warn = FALSE)
  var_lines <- grep("^\\s+[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?\\s*:", lines, value = TRUE)
  if (!length(var_lines)) return(tibble(code = character(), desc = character()))
  tibble(
    code = str_trim(str_extract(var_lines, "[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?")),
    desc = str_trim(str_remove(var_lines, "^.*?:\\s*"))
  )
}

find_vars <- function(vars, pattern) {
  vars$code[str_detect(vars$desc, regex(pattern, ignore_case = TRUE))]
}

# ── Year config ───────────────────────────────────────────────────────────────
# occupied_pat: regex matching occupied-unit row descriptions
# vacant_pat:   regex matching vacant-unit row descriptions
# total_hu = sum(occupied cols) + sum(vacant cols)
# vacancy_rate = sum(vacant cols) / total_hu
#
# CSV selection: loop through all year-matching CSVs; pick first where
# both occupied_pat AND vacant_pat match at least one variable each.

year_config_vac <- list(
  `1950` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1950"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1950*tract*.csv"),
    occupied_pat = "^Occupied",
    vacant_pat   = "^Vacant"
  ),
  `1960` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1960"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1960*tract*.csv"),
    occupied_pat = "Owner.occupied|Renter.occupied",
    vacant_pat   = "^Vacant"
  ),
  `1970` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1970"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1970*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant"
  ),
  `1980` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1980"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1980*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant$"
  ),
  `1990` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1990"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1990*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant$"
  ),
  `2000` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/2000"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*2000*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant$"
  ),
  `2010` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/2010"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*2010*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant$"
  ),
  `2020` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/2020"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*2020*tract*.csv"),
    occupied_pat = "^Occupied$",
    vacant_pat   = "^Vacant$"
  )
)

# ── Process one year ──────────────────────────────────────────────────────────
process_year_vac <- function(yr, cfg) {
  message("\n=== ", yr, " ===")

  csv_files <- Sys.glob(cfg$csv_glob)
  if (!length(csv_files)) stop("No CSV found matching: ", cfg$csv_glob)

  csv_file <- NULL; vars <- NULL
  occ_cols <- character(0); vac_cols <- character(0)

  for (cf in sort(csv_files)) {
    cb <- str_replace(cf, "\\.csv$", "_codebook.txt")
    if (!file.exists(cb)) next
    v  <- parse_codebook(cb)
    oc <- find_vars(v, cfg$occupied_pat)
    vc <- find_vars(v, cfg$vacant_pat)
    if (length(oc) == 0 || length(vc) == 0) next
    csv_file <- cf; vars <- v; occ_cols <- oc; vac_cols <- vc
    break
  }

  if (is.null(csv_file)) {
    message("\nAuto-detect failed for ", yr)
    for (cf in sort(csv_files)) {
      cb <- str_replace(cf, "\\.csv$", "_codebook.txt")
      if (file.exists(cb)) { message("\n  ", basename(cb), ":"); print(parse_codebook(cb), n = 60) }
    }
    stop("Update occupied_pat / vacant_pat in year_config_vac for ", yr)
  }

  message("  CSV:      ", basename(csv_file))
  message("  occupied: ", paste(occ_cols, collapse = ", "))
  message("  vacant:   ", paste(vac_cols,  collapse = ", "))

  dat_raw <- read_csv(csv_file, show_col_types = FALSE)

  dat <- dat_raw %>%
    mutate(
      occ_pop   = rowSums(select(., all_of(occ_cols)), na.rm = TRUE),
      vac_pop   = rowSums(select(., all_of(vac_cols)),  na.rm = TRUE),
      total_hu  = occ_pop + vac_pop,
      vac_share = if_else(total_hu > 0, vac_pop / total_hu, NA_real_)
    ) %>%
    select(GISJOIN, total_hu, vac_share)

  simple_geojson <- file.path(BASE, "nhgis_downloads/shapefiles_simple",
                               paste0("tracts_", yr, "_simple.geojson"))
  if (file.exists(simple_geojson)) {
    message("  Reading pre-simplified GeoJSON...")
    shp <- st_read(simple_geojson, quiet = TRUE)
  } else {
    shp_files <- list.files(cfg$shp_dir, "\\.shp$", full.names = TRUE)
    if (!length(shp_files)) stop("No shapefile in: ", cfg$shp_dir)
    shp <- st_read(shp_files[1], quiet = TRUE)
  }

  merged <- shp %>%
    left_join(dat, by = "GISJOIN") %>%
    mutate(year = as.integer(yr)) %>%
    select(GISJOIN, year, vac_share, total_hu)

  if (!file.exists(simple_geojson)) {
    message("  Simplifying...")
    merged <- merged %>%
      st_transform(4326) %>%
      ms_simplify(keep = 0.04, keep_shapes = TRUE, weighting = 0.7, sys = TRUE)
  }

  out_path <- file.path(OUT, paste0("vacancy_", yr, ".geojson"))
  st_write(merged, out_path, delete_dsn = TRUE, quiet = TRUE)
  sz <- round(file.size(out_path) / 1e6, 1)
  message("  Wrote ", out_path, " (", sz, " MB)")
  invisible(merged)
}

# ── Run ───────────────────────────────────────────────────────────────────────
for (yr in names(year_config_vac)) {
  tryCatch(
    process_year_vac(yr, year_config_vac[[yr]]),
    error = function(e) message("ERROR for ", yr, ": ", e$message)
  )
}
message("\nDone. vacancy_YYYY.geojson written to: ", OUT)
