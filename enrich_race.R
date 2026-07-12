library(tidyverse)
library(sf)

BASE <- "C:/Users/krumh/Claude/white_map"
DATA <- file.path(BASE, "nhgis_downloads/data")
OUT  <- file.path(BASE, "data")

# For each year: which CSV, which columns map to which race
# black_col/hispanic_col/asian_cols = NULL means that race is NA for this year
race_cfg <- list(
  `1940` = list(
    csv          = "nhgis0330_ds76_1940_tract.csv",
    total_cols   = c("BUQ001","BUQ002"),
    white_col    = "BUQ001",
    black_col    = NULL,
    hispanic_col = NULL,
    asian_cols   = NULL
  ),
  `1950` = list(
    csv          = "nhgis0330_ds82_1950_tract.csv",
    total_cols   = c("B0J001","B0J002","B0J003"),
    white_col    = "B0J001",
    black_col    = "B0J002",
    hispanic_col = NULL,
    asian_cols   = NULL
  ),
  `1960` = list(
    csv          = "nhgis0330_ds92_1960_tract.csv",
    total_cols   = c("B7B001","B7B002","B7B003"),
    white_col    = "B7B001",
    black_col    = "B7B002",
    hispanic_col = NULL,
    asian_cols   = NULL
  ),
  `1970` = list(
    csv          = "nhgis0330_ds98_1970_tract.csv",
    total_cols   = c("C0X001","C0X002","C0X003"),
    white_col    = "C0X001",
    black_col    = "C0X002",
    hispanic_col = NULL,
    asian_cols   = NULL
  ),
  `1980` = list(
    csv          = "nhgis0330_ds107_1980_tract.csv",
    total_cols   = paste0("DFB", sprintf("%03d",1:17)),
    white_col    = "DFB001",
    black_col    = "DFB002",
    hispanic_col = "DFB016",   # "Other: Spanish" — race-based, undercounts true Hispanic pop
    asian_cols   = paste0("DFB", sprintf("%03d",6:15))
  ),
  `1990` = list(
    csv          = "nhgis0330_ds123_1990_tract.csv",
    total_cols   = paste0("E1A", sprintf("%03d",1:10)),
    white_col    = "E1A001",
    black_col    = c("E1A002","E1A007"),
    hispanic_col = paste0("E1A", sprintf("%03d",6:10)),
    asian_cols   = c("E1A004","E1A009")
  ),
  `2000` = list(
    csv          = "nhgis0330_ds151_2000_tract.csv",
    total_cols   = paste0("GHJ", sprintf("%03d",1:14)),
    white_col    = "GHJ001",
    black_col    = c("GHJ002","GHJ009"),
    hispanic_col = paste0("GHJ", sprintf("%03d",8:14)),
    asian_cols   = c("GHJ004","GHJ005","GHJ011","GHJ012")
  ),
  `2010` = list(
    csv          = "nhgis0330_ds172_2010_tract.csv",
    total_cols   = "H7Z001",
    white_col    = "H7Z003",
    black_col    = c("H7Z004","H7Z012"),
    hispanic_col = "H7Z010",
    asian_cols   = c("H7Z006","H7Z007","H7Z014","H7Z015")
  ),
  `2020` = list(
    csv          = "nhgis0330_ds258_2020_tract.csv",
    total_cols   = "U7L001",
    white_col    = "U7L003",
    black_col    = c("U7L004","U7L012"),
    hispanic_col = "U7L010",
    asian_cols   = c("U7L006","U7L007","U7L014","U7L015")
  )
)

safe_sum <- function(df, cols) {
  cols <- intersect(cols, names(df))
  if (!length(cols)) return(rep(NA_real_, nrow(df)))
  rowSums(df[cols], na.rm = TRUE)
}

for (yr in names(race_cfg)) {
  message("\n=== ", yr, " ===")
  cfg <- race_cfg[[yr]]

  geojson_path <- file.path(OUT, paste0("tracts_", yr, ".geojson"))
  if (!file.exists(geojson_path)) { message("  GeoJSON missing, skip."); next }

  csv_path <- file.path(DATA, cfg$csv)
  if (!file.exists(csv_path)) { message("  CSV missing: ", cfg$csv); next }

  geom <- st_read(geojson_path, quiet = TRUE)
  dat  <- read_csv(csv_path, show_col_types = FALSE)

  total_pop    <- safe_sum(dat, cfg$total_cols)
  white_pop    <- safe_sum(dat, cfg$white_col)
  black_pop    <- if (!is.null(cfg$black_col))    safe_sum(dat, cfg$black_col)    else rep(NA_real_, nrow(dat))
  hispanic_pop <- if (!is.null(cfg$hispanic_col)) safe_sum(dat, cfg$hispanic_col) else rep(NA_real_, nrow(dat))
  asian_pop    <- if (!is.null(cfg$asian_cols))   safe_sum(dat, cfg$asian_cols)   else rep(NA_real_, nrow(dat))

  race_dat <- tibble(
    GISJOIN        = dat$GISJOIN,
    total_pop      = total_pop,
    white_share    = if_else(total_pop > 0, white_pop    / total_pop, NA_real_),
    black_share    = if_else(total_pop > 0 & !is.na(black_pop),    black_pop    / total_pop, NA_real_),
    hispanic_share = if_else(total_pop > 0 & !is.na(hispanic_pop), hispanic_pop / total_pop, NA_real_),
    asian_share    = if_else(total_pop > 0 & !is.na(asian_pop),    asian_pop    / total_pop, NA_real_)
  )

  updated <- geom %>%
    select(GISJOIN) %>%
    left_join(race_dat, by = "GISJOIN") %>%
    mutate(year = as.integer(yr))

  matched <- sum(!is.na(updated$white_share))
  message("  Matched: ", matched, "/", nrow(updated))
  if (matched > 0) {
    message("  white_share: ", round(min(updated$white_share, na.rm=TRUE),3),
            " – ", round(max(updated$white_share, na.rm=TRUE),3))
    if (!all(is.na(updated$black_share)))
      message("  black_share: ", round(min(updated$black_share, na.rm=TRUE),3),
              " – ", round(max(updated$black_share, na.rm=TRUE),3))
  }

  st_write(updated, geojson_path, delete_dsn = TRUE, quiet = TRUE)
  message("  Wrote ", round(file.size(geojson_path)/1e6,1), " MB")
}

message("\nAll done.")
