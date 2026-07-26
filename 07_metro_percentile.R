# 07_metro_percentile.R
# Adds, IN PLACE, to each Race and SES GeoJSON:
#   cbsa_id / cbsa_name       : 2020 CBSA (metro/micro area) a tract's centroid falls in
#   <var>_pctile_metro        : percentile rank (0-1) of <var> among all tracts in the
#                               SAME cbsa_id, same year. NA outside any CBSA.
#
# Reference frame decision: every census year (1940-2020) is assigned to *today's*
# (2020) CBSA delineations by point-in-polygon on the tract centroid. This keeps the
# same metro composition across decades for comparability, at the cost of including
# tracts that were rural at the time but are inside a metro's present-day footprint.
#
# Also writes data/cbsa_boundaries.geojson: simplified 2020 CBSA polygons (metro only,
# i.e. NAME containing "Metro Area" - micro areas dropped) for the map's boundary layer.

library(sf)
library(dplyr)
sf_use_s2(FALSE)

BASE <- "C:/Users/krumh/Claude/white_map"
CBSA_SHP <- file.path(BASE, "nhgis_downloads/cbsa/tl_2020_us_cbsa.shp")

cat("Reading CBSA shapefile...\n")
cbsa <- st_read(CBSA_SHP, quiet = TRUE) %>%
  st_transform(4326) %>%
  select(cbsa_id = GEOID, cbsa_name = NAME, LSAD) %>%
  filter(!st_is_empty(geometry))

cat("  ", nrow(cbsa), "CBSAs (metro + micro)\n")

# ── Metro boundary layer (metro areas only, "M1" = metropolitan) ──────────────
metro_only <- cbsa %>% filter(LSAD == "M1") %>% select(cbsa_id, cbsa_name)
cat("Simplifying metro boundaries for display...\n")
metro_simp <- rmapshaper::ms_simplify(metro_only, keep = 0.06, keep_shapes = TRUE, sys = TRUE)
st_write(metro_simp, file.path(BASE, "data/cbsa_boundaries.geojson"), delete_dsn = TRUE, quiet = TRUE)
cat("  Wrote data/cbsa_boundaries.geojson (", nrow(metro_simp), "metro areas)\n")

# ── Assign a CBSA to each tract + compute within-metro percentile ─────────────
add_metro_percentile <- function(path, value_cols) {
  cat("\n", basename(path), "\n")
  geo <- st_read(path, quiet = TRUE)

  cent <- suppressWarnings(st_centroid(st_geometry(geo)))
  hit  <- st_join(st_sf(geometry = cent), cbsa, join = st_within)

  geo$cbsa_id   <- hit$cbsa_id
  geo$cbsa_name <- hit$cbsa_name

  n_in_metro <- sum(!is.na(geo$cbsa_id))
  cat("  ", n_in_metro, "/", nrow(geo), "tracts fall inside a CBSA\n")

  df <- st_drop_geometry(geo)
  for (vc in value_cols) {
    if (!vc %in% names(df)) { cat("  (skip", vc, "- column not found)\n"); next }
    pct_col <- paste0(vc, "_pctile_metro")
    df[[pct_col]] <- NA_real_
    has_metro <- !is.na(df$cbsa_id)
    df[[pct_col]][has_metro] <- ave(
      df[[vc]][has_metro], df$cbsa_id[has_metro],
      FUN = function(x) {
        r <- rep(NA_real_, length(x))
        ok <- !is.na(x)
        if (sum(ok) > 1) r[ok] <- (rank(x[ok], ties.method = "average") - 1) / (sum(ok) - 1)
        else if (sum(ok) == 1) r[ok] <- 0.5
        r
      })
    cat("  ", pct_col, ": ", sum(!is.na(df[[pct_col]])), "tracts scored\n")
  }

  geo <- st_sf(df, geometry = st_geometry(geo))
  st_write(geo, path, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
  cat("  Wrote back", basename(path), "\n")
}

cat("\n=== Race tracts ===\n")
for (yr in c(1940,1950,1960,1970,1980,1990,2000,2010,2020)) {
  path <- file.path(BASE, sprintf("data/tracts_%d.geojson", yr))
  if (file.exists(path)) add_metro_percentile(path, "white_share") else cat("  missing:", path, "\n")
}

cat("\n=== SES tracts ===\n")
for (yr in c(1940,1950,1960,1970,1980,1990,2000,2012,2022)) {
  path <- file.path(BASE, sprintf("data_ses/ses_%d.geojson", yr))
  if (file.exists(path)) add_metro_percentile(path, c("edu_share","hv_2022")) else cat("  missing:", path, "\n")
}

cat("\nAll done.\n")
