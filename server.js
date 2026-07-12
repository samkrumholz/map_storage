// Simple static file server for the white_map project
// Run with: node server.js
const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT = 8765;
const ROOT = __dirname;

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.css':  'text/css',
  '.json': 'application/json',
  '.geojson': 'application/json',
  '.png':  'image/png',
};

http.createServer((req, res) => {
  let filePath = path.join(ROOT, req.url === '/' ? '/index.html' : req.url);
  const ext = path.extname(filePath).toLowerCase();
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404); res.end('Not found: ' + req.url); return;
    }
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(PORT, '127.0.0.1', () => {
  console.log('Serving at http://localhost:' + PORT);
  console.log('White share map: http://localhost:' + PORT + '/index.html');
  console.log('Vacancy map:     http://localhost:' + PORT + '/vacancy.html');
  console.log('Press Ctrl+C to stop.');
});
