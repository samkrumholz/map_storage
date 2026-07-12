library(sf)

for (yr in c("1940","1970","1990","2000","2010","2020")) {
  g <- st_read(paste0("C:/Users/krumh/Claude/white_map/data/school_", yr, ".geojson"), quiet=TRUE)
  g_df <- as.data.frame(g)
  cat("\n=== Year", yr, "===\n")
  cat("Rows:", nrow(g_df), "\n")
  cat("Cols:", paste(names(g_df), collapse=", "), "\n")
  cat("school_age_share type:", class(g_df$school_age_share), "\n")
  cat("private_school_share type:", class(g_df$private_school_share), "\n")
  cat("school_age_share: median=", round(median(as.numeric(g_df$school_age_share), na.rm=TRUE)*100,1),
      "% NAs=", sum(is.na(g_df$school_age_share)), "\n")
  cat("private_school_share: median=", round(median(as.numeric(g_df$private_school_share), na.rm=TRUE)*100,1),
      "% NAs=", sum(is.na(g_df$private_school_share)), "/", nrow(g_df), "\n")
}
