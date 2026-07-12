#!/bin/bash
# Batch-convert all white_map GeoJSON layers to PMTiles.
# school_districts is byte-identical across all 9 years -- convert once, reuse.
set -e
cd "$(dirname "$0")/.."
mkdir -p data_pmtiles data_pmtiles_fb data_pmtiles_ses

run() {
  local in="$1" out="$2" layer="$3" maxzoom="$4"
  if [ -f "${out}.pmtiles" ]; then
    echo "[skip] ${out}.pmtiles already exists"
    return
  fi
  echo "=== $in -> ${out}.pmtiles (layer=$layer, maxzoom=$maxzoom) ==="
  node --max-old-space-size=6144 tools/geojson_to_pmtiles.js "$in" "$out" "$layer" "$maxzoom"
}

for y in 1940 1950 1960 1970 1980 1990 2000 2010 2020; do
  run "data/tracts_${y}.geojson" "data_pmtiles/tracts_${y}" "tracts_${y}" 11
  run "data/school_${y}.geojson" "data_pmtiles/school_${y}" "school_${y}" 11
done

# school_districts: identical across all years -- convert once
run "data/school_districts_1940.geojson" "data_pmtiles/school_districts" "school_districts" 11

for y in 1950 1960 1970 1980 1990 2000 2010 2020; do
  run "data/vacancy_${y}.geojson" "data_pmtiles/vacancy_${y}" "vacancy_${y}" 11
done

for y in 1940 1950 1960 1970 1980 1990 2000 2012 2022; do
  run "data_fb/fb_${y}.geojson" "data_pmtiles_fb/fb_${y}" "fb_${y}" 11
  run "data_ses/ses_${y}.geojson" "data_pmtiles_ses/ses_${y}" "ses_${y}" 11
done

echo "=== DONE ==="
du -sh data_pmtiles data_pmtiles_fb data_pmtiles_ses
