library(tidyverse)
library(sf)

BASE <- "C:/Users/krumh/Claude/white_map"
OUT  <- file.path(BASE, "data")

parse_codebook <- function(cb_path) {
  lines <- readLines(cb_path, warn = FALSE)
  var_lines <- grep("^\\s+[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?\\s*:", lines, value = TRUE)
  if (!length(var_lines)) return(tibble(code = character(), desc = character()))
  tibble(code = str_trim(str_extract(var_lines, "[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?")),
         desc = str_trim(str_remove(var_lines, "^.*?:\\s*")))
}
find_vars <- function(vars, pat) vars$code[str_detect(vars$desc, regex(pat, ignore_case = TRUE))]

cfgs <- list(
  `1990` = list(csv_glob = file.path(BASE, "nhgis_downloads/data/*1990*tract*.csv"),
                occupied_pat = "^Occupied$", vacant_pat = "^Vacant$"),
  `2000` = list(csv_glob = file.path(BASE, "nhgis_downloads/data/*2000*tract*.csv"),
                occupied_pat = "^Occupied$", vacant_pat = "^Vacant$"),
  `2010` = list(csv_glob = file.path(BASE, "nhgis_downloads/data/*2010*tract*.csv"),
                occupied_pat = "^Occupied$", vacant_pat = "^Vacant$"),
  `2020` = list(csv_glob = file.path(BASE, "nhgis_downloads/data/*2020*tract*.csv"),
                occupied_pat = "^Occupied$", vacant_pat = "^Vacant$")
)

for (yr in names(cfgs)) {
  out_path <- file.path(OUT, paste0("vacancy_", yr, ".geojson"))
  if (file.exists(out_path)) { message("Skip ", yr); next }
  cfg <- cfgs[[yr]]
  message("\n=== ", yr, " ===")

  csv_file <- NULL; occ_cols <- character(0); vac_cols <- character(0)
  for (cf in sort(Sys.glob(cfg$csv_glob))) {
    cb <- str_replace(cf, "\\.csv$", "_codebook.txt")
    if (!file.exists(cb)) next
    v <- parse_codebook(cb)
    oc <- find_vars(v, cfg$occupied_pat)
    vc <- find_vars(v, cfg$vacant_pat)
    if (length(oc) == 0 || length(vc) == 0) next
    csv_file <- cf; occ_cols <- oc; vac_cols <- vc; break
  }
  if (is.null(csv_file)) { message("No matching CSV for ", yr); next }

  message("  occupied: ", paste(occ_cols, collapse = ", "))
  message("  vacant:   ", paste(vac_cols,  collapse = ", "))

  dat_raw <- read_csv(csv_file, show_col_types = FALSE)
  dat <- dat_raw %>%
    mutate(occ_pop  = rowSums(select(., all_of(occ_cols)), na.rm = TRUE),
           vac_pop  = rowSums(select(., all_of(vac_cols)),  na.rm = TRUE),
           total_hu = occ_pop + vac_pop,
           vac_share = if_else(total_hu > 0, vac_pop / total_hu, NA_real_)) %>%
    select(GISJOIN, total_hu, vac_share)

  sg <- file.path(BASE, "nhgis_downloads/shapefiles_simple",
                  paste0("tracts_", yr, "_simple.geojson"))
  message("  Reading pre-simplified GeoJSON...")
  shp <- st_read(sg, quiet = TRUE)

  merged <- shp %>%
    left_join(dat, by = "GISJOIN") %>%
    mutate(year = as.integer(yr)) %>%
    select(GISJOIN, year, vac_share, total_hu)

  st_write(merged, out_path, delete_dsn = TRUE, quiet = TRUE)
  message("  Wrote ", out_path, " (", round(file.size(out_path) / 1e6, 1), " MB)")
}
message("\nDone.")
