# 05b_download_school_districts.R
# Download school district boundaries for 2000, 2010, 2020.
# Downloads by state for 2000/2010 (national CB not available for older years).

library(tidyverse)
library(sf)
library(tigris)
library(rmapshaper)

options(tigris_use_cache = TRUE)
OUT <- "C:/Users/krumh/Claude/white_map/data"

# All states + DC
all_states <- c(
  "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
  "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
  "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
  "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
  "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC"
)

download_sd_by_state <- function(yr, types = c("unified","elementary","secondary")) {
  cat("Year", yr, "- downloading by state...\n")
  all_parts <- list()
  for (st in all_states) {
    for (tp in types) {
      res <- tryCatch(
        school_districts(state = st, type = tp, cb = FALSE, year = yr, quiet = TRUE) %>%
          select(GEOID, NAME, geometry) %>%
          mutate(type = tp),
        error = function(e) NULL
      )
      if (!is.null(res) && nrow(res) > 0) all_parts[[length(all_parts)+1]] <- res
    }
    cat("  ", st, "\n")
  }
  do.call(rbind, all_parts)
}

# 2020 — national download available
cat("Downloading 2020 school districts (national)...\n")
sd_2020_parts <- lapply(c("unified","elementary","secondary"), function(tp) {
  tryCatch(
    school_districts(type = tp, cb = TRUE, year = 2020) %>%
      select(GEOID, NAME, geometry) %>%
      mutate(type = tp),
    error = function(e) { cat("Failed:", tp, "\n"); NULL }
  )
})
sd_2020 <- do.call(rbind, Filter(Negate(is.null), sd_2020_parts))
if (!is.null(sd_2020) && nrow(sd_2020) > 0) {
  sd_2020_simp <- ms_simplify(sd_2020, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  st_write(sd_2020_simp, file.path(OUT, "school_districts_2020.geojson"), delete_dsn = TRUE, quiet = TRUE)
  cat("Wrote 2020.\n")
}

# 2010 — state by state
sd_2010 <- download_sd_by_state(2010)
if (!is.null(sd_2010) && nrow(sd_2010) > 0) {
  sd_2010_simp <- ms_simplify(sd_2010, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  st_write(sd_2010_simp, file.path(OUT, "school_districts_2010.geojson"), delete_dsn = TRUE, quiet = TRUE)
  cat("Wrote 2010.\n")
}

# 2000 — state by state
sd_2000 <- download_sd_by_state(2000)
if (!is.null(sd_2000) && nrow(sd_2000) > 0) {
  sd_2000_simp <- ms_simplify(sd_2000, keep = 0.05, weighting = 0.7, keep_shapes = TRUE)
  st_write(sd_2000_simp, file.path(OUT, "school_districts_2000.geojson"), delete_dsn = TRUE, quiet = TRUE)
  cat("Wrote 2000.\n")
}

# Copy 2000 for pre-2000 years
for (yr in c("1940","1950","1960","1970","1980","1990")) {
  file.copy(file.path(OUT, "school_districts_2000.geojson"),
            file.path(OUT, paste0("school_districts_", yr, ".geojson")),
            overwrite = TRUE)
}
cat("Done.\n")
