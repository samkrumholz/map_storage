@echo off
cd /d "%~dp0"
start "" "http://localhost:8765/index.html"
node server.js
