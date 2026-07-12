# 05c_download_2010_districts.R
# Direct download of 2010 school district cartographic boundary files from Census FTP.

library(sf)
library(rmapshaper)

OUT <- "C:/Users/krumh/Claude/white_map/data"
tmp <- tempdir()

# 2010 cartographic boundary files (1:500k)
# gz_2010_us_970_00_500k.zip = unified
# gz_2010_us_971_00_500k.zip = secondary
# gz_2010_us_972_00_500k.zip = elementary
base_url <- "https://www2.census.gov/geo/tiger/GENZ2010"

parts <- list()
for (code in c("970","971","972")) {
  fname <- paste0("gz_2010_us_", code, "_00_500k.zip")
  url   <- paste0(base_url, "/", fname)
  dest  <- file.path(tmp, fname)
  cat("Downloading", fname, "...\n")
  tryCatch({
    download.file(url, dest, mode = "wb", quiet = FALSE)
    # Unzip
    unzip(dest, exdir = file.path(tmp, code))
    shp <- list.files(file.path(tmp, code), pattern = "\\.shp$", full.names = TRUE)[1]
    if (!is.na(shp)) {
      sf_obj <- st_read(shp, quiet = TRUE)
      # Standardize columns
      sf_obj <- sf_obj %>%
        sf::st_transform(4326) %>%
        dplyr::transmute(
          GEOID = as.character(ifelse("GEOID10" %in% names(.), GEOID10,
                               ifelse("GEOID" %in% names(.), GEOID, NA))),
          NAME  = as.character(ifelse("NAME10" %in% names(.), NAME10,
                               ifelse("NAME" %in% names(.), NAME, NA))),
          type  = c("970"="unified","971"="secondary","972"="elementary")[code],
          geometry
        )
      parts[[code]] <- sf_obj
      cat("  Got", nrow(sf_obj), "districts.\n")
    }
  }, error = function(e) cat("  Failed:", conditionMessage(e), "\n"))
}

if (length(parts) > 0) {
  sd_2010 <- do.call(rbind, parts)
  sd_2010_simp <- ms_simplify(sd_2010, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  out <- file.path(OUT, "school_districts_2010.geojson")
  sf::st_write(sd_2010_simp, out, delete_dsn = TRUE, quiet = TRUE)
  cat("Wrote", out, "\n")
} else {
  cat("No 2010 data downloaded.\n")
}

# 2000 — Census cartographic boundary (1:500k)
# For 2000, try the pre-2000 TIGER paths
cat("\nAttempting 2000 unified school districts...\n")
tryCatch({
  url_2000 <- "https://www2.census.gov/geo/tiger/PREVGENZ/sd/sd99_sd/sd99_d00_shp.zip"
  dest_2000 <- file.path(tmp, "sd00.zip")
  download.file(url_2000, dest_2000, mode = "wb", quiet = FALSE)
  unzip(dest_2000, exdir = file.path(tmp, "sd2000"))
  shp <- list.files(file.path(tmp, "sd2000"), pattern = "\\.shp$", full.names = TRUE)[1]
  if (!is.na(shp)) {
    sd_2000 <- st_read(shp, quiet = TRUE) %>%
      sf::st_transform(4326) %>%
      dplyr::transmute(GEOID = as.character(STFID), NAME = as.character(NAME), type = "unified", geometry)
    sd_2000_simp <- ms_simplify(sd_2000, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
    out <- file.path(OUT, "school_districts_2000.geojson")
    sf::st_write(sd_2000_simp, out, delete_dsn = TRUE, quiet = TRUE)
    cat("Wrote 2000.\n")
  }
}, error = function(e) cat("2000 failed:", conditionMessage(e), "\n"))
