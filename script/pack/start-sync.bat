@echo off
REM Run sync.sh via Git Bash or WSL.
REM Example: start-sync.bat -y --config=demo.yml --group=1
setlocal
cd /d "%~dp0"

where bash >nul 2>&1
if %ERRORLEVEL%==0 (
  bash sync.sh %*
  exit /b %ERRORLEVEL%
)

where wsl >nul 2>&1
if %ERRORLEVEL%==0 (
  wsl -e bash ./sync.sh %*
  exit /b %ERRORLEVEL%
)

echo [ERROR] Need Git Bash or WSL to run sync.sh
echo Install Git for Windows: https://git-scm.com/
pause
exit /b 1
