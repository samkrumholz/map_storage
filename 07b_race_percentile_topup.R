# 07b_race_percentile_topup.R
# tracts_YYYY.geojson already has cbsa_id/cbsa_name and white_share_pctile_metro
# (written by 07_metro_percentile.R). This adds the same within-metro percentile
# for the other three race shares, reusing the existing cbsa_id (no re-join needed).

library(sf)

BASE <- "C:/Users/krumh/Claude/white_map"
VARS <- c("black_share","hispanic_share","asian_share")

pctile_within <- function(x, grp) {
  r <- rep(NA_real_, length(x))
  ok <- !is.na(x) & !is.na(grp)
  if (!any(ok)) return(r)
  r[ok] <- ave(x[ok], grp[ok], FUN = function(v) {
    rr <- rep(NA_real_, length(v))
    vok <- !is.na(v)
    if (sum(vok) > 1) rr[vok] <- (rank(v[vok], ties.method = "average") - 1) / (sum(vok) - 1)
    else if (sum(vok) == 1) rr[vok] <- 0.5
    rr
  })
  r
}

for (yr in c(1940,1950,1960,1970,1980,1990,2000,2010,2020)) {
  path <- file.path(BASE, sprintf("data/tracts_%d.geojson", yr))
  cat("\n", basename(path), "\n")
  geo <- st_read(path, quiet = TRUE)
  if (!"cbsa_id" %in% names(geo)) { cat("  no cbsa_id, skip (run 07_metro_percentile.R first)\n"); next }
  for (vc in VARS) {
    if (!vc %in% names(geo)) { cat("  (skip", vc, "- not present this year)\n"); next }
    pct_col <- paste0(vc, "_pctile_metro")
    geo[[pct_col]] <- pctile_within(geo[[vc]], geo$cbsa_id)
    cat("  ", pct_col, ": ", sum(!is.na(geo[[pct_col]])), "tracts scored\n")
  }
  st_write(geo, path, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
  cat("  Wrote back", basename(path), "\n")
}
cat("\nDone.\n")
