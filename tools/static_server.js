const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const port = process.argv[2] || 8934;

const mime = {
  '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
  '.pmtiles': 'application/octet-stream', '.css': 'text/css', '.png': 'image/png'
};

http.createServer((req, res) => {
  let filePath = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    const range = req.headers.range;
    if (range) {
      const [startStr, endStr] = range.replace(/bytes=/, '').split('-');
      const start = parseInt(startStr, 10);
      const end = endStr ? parseInt(endStr, 10) : stats.size - 1;
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${stats.size}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': end - start + 1,
        'Content-Type': mime[ext] || 'application/octet-stream'
      });
      fs.createReadStream(filePath, { start, end }).pipe(res);
    } else {
      res.writeHead(200, {
        'Content-Length': stats.size,
        'Accept-Ranges': 'bytes',
        'Content-Type': mime[ext] || 'application/octet-stream'
      });
      fs.createReadStream(filePath).pipe(res);
    }
  });
}).listen(port, () => console.log(`Serving ${root} on http://localhost:${port}`));
