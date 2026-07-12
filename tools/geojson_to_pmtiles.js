// GeoJSON -> MBTiles -> PMTiles, without tippecanoe.
// Pipeline: geojson-vt (tiling/simplification) -> vt-pbf (MVT encoding)
//           -> better-sqlite3 (mbtiles writer) -> pmtiles.exe convert (mbtiles->pmtiles)
//
// Usage: node --max-old-space-size=6144 tools/geojson_to_pmtiles.js <input.geojson> <outBasename> <layerName> [maxZoom]

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');
const geojsonvt = require('geojson-vt').default || require('geojson-vt');
const vtpbf = require('vt-pbf');
const Database = require('better-sqlite3');

const [, , inputPath, outBase, layerName, maxZoomArg] = process.argv;
if (!inputPath || !outBase || !layerName) {
  console.error('Usage: node geojson_to_pmtiles.js <input.geojson> <outBasename> <layerName> [maxZoom]');
  process.exit(1);
}
const MAXZOOM = parseInt(maxZoomArg || '11', 10);
const MINZOOM = 0;

const mbtilesPath = outBase + '.mbtiles';
const pmtilesPath = outBase + '.pmtiles';

// Windows Defender / AV real-time scanning can hold a transient lock on
// freshly-written large files, making unlinkSync throw EBUSY or "succeed"
// while the file is still briefly openable. Retry with backoff and confirm
// removal before proceeding.
function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function unlinkRetry(p, tries = 40, delayMs = 1000) {
  for (let i = 0; i < tries; i++) {
    if (!fs.existsSync(p)) return;
    try {
      fs.unlinkSync(p);
      if (!fs.existsSync(p)) return;
    } catch (e) {
      if (i === tries - 1) throw e;
    }
    sleepSync(delayMs);
  }
}

unlinkRetry(mbtilesPath);
unlinkRetry(pmtilesPath);

console.log(`[read] ${inputPath}`);
const raw = JSON.parse(fs.readFileSync(inputPath, 'utf8'));

// Strip null-valued properties: MVT has no null type, and the map style
// already treats a missing key the same as a null value (see makeColorExpr).
let minLon = Infinity, minLat = Infinity, maxLon = -Infinity, maxLat = -Infinity;
for (const f of raw.features) {
  const props = f.properties || {};
  for (const k of Object.keys(props)) {
    if (props[k] === null) delete props[k];
  }
}

console.log(`[tile] ${raw.features.length} features, maxZoom=${MAXZOOM}`);
const tileIndex = geojsonvt(raw, {
  maxZoom: MAXZOOM,
  indexMaxZoom: MAXZOOM,
  indexMaxPoints: 0,
  tolerance: 3,
  extent: 4096,
  buffer: 64
});

const db = new Database(mbtilesPath);
db.pragma('journal_mode = OFF');
db.exec(`
  CREATE TABLE metadata (name TEXT, value TEXT);
  CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
  CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
`);
const insertTile = db.prepare('INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)');
const insertMeta = db.prepare('INSERT INTO metadata (name, value) VALUES (?, ?)');

let tileCount = 0;
const insertMany = db.transaction((tiles) => {
  for (const t of tiles) insertTile.run(t.z, t.x, t.y, t.data);
});

function collect(z, x, y, out) {
  const tile = tileIndex.getTile(z, x, y);
  if (!tile) return;
  const buf = vtpbf.fromGeojsonVt({ [layerName]: tile }, { version: 2 });
  const gz = zlib.gzipSync(Buffer.from(buf));
  // mbtiles uses TMS row order (flipped Y) vs the XYZ scheme geojson-vt/web maps use.
  const tmsRow = (Math.pow(2, z) - 1) - y;
  out.push({ z, x, y: tmsRow, data: gz });
  tileCount++;
  if (out.length >= 500) { insertMany(out.splice(0)); }
  if (z < MAXZOOM) {
    collect(z + 1, 2 * x,     2 * y,     out);
    collect(z + 1, 2 * x + 1, 2 * y,     out);
    collect(z + 1, 2 * x,     2 * y + 1, out);
    collect(z + 1, 2 * x + 1, 2 * y + 1, out);
  }
}

const buffer = [];
collect(0, 0, 0, buffer);
if (buffer.length) insertMany(buffer);
console.log(`[tile] wrote ${tileCount} tiles`);

for (const f of raw.features) {
  const [lon, lat] = boundsPoint(f.geometry);
  if (lon == null) continue;
  if (lon < minLon) minLon = lon;
  if (lat < minLat) minLat = lat;
  if (lon > maxLon) maxLon = lon;
  if (lat > maxLat) maxLat = lat;
}
function boundsPoint(geom) {
  if (!geom) return [null, null];
  let c = geom.coordinates;
  while (Array.isArray(c) && Array.isArray(c[0])) c = c[0];
  return Array.isArray(c) ? c : [null, null];
}
if (!isFinite(minLon)) { minLon = -180; minLat = -85; maxLon = 180; maxLat = 85; }

const sampleProps = (raw.features[0] && raw.features[0].properties) || {};
const fields = {};
for (const k of Object.keys(sampleProps)) fields[k] = typeof sampleProps[k] === 'number' ? 'Number' : 'String';

insertMeta.run('name', layerName);
insertMeta.run('format', 'pbf');
insertMeta.run('minzoom', String(MINZOOM));
insertMeta.run('maxzoom', String(MAXZOOM));
insertMeta.run('bounds', `${minLon},${minLat},${maxLon},${maxLat}`);
insertMeta.run('center', `${(minLon+maxLon)/2},${(minLat+maxLat)/2},${MINZOOM}`);
insertMeta.run('type', 'overlay');
insertMeta.run('json', JSON.stringify({
  vector_layers: [{ id: layerName, fields, minzoom: MINZOOM, maxzoom: MAXZOOM }]
}));
db.close();
console.log(`[mbtiles] ${mbtilesPath} (${(fs.statSync(mbtilesPath).size/1e6).toFixed(1)} MB)`);

const pmtilesExe = path.join(__dirname, 'pmtiles.exe');
execFileSync(pmtilesExe, ['convert', mbtilesPath, pmtilesPath], { stdio: 'inherit' });
console.log(`[pmtiles] ${pmtilesPath} (${(fs.statSync(pmtilesPath).size/1e6).toFixed(1)} MB)`);
unlinkRetry(mbtilesPath);
