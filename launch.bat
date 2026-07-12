@echo off
cd /d "%~dp0\.."

echo Starting Census Maps server...
echo A console window titled "Census Maps Server" will open.
echo Keep it open while using the maps -- close it to stop the server.
echo.

start "Census Maps Server" "C:\Program Files\R\R-4.4.0\bin\Rscript.exe" -e "if (!requireNamespace('servr', quietly=TRUE)) install.packages('servr', repos='https://cloud.r-project.org'); servr::httd('.', port=8743, browser=FALSE)"

timeout /t 4 /nobreak >nul
start "" "http://localhost:8743/white_map/portal.html"
