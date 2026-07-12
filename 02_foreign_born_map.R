library(tidyverse)
library(sf)

BASE   <- "C:/Users/krumh/Claude/white_map"
SRC    <- BASE                              # nhgis0333 CSVs are in white_map/
RACE   <- file.path(BASE, "nhgis_downloads/data")  # denominators for 1940-1970
GEOM   <- file.path(BASE, "data")          # geometry GeoJSONs
OUT    <- file.path(BASE, "data_fb")
dir.create(OUT, showWarnings = FALSE)

build_geojson <- function(fb_pop, total_pop, gisjoin, geom_path, yr_label) {
  geom <- st_read(geom_path, quiet = TRUE) |> select(GISJOIN)
  dat  <- tibble(
    GISJOIN   = gisjoin,
    fb_share  = round(if_else(total_pop > 0, fb_pop / total_pop, NA_real_), 4)
  )
  matched <- sum(!is.na(dat$fb_share))
  out <- geom |>
    left_join(dat, by = "GISJOIN") |>
    mutate(year = as.integer(yr_label))
  message(sprintf("  %d: %d/%d rows matched", yr_label, matched, nrow(dat)))
  path <- file.path(OUT, paste0("fb_", yr_label, ".geojson"))
  st_write(out, path, delete_dsn = TRUE, quiet = TRUE)
  message(sprintf("  Wrote %s (%.1f MB)", basename(path), file.size(path)/1e6))
}

read_csv_c <- function(path) read_csv(path, col_types = cols(.default = "c"),
                                      show_col_types = FALSE)

# ── 1940: FB White (BUG001:066) / total pop (BUQ001+BUQ002) ──────────────────
message("=== 1940 ===")
fb40  <- read_csv_c(file.path(SRC,  "nhgis0333_ds76_1940_tract.csv"))
pop40 <- read_csv_c(file.path(RACE, "nhgis0330_ds76_1940_tract.csv"))
bug_cols <- paste0("BUG", sprintf("%03d", 1:66))
fb40  <- fb40  |> mutate(fb_pop = rowSums(across(all_of(bug_cols), as.numeric), na.rm=TRUE))
pop40 <- pop40 |> mutate(total  = as.numeric(BUQ001) + as.numeric(BUQ002))
d40   <- inner_join(select(fb40, GISJOIN, fb_pop), select(pop40, GISJOIN, total), by="GISJOIN")
build_geojson(d40$fb_pop, d40$total, d40$GISJOIN,
              file.path(GEOM, "tracts_1940.geojson"), 1940)

# ── 1950: FB White (B1K001) / total pop (B0J001+B0J002+B0J003) ───────────────
message("=== 1950 ===")
fb50  <- read_csv_c(file.path(SRC,  "nhgis0333_ds82_1950_tract.csv"))
pop50 <- read_csv_c(file.path(RACE, "nhgis0330_ds82_1950_tract.csv"))
pop50 <- pop50 |> mutate(total = as.numeric(B0J001)+as.numeric(B0J002)+as.numeric(B0J003))
d50   <- inner_join(
  transmute(fb50, GISJOIN, fb_pop = as.numeric(B1K001)),
  select(pop50, GISJOIN, total), by="GISJOIN")
build_geojson(d50$fb_pop, d50$total, d50$GISJOIN,
              file.path(GEOM, "tracts_1950.geojson"), 1950)

# ── 1960: FB (B8J001) / total pop (B7B001+B7B002+B7B003) ────────────────────
message("=== 1960 ===")
fb60  <- read_csv_c(file.path(SRC,  "nhgis0333_ds92_1960_tract.csv"))
pop60 <- read_csv_c(file.path(RACE, "nhgis0330_ds92_1960_tract.csv"))
pop60 <- pop60 |> mutate(total = as.numeric(B7B001)+as.numeric(B7B002)+as.numeric(B7B003))
d60   <- inner_join(
  transmute(fb60, GISJOIN, fb_pop = as.numeric(B8J001)),
  select(pop60, GISJOIN, total), by="GISJOIN")
build_geojson(d60$fb_pop, d60$total, d60$GISJOIN,
              file.path(GEOM, "tracts_1960.geojson"), 1960)

# ── 1970: FB (C13001:005) / total pop (C0X001+002+003 from ds98) ─────────────
message("=== 1970 ===")
fb70  <- read_csv_c(file.path(SRC,  "nhgis0333_ds99_1970_tract.csv"))
pop70 <- read_csv_c(file.path(RACE, "nhgis0330_ds98_1970_tract.csv"))
c13_cols <- paste0("C13", sprintf("%03d", 1:5))
fb70  <- fb70  |> mutate(fb_pop = rowSums(across(all_of(c13_cols), as.numeric), na.rm=TRUE))
pop70 <- pop70 |> mutate(total  = as.numeric(C0X001)+as.numeric(C0X002)+as.numeric(C0X003))
d70   <- inner_join(select(fb70, GISJOIN, fb_pop), select(pop70, GISJOIN, total), by="GISJOIN")
build_geojson(d70$fb_pop, d70$total, d70$GISJOIN,
              file.path(GEOM, "tracts_1970.geojson"), 1970)

# ── 1980: FB (DG6004) / total (DG6001+002+003+004) — self-contained ──────────
message("=== 1980 ===")
fb80 <- read_csv_c(file.path(SRC, "nhgis0333_ds107_1980_tract.csv"))
fb80 <- fb80 |> mutate(
  fb_pop = as.numeric(DG6004),
  total  = as.numeric(DG6001)+as.numeric(DG6002)+as.numeric(DG6003)+as.numeric(DG6004))
build_geojson(fb80$fb_pop, fb80$total, fb80$GISJOIN,
              file.path(GEOM, "tracts_1980.geojson"), 1980)

# ── 1990: FB (E3N009) / total (E3N001:009) — self-contained ──────────────────
message("=== 1990 ===")
fb90 <- read_csv_c(file.path(SRC, "nhgis0333_ds123_1990_tract.csv"))
e3n_cols <- paste0("E3N", sprintf("%03d", 1:9))
fb90 <- fb90 |> mutate(
  fb_pop = as.numeric(E3N009),
  total  = rowSums(across(all_of(e3n_cols), as.numeric), na.rm=TRUE))
build_geojson(fb90$fb_pop, fb90$total, fb90$GISJOIN,
              file.path(GEOM, "vacancy_1990.geojson"), 1990)

# ── 2000: FB (GI8002) / total (GI8001+GI8002) — self-contained ───────────────
message("=== 2000 ===")
fb00 <- read_csv_c(file.path(SRC, "nhgis0333_ds151_2000_tract.csv"))
fb00 <- fb00 |> mutate(
  fb_pop = as.numeric(GI8002),
  total  = as.numeric(GI8001)+as.numeric(GI8002))
build_geojson(fb00$fb_pop, fb00$total, fb00$GISJOIN,
              file.path(GEOM, "vacancy_2000.geojson"), 2000)

# ── 2012 ACS: FB (Q2YE013) / total (Q2YE001) — 2010 tract vintage ────────────
message("=== 2012 ===")
fb12 <- read_csv_c(file.path(SRC, "nhgis0333_ds192_20125_tract.csv"))
fb12 <- fb12 |> mutate(
  fb_pop = as.numeric(Q2YE013),
  total  = as.numeric(Q2YE001))
build_geojson(fb12$fb_pop, fb12$total, fb12$GISJOIN,
              file.path(GEOM, "tracts_2010.geojson"), 2012)

# ── 2022 ACS: FB (AQZQE003) / total (AQZQE001) — 2020 tract vintage ──────────
message("=== 2022 ===")
fb22 <- read_csv_c(file.path(SRC, "nhgis0333_ds263_20225_tract.csv"))
fb22 <- fb22 |> mutate(
  fb_pop = as.numeric(AQZQE003),
  total  = as.numeric(AQZQE001))
build_geojson(fb22$fb_pop, fb22$total, fb22$GISJOIN,
              file.path(GEOM, "tracts_2020.geojson"), 2022)

message("\nAll done. GeoJSONs in ", OUT)
