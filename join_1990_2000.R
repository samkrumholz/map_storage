library(tidyverse)
library(sf)

BASE <- "C:/Users/krumh/Claude/white_map"
OUT  <- file.path(BASE, "data")

parse_codebook <- function(cb_path) {
  lines <- readLines(cb_path, warn = FALSE)
  var_lines <- grep("^\\s+[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?\\s*:", lines, value = TRUE)
  if (!length(var_lines)) return(tibble(code = character(), desc = character()))
  tibble(
    code = str_trim(str_extract(var_lines, "[A-Z][A-Z0-9]{2}[0-9]{3,}[A-Z]?")),
    desc = str_trim(str_remove(var_lines, "^.*?:\\s*"))
  )
}

find_var <- function(vars, pattern) {
  vars$code[str_detect(vars$desc, regex(pattern, ignore_case = TRUE))][1]
}

configs <- list(
  `1990` = list(
    simp_shp = file.path(BASE, "nhgis_downloads/shapefiles/1990_simp/tracts_1990_simp.shp"),
    csv_glob = file.path(BASE, "nhgis_downloads/data/*1990*tract*.csv"),
    white_pat = "Not.{0,15}Hispanic.{0,15}White",
    total_as_sum = TRUE,
    label = "NH-White share"
  ),
  `2000` = list(
    simp_shp = file.path(BASE, "nhgis_downloads/shapefiles/2000_simp/tracts_2000_simp.shp"),
    csv_glob = file.path(BASE, "nhgis_downloads/data/*2000*tract*.csv"),
    white_pat = "Not Hispanic.{0,30}White alone",
    total_as_sum = TRUE,
    label = "NH-White alone share"
  )
)

for (yr in names(configs)) {
  cfg <- configs[[yr]]
  message("\n=== ", yr, " ===")

  # Find CSV + white variable
  csv_files <- Sys.glob(cfg$csv_glob)
  csv_file <- NULL; white_col <- NULL

  for (cf in sort(csv_files)) {
    cb <- str_replace(cf, "\\.csv$", "_codebook.txt")
    if (!file.exists(cb)) next
    v  <- parse_codebook(cb)
    wc <- find_var(v, cfg$white_pat)
    if (!is.na(wc)) { csv_file <- cf; white_col <- wc; break }
  }
  if (is.null(csv_file)) stop("No CSV for ", yr)
  message("  CSV: ", basename(csv_file), "  white_col: ", white_col)

  # Compute white_share
  dat_raw <- read_csv(csv_file, show_col_types = FALSE)
  prefix   <- substr(white_col, 1, 3)
  race_cols <- names(dat_raw)[grepl(paste0("^", prefix, "[0-9]"), names(dat_raw))]

  dat <- dat_raw %>%
    mutate(
      total_pop  = rowSums(select(., all_of(race_cols)), na.rm = TRUE),
      white_pop  = .data[[white_col]],
      white_share = if_else(total_pop > 0, white_pop / total_pop, NA_real_)
    ) %>%
    select(GISJOIN, total_pop, white_share)

  # Read already-simplified shapefile
  shp <- st_read(cfg$simp_shp, quiet = TRUE)
  message("  shp rows: ", nrow(shp))

  merged <- shp %>%
    st_transform(4326) %>%
    left_join(dat, by = "GISJOIN") %>%
    mutate(year = as.integer(yr), label = cfg$label) %>%
    select(GISJOIN, year, label, white_share, total_pop)

  out_path <- file.path(OUT, paste0("tracts_", yr, ".geojson"))
  st_write(merged, out_path, delete_dsn = TRUE, quiet = TRUE)
  sz <- round(file.size(out_path) / 1e6, 1)
  message("  Wrote ", out_path, " (", sz, " MB)")
}

message("\nDone.")
