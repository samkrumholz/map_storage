library(sf)
sf_use_s2(FALSE)  # simplified polygons have duplicate vertices that fail S2; GEOS is fine here

# Pre-compute, for each tract:
#   max_white_diff  : max |white_share_i - white_share_j| over all touching neighbors j
#   max_hv_ratio    : max(hv_i, hv_j) / min(hv_i, hv_j) over touching neighbors where both hv > 0
#
# These properties are added to each GeoJSON file in place so that the map can
# apply a simple attribute filter without any client-side geometry computation.

compute_and_write <- function(path, value_col, out_col, transform_fn) {
  cat(sprintf("  Reading %s...\n", basename(path)))
  geo <- st_read(path, quiet=TRUE)
  n   <- nrow(geo)
  cat(sprintf("  %d features. Computing adjacency (st_touches)...\n", n))

  vals <- as.numeric(geo[[value_col]])

  adj <- st_touches(geo, sparse=TRUE)

  # Build edge list: pairs (i, j) where j is in adj[[i]]
  cat("  Building edge list...\n")
  i_vec <- rep(seq_len(n), lengths(adj))
  j_vec <- unlist(adj, use.names=FALSE)

  result <- rep(NA_real_, n)

  if (length(i_vec) > 0) {
    # Compute the pairwise statistic for each edge
    edge_stat <- transform_fn(vals[i_vec], vals[j_vec])

    # Keep only valid edges
    valid  <- !is.na(edge_stat)
    i_v    <- i_vec[valid]
    s_v    <- edge_stat[valid]

    if (length(i_v) > 0) {
      # For each i, take the max stat over all neighbors
      result_named <- tapply(s_v, i_v, max)
      result[as.integer(names(result_named))] <- as.numeric(result_named)
    }
  }

  geo[[out_col]] <- round(result, 4)
  cat(sprintf("  Writing back... (above threshold: %d / %d)\n",
              sum(result >= ifelse(out_col=="max_white_diff", 0.40, 1.50), na.rm=TRUE), n))
  st_write(geo, path, driver="GeoJSON", delete_dsn=TRUE, quiet=TRUE)
  cat(sprintf("  Done. %s range: [%.3f, %.3f]\n", out_col,
              min(result, na.rm=TRUE), max(result, na.rm=TRUE)))
}

# ── 1. Race GeoJSONs ──────────────────────────────────────────────────────────
race_years <- c(1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020)

white_diff_fn <- function(vi, vj) {
  d <- abs(vi - vj)
  d[is.na(vi) | is.na(vj)] <- NA_real_
  d
}

for (yr in race_years) {
  cat(sprintf("\n=== Race %d ===\n", yr))
  path <- sprintf("C:/Users/krumh/Claude/white_map/data/tracts_%d.geojson", yr)
  compute_and_write(path, "white_share", "max_white_diff", white_diff_fn)
}

# ── 2. SES GeoJSONs ───────────────────────────────────────────────────────────
ses_years <- c(1940, 1950, 1960, 1970, 1980, 1990, 2000, 2012, 2022)

hv_ratio_fn <- function(vi, vj) {
  r <- pmax(vi, vj) / pmin(vi, vj)
  r[is.na(vi) | is.na(vj) | vi <= 0 | vj <= 0] <- NA_real_
  r
}

for (yr in ses_years) {
  cat(sprintf("\n=== SES %d ===\n", yr))
  path <- sprintf("C:/Users/krumh/Claude/white_map/data_ses/ses_%d.geojson", yr)
  compute_and_write(path, "hv_2022", "max_hv_ratio", hv_ratio_fn)
}

cat("\nAll done.\n")
