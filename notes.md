# White Share Map — Session Notes
**Started:** 2026-04-20  
**Updated:** 2026-07-30

## Session 2026-07-25

Project has grown well beyond the original race map since the last note update — there are
now 5 maps total, all launched from `portal.html`: Race (`index.html`), Vacancy
(`vacancy.html`), SES (`ses.html`), Foreign Born (`foreign.html`), Schools (`school.html`).
Each has its own data pipeline and its own (previously independent) color-scale code — there
is no shared `makeColorExpr` across files, contrary to what you might assume from `index.html`
alone.

User asked for three things across "the maps in white_map": (1) sharper low/high color
contrast, (2) a percentile-within-metro toggle + metro boundaries, (3) a Zillow ZHVI zip-level
toggle for SES home value with a year slider + compare-year feature. Scoped with the user via
AskUserQuestion before building (2)/(3) since neither had any supporting data in the project:
- **(2) scope**: Race and SES maps only (not Vacancy/Foreign Born/Schools).
- **(2) metro reference frame**: fixed 2020 CBSA delineations applied to every census year via
  centroid point-in-polygon (not period-specific metro definitions). Tradeoff: tracts that were
  rural at the time but sit inside a metro's *current* footprint get included.
- **(3) compare-year behavior**: a toggle between % change and absolute $ change between two
  selected years (not side-by-side panes, not hover-only).

### (1) Sharper contrast — done, all 5 maps
Every map's color ramp had a near-white/near-transparent low-end stop (e.g. `#f7fbff`,
`#ffffb2`, `#f2f0f7`) that barely showed against the CARTO light basemap. Fix applied
consistently: dropped that washed-out stop (shifted the ramp up one class) and added a new,
darker stop at the top end for a more dramatic high extreme. Same treatment in
`index.html`, `vacancy.html`, `foreign.html`, `school.html` (both the `makeColorExpr`-style
JS function AND the corresponding CSS/legend gradient — `school.html` had a second,
easy-to-miss copy of the gradient inside `updateLegend()` that also needed updating), and
`ses.html` (both `edu` and `hv` variable configs).

### (2) Percentile-within-metro toggle + metro boundaries — done, Race + SES maps
- `nhgis_downloads/cbsa/tl_2020_us_cbsa.shp` — 2020 Census TIGER CBSA shapefile (939 areas;
  `LSAD` field: `M1`=392 metro areas, `M2`=547 micro areas — filtered to M1 only for the
  boundary display layer).
- `07_metro_percentile.R` — for every year's `data/tracts_YYYY.geojson` (race) and
  `data_ses/ses_YYYY.geojson` (SES): centroid-joins each tract to a 2020 CBSA, adds
  `cbsa_id`/`cbsa_name`, and adds `<var>_pctile_metro` (0-1, `(rank-1)/(n-1)` within cbsa_id,
  NA outside any metro) for `white_share` (race) and `edu_share`+`hv_2022` (SES). Also writes
  `data/cbsa_boundaries.geojson` (simplified M1-only polygons for the map line layer).
- `07b_race_percentile_topup.R` — adds the same percentile field for `black_share`,
  `hispanic_share`, `asian_share` too (reuses the `cbsa_id` already written, no re-join).
- Regenerated all 18 race+SES `.pmtiles` plus one new `data_pmtiles/cbsa_boundaries.pmtiles`
  (shared by both `index.html` and `ses.html` via a relative path, single file, not per-year —
  metro boundaries don't change across census years like tract geometry does).
- `index.html` / `ses.html`: new "Percentile within metro" toggle button (same visual style as
  the existing border-pairs button). When on: fill-color switches from the raw prop to
  `<prop>_pctile_metro` (both are 0-1 so the SAME color ramp works for either — for `ses.html`'s
  `hv` variable specifically, added a separate `pctileColorExpr()` since `hv`'s normal color
  expression assumes raw log-dollars, which would be nonsense applied to a 0-1 percentile), the
  metro boundary line layer becomes visible, and legend/tooltip update to show percentile +
  metro name. Border-pairs filter is orthogonal and still works independently in either mode.
- Coverage: ~85-90% of tracts fall inside a 2020 CBSA in most years; older/sparser years (1940
  cities-only, etc.) naturally have lower/no coverage outside their few defined tracts.

### (3) Zillow ZHVI zip-level toggle for SES — done
- Downloaded (no API key needed, both public):
  - `zillow_downloads/zhvi_zip.csv` — Zillow Research ZHVI, all zips, smoothed/seasonally
    adjusted, monthly 2000-01 through 2026-06 (26,274 zips).
  - `nhgis_downloads/zcta/tl_2020_us_zcta520.shp` — 2020 Census TIGER ZCTA5 boundaries
    (~33k zip areas, 819MB raw shapefile).
- **Hit the same bottleneck already documented below in the 1990/2000 note**: routing the
  full-resolution national ZCTA shapefile through `rmapshaper::ms_simplify()` in R (even with
  `sys=TRUE`) took 45+ min and was killed twice — R's own GeoJSON serialization of the raw
  geometry before handing off to mapshaper was the bottleneck, not the simplification itself.
  Fix (same as before): ran mapshaper CLI directly on the `.shp`:
  `mapshaper -i tl_2020_us_zcta520.shp -simplify 3% weighting=0.7 keep-shapes -o
  data_zillow/zcta_simplified.shp format=shapefile` — took 23 seconds. Lesson: for any future
  nationwide TIGER shapefile, simplify via the CLI directly first, don't hand raw geometry to
  `ms_simplify()` from R.
- `08_zhvi_zcta.R` — reads the pre-simplified ZCTA shapefile, builds a Dec-snapshot-per-year
  wide table from the ZHVI CSV (2000-2025 + latest partial month `zhvi_2026_latest` = 2026-06),
  joins by 5-digit zip, writes `data_zillow/zhvi_zcta.geojson` (33,791 ZCTAs, 25,752 matched
  to ZHVI, 77.4MB, 27 `zhvi_<year>` fields) — ONE file, not one per year, since ZCTA geometry
  is static across the analysis period unlike decennial tract boundaries.
- Converted to `data_pmtiles_zillow/zhvi_zcta.pmtiles` (101.8MB, maxzoom 10, layer
  `zhvi_zcta`). Verified all 27 year fields survive per-feature in the actual tile encoding
  (decoded a real tile directly with vt-pbf/@mapbox-vector-tile) — the pmtiles CLI's
  `--metadata` field list only reflects `features[0]`'s properties
  (`tools/geojson_to_pmtiles.js:127`), so it under-reports fields for the first feature's
  data gaps; not a real bug, just a cosmetic quirk of that summary output.
- `ses.html` UI, all gated on the `hv` variable being selected (button/controls hidden
  otherwise):
  - **Zillow toggle** (`btn-zillow`): swaps the visible layer from the current tract-year fill
    to a national zip-level fill (`fill-zillow`/`line-zillow`), reusing `VAR_CFG.hv.colorExpr`
    (already generic over which property it reads) for the single-year view.
  - **Year slider**: index 0-26 over `ZHVI_YEARS` (2000...2025, 2026_latest), defaults to 2022.
  - **Compare-year checkbox**: reveals a second year slider (default 2012) plus a %/$ radio
    toggle, per your answer to the scoping question. Color is a 7-stop diverging ramp (red =
    decline, blue = increase) — stops are a first-pass guess at typical zip-level swings
    (±100% / ±$150k-300k), not derived from the actual national distribution of changes, so
    they may need retuning once you've looked at it.
  - Border-pairs and percentile-within-metro buttons are disabled while the Zillow layer is
    active (both depend on tract-only fields the zip layer doesn't have).
- Verified: `node --check` on the extracted script (syntax OK), server smoke test (200s for
  `ses.html`, `zhvi_zcta.pmtiles`), and a direct tile-decode test confirming per-feature
  properties are intact. **Not tested in an actual browser** — no browser tool available this
  session; worth opening it once and clicking through the new controls before relying on it.

### (3b) Follow-up after user found the Zillow toggle — done
- User asked why the button wasn't visible: it's gated on `hv` being the selected Variable
  radio (by design, since Zillow only applies to home value), which wasn't obvious from the UI.
  No code change — just explained the click path (Variable → "Median home value (2022$)").
- **New color scale for single-year Zillow view**: was reusing `VAR_CFG.hv.colorExpr` (all-green
  ramp, shared with the tract-level Census home-value fill). User wanted green→yellow→red
  instead. Added a dedicated `zillowSingleYearColorExpr()` / `ZILLOW_SEQ_COLORS` (7-stop
  ColorBrewer-style RdYlGn on the same ln($) breakpoints as before, ~$22k to ~$3.3M) used only
  for the Zillow layer's single-year mode — left `VAR_CFG.hv.colorExpr` (tract-level Census
  values) untouched since that wasn't part of the ask. Compare-year mode keeps its own separate
  diverging red/blue scale (`DIVERGING_COLORS`), unaffected.
- Legend bar/ticks for Zillow single-year mode now pull from `ZILLOW_SEQ_GRAD`/`ZILLOW_SEQ_TICKS`
  instead of `VAR_CFG.hv.barGrad`/`.ticks`.
- **Paler fill**: `fill-zillow` opacity 0.65 → 0.42 so streets/labels on the CARTO basemap show
  through better.
- **Inflation-adjustment question**: confirmed ZHVI is nominal (current) dollars, not inflation-
  adjusted. Zillow's own site (zhvi-methodology, zhvi-user-guide pages) returned 403 to WebFetch,
  but corroborating evidence: multiple independent third-party analyses (Advisor
  Perspectives/dshort "real home values" series) explicitly deflate Zillow's ZHVI by CPI
  themselves to get an inflation-adjusted series — implying the raw ZHVI Zillow publishes is
  nominal. If you need real values, would need to deflate `zhvi_<year>` by CPI (e.g. FRED
  CPIAUCSL, December value each year) — not implemented.
- Not yet re-tested in browser after this edit — same caveat as above.

### (3c) Inflation adjustment + unified color scale + push to GitHub — done
- **Inflation adjustment**: folded CPI deflation directly into `08_zhvi_zcta.R` (not a separate
  post-hoc script, to avoid any risk of double-deflating on a future re-run) — every `zhvi_<year>`
  is now multiplied by `CPI_dec_2022 / CPI_dec_<year>` using CPI-U NSA (FRED series CPIAUCNS,
  December value each year; June 2026 for `zhvi_2026_latest`). CPI values are hardcoded in the
  script (pulled once from `fredgraph.csv?id=CPIAUCNS`) — re-download and update `cpi_dec`/
  `cpi_latest` if regenerating in a future year and want the base year to roll forward past 2022.
  Base year 2022 chosen to match `hv_2022`'s existing "(2022$)" convention. Re-ran the full
  pipeline (23 sec, reusing the cached `zcta_simplified.shp`) and regenerated
  `data_pmtiles_zillow/zhvi_zcta.pmtiles` (96.6 MB now, up slightly from 96.5 — value magnitudes
  changed, feature count didn't).
- **Unified color scale**: moved the green→yellow→red ramp (`DOLLAR_SEQ_STOPS/COLORS/TICKS/GRAD`,
  `dollarColorExpr()`) to before `VAR_CFG` in `ses.html` and pointed `VAR_CFG.hv` at it too, so
  the tract-level Census home-value view and the Zillow zip-level view now share one scale
  (previously only the Zillow layer got it). Percentile-mode's Blues ramp (`pctileColorExpr`,
  shared with the `edu` variable and with `index.html`) was deliberately left alone — it's a
  generic 0-1 ramp, not home-value-specific.
- **Pushed to GitHub**: `origin/main` (`samkrumholz/map_storage`), commit `dda90f2`. Scoped the
  commit to SES-only files — `ses.html`, `notes.md`, `07_metro_percentile.R`, `08_zhvi_zcta.R`,
  all of `data_pmtiles_ses/`, `data_pmtiles/cbsa_boundaries.pmtiles`,
  `data_pmtiles_zillow/zhvi_zcta.pmtiles` — left the Race/Vacancy/Foreign Born/Schools changes
  (already modified in the working tree from the same session's ask #1/#2 work) uncommitted,
  since only "the SES maps" were asked for. Excluded from git entirely: `data_zillow/`
  (raw geojson + intermediate shapefile — geojson already gitignored via `*.geojson`, shapefile
  parts are just a fast-rebuild cache) and `zillow_downloads/zhvi_zip.csv` (122MB raw Zillow
  download — over GitHub's 100MB hard limit, not needed for serving anyway, regeneratable from
  Zillow's public research page).
- **File size watch**: no `.gitattributes`/Git LFS configured in this repo (git-lfs 3.7.1 *is*
  installed locally, just unused). `zhvi_zcta.pmtiles` is 96.6 MB — under GitHub's 100MB hard
  block but over its 50MB warning threshold (push succeeded with a warning). If this grows past
  ~100MB in a future update (e.g. more years, finer maxzoom), it'll need Git LFS.


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

## Session 2026-07-29: Firefox black-screen bug (root cause + fix)

**Symptom:** vacancy.html, ses.html, etc. loaded as a black screen in Firefox (legends/controls fine, no map). Not present in Chrome.

**Diagnostic path:**
- Headless Chromium tests (Puppeteer) showed clean renders, no errors — false all-clear, since it never tested the actual browser.
- User ruled out cache/extensions (incognito, same result), then clarified they use Firefox, not Chrome, and confirmed Chrome works fine on the same machine — pointing at a Firefox-specific bug, not hardware/GPU.
- Switched to Playwright with real headless Firefox. Screenshot of the live site showed a patchwork render: basemap fine, vector tract layer only rendered in scattered isolated patches (e.g., parts of California/Dakotas) — consistent with corrupted tile reads, not a total failure.

**Root cause:** Firefox's HTTP cache misapplies range-request responses across different byte ranges of the same URL (protomaps/PMTiles GitHub #272, discussion #582). Since PMTiles fetches many different byte ranges from one static `.pmtiles` file, Firefox serves back a cached fragment from an earlier range request instead of the newly requested range, corrupting tile data. No console errors are thrown, which is why it presents as a silent black map. Confirmed the old pinned pmtiles.js (3.0.7) has no proactive cache-bypass, only a reactive ETag-mismatch retry that doesn't catch every case.

**Fix:** Bumped `pmtiles@3.0.7` → `pmtiles@4.4.1` (unpkg CDN tag) and added a `registerPmtiles(path)` helper that constructs a `pmtiles.FetchSource`, sets `chromeWindowsNoCache = true` on it (a flag added in 4.4.1 for an analogous Chrome/Windows bug — repurposed here since the underlying fix, forcing `cache: "no-store"` on every range fetch, is browser-agnostic), wraps it in `pmtiles.PMTiles`, and registers it via `pmtilesProtocol.add()` before each `map.addSource()` call. Applied to every pmtiles source in `vacancy.html`, `foreign.html`, `ses.html`, and `index.html`.

**Note on index.html:** that file also contains a large in-progress, unshipped "percentile within metro" toggle feature (new `loadMetroLayer()`, `colorProp()`, `setPercentileMode()`, UI button, tooltip changes) that was NOT touched — its `registerPmtiles('data_pmtiles/cbsa_boundaries.pmtiles')` call was deliberately left out since that function has no live callers yet.

**Testing:** Local repro via a custom Range-capable Node static server (`tools/static_server.js` — `python -m http.server` isn't available, only a Windows Store stub) + Playwright headless Firefox (`tools/diagnose_firefox.js`). Before/after screenshots confirmed all four pages went from broken/partial to full correct renders.

**Push scoping:** User chose "fix only." Hand-built unified-diff patches isolated just the fix hunks (version bump + `registerPmtiles` helper + call-site insertions) and staged them with `git apply --cached`, leaving unrelated uncommitted work untouched in the working tree:
- `index.html`: percentile-toggle feature (new functions/UI, still unshipped)
- `foreign.html` / `vacancy.html`: pending color-gradient tweaks (not yet reviewed/finalized)
- Four `tracts_*.pmtiles` files (1990/2000/2010/2020) that now exceed GitHub's 100MB push limit — need shrinking (more aggressive mapshaper simplification) or Git LFS before they can be committed; no decision made yet on which.

Commit `7b63229` pushed to `origin/main` (samkrumholz/map_storage). Temporary patch files and diagnostic screenshots deleted after use; `tools/diagnose_firefox.js` and `tools/static_server.js` kept as reusable diagnostics.

**Still open:** oversized `tracts_*.pmtiles` files and the percentile-toggle feature remain uncommitted, no plan yet for either.

## Session 2026-07-30: Shipped percentile-toggle feature (Race map) + fixed oversized pmtiles

User approved shipping the percentile-within-metro toggle for `index.html` (Race map), Chrome only for this round. The feature itself was already fully coded from the prior session (color ramp, `colorProp()`, `loadMetroLayer()`, `setPercentileMode()`, UI button, tooltip) — the blocker was that `data_pmtiles/tracts_2000/2010/2020.pmtiles`, once carrying the new `*_pctile_metro` fields, exceeded GitHub's 100 MiB (104,857,600-byte) hard push limit.

**Root cause of bloat:** MVT tiles dedupe properties via a per-tile value dictionary. `GISJOIN` (a unique-per-tract NHGIS join key, confirmed unused anywhere in the map's HTML/JS) and `cbsa_name` (a repeated but unnecessary string) don't dedupe well and dominated file size — far more than the unrounded percentile floats did.

**Fix:** stripped `GISJOIN` and `cbsa_name` from all 9 years' `data/tracts_YYYY.geojson`, rounded the 4 `*_pctile_metro` fields to the nearest 0.02, and regenerated all `data_pmtiles/tracts_YYYY.pmtiles` via `tools/geojson_to_pmtiles.js`. Final sizes, largest first: 2020=92.89 MiB, 2000=88.10 MiB, 2010=84.57 MiB, 1990=82.77 MiB, 1980=45.88 MiB, 1970=23.66 MiB, 1960=14.37 MiB, 1950=5.90 MiB, 1940=2.89 MiB — all under the limit.

Since `cbsa_name` was removed from the tiles, the tooltip needed a replacement: built `tools/cbsa_names.json` (939-entry `cbsa_id → cbsa_name` lookup, extracted from the geojsons before stripping) and embedded it as a `CBSA_NAMES` JS constant directly in `index.html`. Tooltip now resolves `CBSA_NAMES[p.cbsa_id]` instead of reading `p.cbsa_name` off the tile.

**Not yet done:** `07_metro_percentile.R` / `07b_race_percentile_topup.R` do NOT yet bake in this rounding/field-stripping — if either is rerun from scratch, the oversized-pmtiles problem will reappear and need to be reapplied by hand. Worth fixing in the R scripts directly at some point.

**Verification:** local Range-capable static server (`tools/static_server.js`) + a real Chrome binary (from the Puppeteer cache, driven via Playwright's `chromium.launch({ executablePath })` since `playwright install` hadn't downloaded its own Chromium) — `tools/test_percentile_chrome.js`. Confirmed: toggle button flips `percentileMode`, `metro-line` layer becomes visible, `fill-2020` paint switches to the percentile color expression, and hovering a Chicago tract shows the correct tooltip ("Chicago-Naperville-Elgin, IL-IN-WI (50th pctile)"). Only network 404 seen was `favicon.ico` — cosmetic, unrelated.

Committed and pushed: `index.html`, all 9 `data_pmtiles/tracts_*.pmtiles`, `07b_race_percentile_topup.R`, `tools/cbsa_names.json`, plus the dev/test tooling (`tools/static_server.js`, `tools/diagnose_black_screen.js`, `tools/diagnose_firefox.js`, `tools/list_responses.js`, `tools/test_percentile_chrome.js`). Left uncommitted, unrelated to this task: `foreign.html`/`vacancy.html` pending color-gradient tweaks, and the untracked `data_zillow/`/`zillow_downloads/` directories (SES Zillow layer data, ~100MB+ each — not reviewed this session).

**Still open:** SES map (`ses.html`) percentile toggle — mentioned as "done" in the 2026-07-25 entry but its own `data_ses/ses_YYYY.geojson`/pmtiles pipeline has NOT been checked for the same GISJOIN/cbsa_name bloat issue; should verify before assuming it's shippable as-is.
