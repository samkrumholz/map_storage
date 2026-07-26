# 08_zhvi_zcta.R
# Zillow ZHVI (zip-level home value index), one December snapshot per year
# 2000-2025 plus the latest available month, joined to 2020 ZCTA5 boundaries.
# Single GeoJSON with one zhvi_<year> property per year (geometry is static,
# so there's no need to repeat it per year the way census tracts do).
#
# ZHVI as published by Zillow is NOMINAL (current) dollars -- not inflation-adjusted.
# Deflated here to real 2022$ (CPI-U NSA, FRED series CPIAUCNS, December value each
# year) so it lines up with hv_2022, the Census tract home-value field, which is
# already expressed in constant 2022 dollars.

library(sf)
library(dplyr)
library(readr)
library(stringr)
sf_use_s2(FALSE)

BASE <- "C:/Users/krumh/Claude/white_map"
CSV  <- file.path(BASE, "zillow_downloads/zhvi_zip.csv")
OUT_DIR  <- file.path(BASE, "data_zillow")
dir.create(OUT_DIR, showWarnings = FALSE)

cat("Reading Zillow ZHVI CSV...\n")
dat <- read_csv(CSV, show_col_types = FALSE)
cat("  ", nrow(dat), "zips,", ncol(dat), "columns\n")

date_cols <- names(dat)[str_detect(names(dat), "^\\d{4}-\\d{2}-\\d{2}$")]
all_years <- 2000:2025
latest_col <- date_cols[length(date_cols)]
latest_year <- as.integer(str_sub(latest_col, 1, 4))
latest_month <- str_sub(latest_col, 6, 7)

zhvi_wide <- dat %>% select(RegionName)
for (yr in all_years) {
  col <- paste0(yr, "-12-31")
  if (col %in% names(dat)) {
    zhvi_wide[[paste0("zhvi_", yr)]] <- dat[[col]]
  } else {
    cat("  (no Dec column for", yr, ", skipping)\n")
  }
}
# Latest partial year (if not already Dec of a captured year)
if (!(paste0(latest_year, "-12-31") %in% names(dat))) {
  zhvi_wide[[paste0("zhvi_", latest_year, "_latest")]] <- dat[[latest_col]]
  cat("  Added partial latest snapshot: zhvi_", latest_year, "_latest (", latest_col, ")\n", sep="")
}

zhvi_wide$zip <- str_pad(as.character(zhvi_wide$RegionName), 5, pad = "0")
zhvi_wide <- zhvi_wide %>% select(-RegionName)

# Deflate to real 2022$ (CPI-U NSA, December each year, FRED CPIAUCNS)
cat("\nDeflating to real 2022$ (CPI-U NSA)...\n")
cpi_dec <- c(
  `2000`=174.000, `2001`=176.700, `2002`=180.900, `2003`=184.300, `2004`=190.300,
  `2005`=196.800, `2006`=201.800, `2007`=210.036, `2008`=210.228, `2009`=215.949,
  `2010`=219.179, `2011`=225.672, `2012`=229.601, `2013`=233.049, `2014`=234.812,
  `2015`=236.525, `2016`=241.432, `2017`=246.524, `2018`=251.233, `2019`=256.974,
  `2020`=260.474, `2021`=278.802, `2022`=296.797, `2023`=306.746, `2024`=315.605,
  `2025`=324.054
)
cpi_latest <- 333.952  # June 2026, matches the zhvi_2026_latest snapshot month
cpi_base   <- cpi_dec[["2022"]]
for (yr in all_years) {
  col <- paste0("zhvi_", yr)
  if (col %in% names(zhvi_wide)) {
    zhvi_wide[[col]] <- zhvi_wide[[col]] * (cpi_base / cpi_dec[[as.character(yr)]])
  }
}
if ("zhvi_2026_latest" %in% names(zhvi_wide)) {
  zhvi_wide[["zhvi_2026_latest"]] <- zhvi_wide[["zhvi_2026_latest"]] * (cpi_base / cpi_latest)
}

# Pre-simplified via the mapshaper CLI directly on the raw .shp (same fix used for the
# 1990/2000 census tract shapefiles -- see notes.md: R's GeoJSON round-trip through
# rmapshaper::ms_simplify() chokes on nationwide full-resolution TIGER geometry, but the
# CLI operating on the shapefile directly took 23 sec):
#   mapshaper -i tl_2020_us_zcta520.shp -simplify 3% weighting=0.7 keep-shapes \
#     -o data_zillow/zcta_simplified.shp format=shapefile
ZCTA_SIMP_SHP <- file.path(BASE, "data_zillow/zcta_simplified.shp")

cat("\nReading pre-simplified ZCTA shapefile...\n")
zcta <- st_read(ZCTA_SIMP_SHP, quiet = TRUE) %>%
  st_transform(4326) %>%
  select(zip = ZCTA5CE20) %>%
  filter(!st_is_empty(geometry))
cat("  ", nrow(zcta), "ZCTAs\n")

cat("Joining ZHVI to simplified ZCTA polygons...\n")
merged <- zcta %>% left_join(zhvi_wide, by = "zip")
matched <- sum(!is.na(merged$zhvi_2022))
cat("  Matched (has zhvi_2022):", matched, "/", nrow(merged), "\n")

out_path <- file.path(OUT_DIR, "zhvi_zcta.geojson")
st_write(merged, out_path, delete_dsn = TRUE, quiet = TRUE)
cat("\nWrote", out_path, "(", round(file.size(out_path)/1e6,1), "MB )\n")

year_cols <- names(merged)[str_detect(names(merged), "^zhvi_")]
cat("Year fields:", paste(year_cols, collapse=", "), "\n")
