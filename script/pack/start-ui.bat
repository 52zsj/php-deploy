@echo off
setlocal
cd /d "%~dp0"

set SYNC_UI_HOST=127.0.0.1
set SYNC_UI_PORT=8765

where python >nul 2>&1
if %ERRORLEVEL%==0 (
  python script\sync-ui\app.py
  exit /b %ERRORLEVEL%
)

where python3 >nul 2>&1
if %ERRORLEVEL%==0 (
  python3 script\sync-ui\app.py
  exit /b %ERRORLEVEL%
)

echo [ERROR] Need Python 3 on PATH.
echo Install from https://www.python.org/ and retry.
pause
exit /b 1
