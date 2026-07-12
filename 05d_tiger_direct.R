# 05d_tiger_direct.R — direct TIGER downloads for 2010 school districts

library(sf)
library(rmapshaper)

OUT <- "C:/Users/krumh/Claude/white_map/data"
tmp <- tempdir()

# Try TIGER 2010 national unified school districts
urls_2010 <- c(
  "https://www2.census.gov/geo/tiger/TIGER2010/UNSD/2010/tl_2010_us_unsd00.zip",
  "https://www2.census.gov/geo/tiger/TIGER2010/SCSD/2010/tl_2010_us_scsd00.zip",
  "https://www2.census.gov/geo/tiger/TIGER2010/ELSD/2010/tl_2010_us_elsd00.zip"
)

parts <- list()
for (url in urls_2010) {
  fname <- basename(url)
  dest  <- file.path(tmp, fname)
  dir_out <- file.path(tmp, tools::file_path_sans_ext(fname))
  cat("Trying:", fname, "\n")
  ok <- tryCatch({
    download.file(url, dest, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) { cat("  HTTP error\n"); FALSE })
  if (!ok) next
  unzip(dest, exdir = dir_out)
  shp <- list.files(dir_out, pattern = "\\.shp$", full.names = TRUE)[1]
  if (!is.na(shp)) {
    obj <- st_read(shp, quiet = TRUE) %>% st_transform(4326)
    # Identify GEOID and NAME columns
    geoid_col <- intersect(c("GEOID10","GEOID","STATEFP10"), names(obj))[1]
    name_col  <- intersect(c("NAME10","NAME"), names(obj))[1]
    type_str  <- if (grepl("unsd", fname)) "unified" else if (grepl("scsd", fname)) "secondary" else "elementary"
    obj <- obj %>% dplyr::transmute(GEOID = as.character(.data[[geoid_col]]),
                                    NAME  = as.character(.data[[name_col]]),
                                    type  = type_str,
                                    geometry)
    parts[[length(parts)+1]] <- obj
    cat("  Got", nrow(obj), "districts\n")
  }
}

if (length(parts) > 0) {
  sd_2010 <- do.call(rbind, parts)
  sd_2010_simp <- ms_simplify(sd_2010, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  out <- file.path(OUT, "school_districts_2010.geojson")
  st_write(sd_2010_simp, out, delete_dsn = TRUE, quiet = TRUE)
  cat("Wrote", out, "\n")
} else {
  cat("No 2010 data — copying 2020 as fallback\n")
  file.copy(file.path(OUT, "school_districts_2020.geojson"),
            file.path(OUT, "school_districts_2010.geojson"), overwrite = TRUE)
}

# Copy for 2000 and pre-2000
cat("Copying 2020 as 2000 fallback\n")
file.copy(file.path(OUT, "school_districts_2020.geojson"),
          file.path(OUT, "school_districts_2000.geojson"), overwrite = TRUE)
for (yr in c("1940","1950","1960","1970","1980","1990")) {
  file.copy(file.path(OUT, "school_districts_2000.geojson"),
            file.path(OUT, paste0("school_districts_", yr, ".geojson")), overwrite = TRUE)
}
cat("Done.\n")
