# 05_school_map.R
# Builds school_YYYY.geojson with:
#   school_age_share  = pop 5-17 / total_pop
#   private_school_share = private K-12 enrolled / (public + private K-12 enrolled)
# Also downloads and saves school district boundary GeoJSONs for 2000/2010/2020.

library(tidyverse)
library(sf)
library(rmapshaper)
library(tigris)

BASE <- "C:/Users/krumh/Claude/white_map"
OUT  <- file.path(BASE, "data")
D34  <- file.path(BASE, "data/nhgis0334_extract/nhgis0334_csv")
D35  <- file.path(BASE, "data/nhgis0335_extract/nhgis0335_csv")

options(tigris_use_cache = TRUE)

# ── helpers ───────────────────────────────────────────────────────────────────
read_csv2 <- function(path) read_csv(path, show_col_types = FALSE)

safe_share <- function(num, den) {
  s <- num / den
  s[!is.finite(s) | den == 0] <- NA_real_
  s
}

# ── School-age population (5-17) by year ─────────────────────────────────────

age_1940 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds76_1940_tract.csv"))
  # BUJ: 5-9 (002+018), 10-14 (003+019), 15-19 (004+020) — approximate 5-17 as 5-14 + 3/5*(15-19)
  d %>% transmute(
    GISJOIN,
    pop_5_17 = (BUJ002+BUJ018) + (BUJ003+BUJ019) + 0.6*(BUJ004+BUJ020),
    approx_age = TRUE
  )
}

age_1950 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds82_1950_tract.csv"))
  # B0H: same structure as 1940
  d %>% transmute(
    GISJOIN,
    pop_5_17 = (B0H002+B0H018) + (B0H003+B0H019) + 0.6*(B0H004+B0H020),
    approx_age = TRUE
  )
}

age_1960 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds92_1960_tract.csv"))
  # B8D: single year, 5yr=011/012 through 17yr=035/036 (male/female pairs)
  d %>% transmute(
    GISJOIN,
    pop_5_17 = B8D011+B8D012 + B8D013+B8D014 + B8D015+B8D016 +
               B8D017+B8D018 + B8D019+B8D020 + B8D021+B8D022 +
               B8D023+B8D024 + B8D025+B8D026 + B8D027+B8D028 +
               B8D029+B8D030 + B8D031+B8D032 + B8D033+B8D034 +
               B8D035+B8D036,
    approx_age = FALSE
  )
}

age_1970 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds95_1970_tract.csv"))
  # CE6: single year, male 5-17 = CE6006:CE6018, female 5-17 = CE6107:CE6119
  male_vars   <- paste0("CE6", sprintf("%03d", 6:18))
  female_vars <- paste0("CE6", sprintf("%03d", 107:119))
  d %>% transmute(
    GISJOIN,
    pop_5_17 = rowSums(across(all_of(male_vars))) + rowSums(across(all_of(female_vars))),
    approx_age = FALSE
  )
}

age_1980 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds104_1980_tract.csv"))
  # C67: total (not by sex): 5=C67004, 6=C67005, 7-9=C67006, 10-13=C67007,
  #      14=C67008, 15=C67009, 16=C67010, 17=C67011
  d %>% transmute(
    GISJOIN,
    pop_5_17 = C67004 + C67005 + C67006 + C67007 + C67008 + C67009 + C67010 + C67011,
    approx_age = FALSE
  )
}

age_1990 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds120_1990_tract.csv"))
  # ET3: 5=ET3004, 6=ET3005, 7-9=ET3006, 10-11=ET3007, 12-13=ET3008,
  #      14=ET3009, 15=ET3010, 16=ET3011, 17=ET3012
  d %>% transmute(
    GISJOIN,
    pop_5_17 = ET3004 + ET3005 + ET3006 + ET3007 + ET3008 + ET3009 + ET3010 + ET3011 + ET3012,
    approx_age = FALSE
  )
}

age_2000 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds146_2000_tract.csv"))
  # FMZ: male 5-9=FMZ002, 10-14=FMZ003, 15-17=FMZ004; female 25-27=FMZ025/026/027
  d %>% transmute(
    GISJOIN,
    pop_5_17 = FMZ002 + FMZ003 + FMZ004 + FMZ025 + FMZ026 + FMZ027,
    approx_age = FALSE
  )
}

age_2010 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds172_2010_tract.csv"))
  # H76: male 5-9=H76004, 10-14=H76005, 15-17=H76006; female H76028/H76029/H76030
  d %>% transmute(
    GISJOIN,
    pop_5_17 = H76004 + H76005 + H76006 + H76028 + H76029 + H76030,
    approx_age = FALSE
  )
}

age_2020 <- function() {
  d <- read_csv2(file.path(D35, "nhgis0335_ds259_2020_tract.csv"))
  # VCG: single year; male 5-17 = VCG008:VCG020, female 5-17 = VCG112:VCG124
  male_vars   <- paste0("VCG", sprintf("%03d", 8:20))
  female_vars <- paste0("VCG", sprintf("%03d", 112:124))
  d %>% transmute(
    GISJOIN,
    pop_5_17 = rowSums(across(all_of(male_vars))) + rowSums(across(all_of(female_vars))),
    approx_age = FALSE
  )
}

# ── Private school share by year ──────────────────────────────────────────────
# Returns tibble(GISJOIN, private_K12, public_K12)
# Returns NULL if data not available for that year.

priv_1970 <- function() {
  d <- read_csv2(file.path(D34, "nhgis0334_ds99_1970_tract.csv"))
  # C2I: K pub=C2I004, K par=C2I005, K priv=C2I006
  #      Elem pub=C2I007, Elem par=C2I008, Elem priv=C2I009
  #      HS pub=C2I010, HS par=C2I011, HS priv=C2I012
  d %>% transmute(
    GISJOIN,
    private_K12 = C2I005+C2I006 + C2I008+C2I009 + C2I011+C2I012,
    public_K12  = C2I004 + C2I007 + C2I010
  )
}

priv_1990 <- function() {
  d <- read_csv2(file.path(D34, "nhgis0334_ds123_1990_tract.csv"))
  # E30: elem/HS public=E30003, elem/HS private=E30004
  d %>% transmute(
    GISJOIN,
    private_K12 = E30004,
    public_K12  = E30003
  )
}

priv_2000 <- function() {
  d <- read_csv2(file.path(D34, "nhgis0334_ds151_2000_tract.csv"))
  # GKP: K pub/priv = GKP003/GKP004 (M), GKP017/GKP018 (F)
  #      1-4 pub/priv = GKP005/GKP006 (M), GKP019/GKP020 (F)
  #      5-8 pub/priv = GKP007/GKP008 (M), GKP021/GKP022 (F)
  #      9-12 pub/priv = GKP009/GKP010 (M), GKP023/GKP024 (F)
  d %>% transmute(
    GISJOIN,
    private_K12 = GKP004+GKP006+GKP008+GKP010 + GKP018+GKP020+GKP022+GKP024,
    public_K12  = GKP003+GKP005+GKP007+GKP009 + GKP017+GKP019+GKP021+GKP023
  )
}

priv_2010 <- function() {
  # Use 2010-2014 ACS (ABCR) — 2010-era tract boundaries
  d <- read_csv2(file.path(D34, "nhgis0334_ds206_20145_tract.csv"))
  # ABCR: by level (K, 1-4, 5-8, 9-12) × sex × pub/priv
  # Male: K pub=ABCRE008, K priv=ABCRE009; 1-4 pub=ABCRE011, priv=ABCRE012
  #       5-8 pub=ABCRE014, priv=ABCRE015; 9-12 pub=ABCRE017, priv=ABCRE018
  # Female: K pub=ABCRE032, priv=ABCRE033; 1-4 pub=ABCRE035, priv=ABCRE036
  #         5-8 pub=ABCRE038, priv=ABCRE039; 9-12 pub=ABCRE041, priv=ABCRE042
  d %>% transmute(
    GISJOIN,
    private_K12 = ABCRE009+ABCRE012+ABCRE015+ABCRE018 + ABCRE033+ABCRE036+ABCRE039+ABCRE042,
    public_K12  = ABCRE008+ABCRE011+ABCRE014+ABCRE017 + ABCRE032+ABCRE035+ABCRE038+ABCRE041
  )
}

priv_2020 <- function() {
  # Use 2020-2024 ACS (AU69) — 2020-era tract boundaries
  d <- read_csv2(file.path(D34, "nhgis0334_ds273_20245_tract.csv"))
  # AU69: by age (5-9, 10-14, 15-17) × sex × pub/priv
  # Male pub 5-9=AU69E005, 10-14=AU69E006, 15-17=AU69E007
  # Male priv 5-9=AU69E014, 10-14=AU69E015, 15-17=AU69E016
  # Female pub 5-9=AU69E033, 10-14=AU69E034, 15-17=AU69E035
  # Female priv 5-9=AU69E042, 10-14=AU69E043, 15-17=AU69E044
  d %>% transmute(
    GISJOIN,
    private_K12 = AU69E014+AU69E015+AU69E016 + AU69E042+AU69E043+AU69E044,
    public_K12  = AU69E005+AU69E006+AU69E007 + AU69E033+AU69E034+AU69E035
  )
}

# ── Build GeoJSONs ────────────────────────────────────────────────────────────

age_fns  <- list(
  `1940` = age_1940, `1950` = age_1950, `1960` = age_1960,
  `1970` = age_1970, `1980` = age_1980, `1990` = age_1990,
  `2000` = age_2000, `2010` = age_2010, `2020` = age_2020
)
priv_fns <- list(
  `1970` = priv_1970, `1990` = priv_1990,
  `2000` = priv_2000, `2010` = priv_2010, `2020` = priv_2020
)

YEARS <- c("1940","1950","1960","1970","1980","1990","2000","2010","2020")

for (yr in YEARS) {
  cat("Processing", yr, "...\n")
  geojson_path <- file.path(OUT, paste0("tracts_", yr, ".geojson"))
  out_path     <- file.path(OUT, paste0("school_", yr, ".geojson"))

  geo <- st_read(geojson_path, quiet = TRUE)

  # Age data
  age_d <- age_fns[[yr]]()

  # Private school data (or NULL if not available)
  priv_d <- if (!is.null(priv_fns[[yr]])) priv_fns[[yr]]() else NULL

  # Join age
  geo <- geo %>%
    left_join(age_d, by = "GISJOIN") %>%
    mutate(
      school_age_share = safe_share(pop_5_17, total_pop),
      age_approx       = if ("approx_age" %in% names(.)) approx_age else FALSE
    )

  # Join private school
  if (!is.null(priv_d)) {
    geo <- geo %>%
      left_join(priv_d, by = "GISJOIN") %>%
      mutate(
        private_school_share = safe_share(private_K12, private_K12 + public_K12)
      )
  } else {
    geo$private_K12          <- NA_real_
    geo$public_K12           <- NA_real_
    geo$private_school_share <- NA_real_
  }

  # Keep only needed columns
  geo <- geo %>%
    select(GISJOIN, year, total_pop,
           school_age_share, age_approx,
           private_school_share, private_K12, public_K12,
           geometry)

  st_write(geo, out_path, delete_dsn = TRUE, quiet = TRUE)
  cat("  Wrote", out_path, "\n")
}

# ── School district boundaries ────────────────────────────────────────────────
# Download unified + elementary + secondary for 2000, 2010, 2020
# Pre-2000 years reuse the 2000 file.

cat("\nDownloading school district boundaries...\n")

get_school_districts <- function(yr) {
  cat("  Downloading year", yr, "...\n")
  # Download all 3 types (they tile the country without overlap)
  types <- c("unified", "elementary", "secondary")
  parts <- lapply(types, function(t) {
    tryCatch(
      school_districts(type = t, cb = TRUE, year = yr) %>%
        select(GEOID, NAME, geometry) %>%
        mutate(type = t),
      error = function(e) {
        cat("    Warning: could not get", t, "for", yr, ":", conditionMessage(e), "\n")
        NULL
      }
    )
  })
  parts <- Filter(Negate(is.null), parts)
  do.call(rbind, parts)
}

for (yr in c(2000L, 2010L, 2020L)) {
  sd <- get_school_districts(yr)
  if (is.null(sd) || nrow(sd) == 0) {
    cat("  No school districts for", yr, "\n")
    next
  }
  # Simplify for web
  sd_simp <- ms_simplify(sd, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  out <- file.path(OUT, paste0("school_districts_", yr, ".geojson"))
  st_write(sd_simp, out, delete_dsn = TRUE, quiet = TRUE)
  cat("  Wrote", out, "\n")
}

# Copy 2000 boundaries for pre-2000 years
sd_2000_path <- file.path(OUT, "school_districts_2000.geojson")
if (file.exists(sd_2000_path)) {
  for (yr in c("1940","1950","1960","1970","1980","1990")) {
    dest <- file.path(OUT, paste0("school_districts_", yr, ".geojson"))
    file.copy(sd_2000_path, dest, overwrite = TRUE)
  }
  cat("Copied 2000 boundaries to pre-2000 years.\n")
}

cat("\nDone.\n")
