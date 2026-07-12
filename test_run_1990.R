library(tidyverse)
library(sf)
library(rmapshaper)

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

year_config <- list(
  `1990` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/1990"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*1990*tract*.csv"),
    nh_white     = TRUE,
    total_as_sum = TRUE,
    white_pat    = "Not.{0,15}Hispanic.{0,15}White",
    label        = NULL
  ),
  `2000` = list(
    shp_dir      = file.path(BASE, "nhgis_downloads/shapefiles/2000"),
    csv_glob     = file.path(BASE, "nhgis_downloads/data/*2000*tract*.csv"),
    nh_white     = TRUE,
    total_as_sum = TRUE,
    white_pat    = "Not Hispanic.{0,30}White alone",
    label        = NULL
  )
)

process_year <- function(yr, cfg) {
  message("\n=== ", yr, " ===")

  csv_files <- Sys.glob(cfg$csv_glob)
  if (!length(csv_files)) stop("No CSV found matching: ", cfg$csv_glob)

  csv_file <- NULL; cb_file <- NULL; vars <- NULL
  total_col <- NA_character_; white_col <- NA_character_

  for (cf in sort(csv_files)) {
    cb <- str_replace(cf, "\\.csv$", "_codebook.txt")
    if (!file.exists(cb)) next
    v  <- parse_codebook(cb)
    wc <- find_var(v, cfg$white_pat)
    if (is.na(wc)) next
    tc <- if (isTRUE(cfg$total_as_sum)) NA_character_ else find_var(v, cfg$total_pat)
    if (!isTRUE(cfg$total_as_sum) && is.na(tc)) next
    csv_file <- cf; cb_file <- cb; vars <- v
    total_col <- tc; white_col <- wc
    break
  }

  if (is.null(csv_file)) stop("No suitable CSV found for ", yr)

  message("  CSV:   ", basename(csv_file))
  message("  white: ", white_col)

  dat_raw <- read_csv(csv_file, show_col_types = FALSE)
  message("  dat_raw rows: ", nrow(dat_raw), " | cols: ", ncol(dat_raw))

  white_prefix <- substr(white_col, 1, 3)
  race_cols    <- names(dat_raw)[grepl(paste0("^", white_prefix, "[0-9]"), names(dat_raw))]
  message("  race_cols: ", paste(race_cols, collapse=", "))

  dat <- dat_raw %>%
    mutate(
      total_pop = rowSums(select(., all_of(race_cols)), na.rm = TRUE),
      white_pop = .data[[white_col]]
    ) %>%
    select(GISJOIN, total_pop, white_pop) %>%
    mutate(white_share = if_else(total_pop > 0, white_pop / total_pop, NA_real_))

  message("  dat rows: ", nrow(dat), " | white_share range: ",
          round(min(dat$white_share, na.rm=TRUE), 3), " – ",
          round(max(dat$white_share, na.rm=TRUE), 3))

  shp_files <- list.files(cfg$shp_dir, "\\.shp$", full.names = TRUE)
  message("  shp files: ", length(shp_files), " | ", basename(shp_files[1]))
  shp <- st_read(shp_files[1], quiet = TRUE)
  message("  shp rows: ", nrow(shp), " | GISJOIN present: ", "GISJOIN" %in% names(shp))

  default_label <- if_else(isTRUE(cfg$nh_white), "NH-White share", "White share (incl. Hispanic)")
  row_label <- if (!is.null(cfg$label)) cfg$label else default_label

  merged <- shp %>%
    left_join(dat, by = "GISJOIN") %>%
    mutate(year = as.integer(yr), label = row_label) %>%
    select(GISJOIN, year, label, white_share, total_pop)

  message("  merged rows: ", nrow(merged))
  message("  Simplifying (st_simplify)...")
  merged <- merged %>%
    st_transform(4326) %>%
    st_make_valid() %>%
    st_simplify(preserveTopology = TRUE, dTolerance = 0.02)

  out_path <- file.path(OUT, paste0("tracts_", yr, ".geojson"))
  st_write(merged, out_path, delete_dsn = TRUE, quiet = TRUE)
  sz <- round(file.size(out_path) / 1e6, 1)
  message("  Wrote ", out_path, " (", sz, " MB)")
  invisible(merged)
}

for (yr in names(year_config)) {
  tryCatch(
    process_year(yr, year_config[[yr]]),
    error = function(e) message("ERROR for ", yr, ": ", e$message)
  )
}
message("\nDone.")
