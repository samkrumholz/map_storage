# White Share Map — Session Notes
**Started:** 2026-04-20  
**Updated:** 2026-05-08

## Project
Interactive MapLibre GL map of White (Non-Hispanic where available) share by census tract, 1930–2020.
No API keys required (CARTO base tiles, MapLibre from CDN).

## Files
- `01_process_nhgis.R` — reads NHGIS CSVs + shapefiles, simplifies, exports GeoJSONs to `data/`
- `index.html` — MapLibre GL JS map, lazy-loads each year on checkbox click
- `data/tracts_YYYY.geojson` — output files (created by R script)
- `nhgis_downloads/data/` — put NHGIS CSVs + codebook .txt files here
- `nhgis_downloads/shapefiles/YYYY/` — put extracted shapefiles here for each year

## NHGIS Download Instructions

### Step 1 — Create/log in
Go to **nhgis.org** → "Get Data" → log in (IPUMS account; free to register).

### Step 2 — Data tables extract (CSVs)

In the Data Finder, click **APPLY FILTERS** and set:
- Geographic Levels → **Census Tract**

Then for each decade add the appropriate race table to your cart:

| Year | Table to find | Search for in NHGIS |
|------|--------------|---------------------|
| 1930 | Race | Filter year=1930, look for "Race" table at tract level |
| 1940 | Race | Filter year=1940, "Race" table |
| 1950 | Race | Filter year=1950, "Race" table |
| 1960 | Race | Filter year=1960, "Race" table |
| 1970 | Race | Filter year=1970, "Race" table |
| 1980 | Race × Spanish origin | Filter year=1980, look for table with "Spanish Origin" × Race cross-tab |
| 1990 | Race × Hispanic origin | Filter year=1990, "Hispanic Origin" × Race cross-tab |
| 2000 | Hispanic/Latino by Race | Filter year=2000, table P4 "Hispanic or Latino, and Not Hispanic or Latino by Race" |
| 2010 | Hispanic/Latino by Race | Filter year=2010, table P5 "Hispanic or Latino Origin by Race" |
| 2020 | Hispanic/Latino by Race | Filter year=2020, table P2 "Hispanic or Latino, and Not Hispanic or Latino by Race" |

You can add all years to a single extract. The resulting ZIP will contain one CSV + one codebook TXT per year. Place all of them (extracted) in `nhgis_downloads/data/`.

### Step 3 — Shapefiles extract

In the same NHGIS session, go to **GIS FILES** tab.

Filter: Geographic Level → **Census Tract**

Add tract boundary shapefiles for: **1930, 1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020**

(You can put all in one extract.) After downloading and unzipping, put each year's `.shp`, `.dbf`, `.prj`, etc. files in:
- `nhgis_downloads/shapefiles/1930/`
- `nhgis_downloads/shapefiles/1940/`
- ... and so on through 2020

### Step 4 — Run the R script

```r
source("C:/Users/krumh/Claude/white_map/01_process_nhgis.R")
```

Each year takes ~1–2 minutes (simplification). Output GeoJSONs go to `data/`.

### Step 5 — Open the map

Open `index.html` in a browser (must be served from a local HTTP server, not opened as a file, because of GeoJSON fetch). Quickest way in R:

```r
servr::httd("C:/Users/krumh/Claude/white_map")
```

Or in terminal: `npx serve C:/Users/krumh/Claude/white_map`

## Coverage caveats
- **1930–1950**: Only cities that had census tracts defined appear. Rural areas are blank.
- **1960**: Partial national coverage; major metro areas mostly covered.
- **1970+**: Near-nationwide coverage.
- **1930–1970**: "White" includes Hispanic whites (Hispanic origin question not asked until 1980).
- **1980+**: "NH-White" = Non-Hispanic White alone.
- Tract boundaries differ across years; overlapping multiple years on the map will show misaligned polygons.

## Known issues / caveats
- simplification: keep=0.04 (rmapshaper). May want to increase keep for zoom >10 detail.
- File sizes: 1940=5.7MB, 1950=10MB, 1960=23MB, 1970=38MB, 1980=59MB, 1990=107MB, 2000=111MB, 2010=57MB, 2020=65MB
- 1990/2000 are larger (~107-111MB) because conflated shapefiles (636-649MB raw) retain more vertices at 4% keep. Acceptable for local serving.
- Color scale: light = low white share, dark blue = high white share (Blues ColorBrewer)
- Auto-detect fallback: if `01_process_nhgis.R` can't find variable names, it prints all available variables and stops. Update the `white_pat` regex in `year_config` to match.

## Status
- [x] R script updated to cover 1940–2020
- [x] HTML map updated with checkboxes for 1940–2020
- [x] NHGIS data downloaded (all years in nhgis_downloads/)
- [x] GeoJSONs exist: 1940, 1970, 1980, 2010, 2020
- [x] GeoJSONs generated 2026-05-09: 1950, 1960 (run_missing_years.R)
- [x] GeoJSONs generated 2026-05-10: 1990, 2000 (join_1990_2000.R — see note below)
- [x] 1940 denominator bug fixed: was using BVP001 (occupied dwellings) as denominator;
      fixed to total_as_sum=TRUE → BUQ001+BUQ002 = total persons
- [x] HTML fill-opacity reduced 0.55→0.40 for lighter shading (geography more visible)
- [x] Radio buttons (single-year mode) — selecting a year auto-hides the previous (2026-05-10)
- [x] Race/ethnicity toggle added: White, Black, Hispanic, Asian (2026-05-10)
  - enrich_race.R adds black_share/hispanic_share/asian_share to all 9 GeoJSONs
  - 1940: white only | 1950-1970: white+black | 1980+: all four (1980 Hispanic = DFB016 "Spanish race" only, undercounts)
- [ ] Map tested in browser

## 1990/2000 generation note (2026-05-10)
The 1990/2000 "conflated" shapefiles are 636/649 MB raw — too large for ms_simplify (times out
at 10 min) or st_simplify (OOM on topology graph). Working approach used:
1. Mapshaper CLI directly on raw .shp: `mapshaper -i input.shp -simplify 4% weighting=0.7 keep-shapes -o output.shp format=shapefile`
   → output shapefiles in nhgis_downloads/shapefiles/1990_simp/ and 2000_simp/ (36-37 MB each)
2. R join: join_1990_2000.R reads simplified .shp, joins CSV data, exports GeoJSON
If regeneration needed, run steps 1 and 2. Do NOT use ms_simplify or st_simplify for these years.
