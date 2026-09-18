@echo off
setlocal enabledelayedexpansion
title machine-bridge

rem ============ EDIT THESE TWO LINES ONCE, THEN NEVER AGAIN ============
set "ROOT=C:\Users\Admin\Desktop\first-roblox-game"
set "NGROK_DOMAIN="
rem   ^ leave empty to use a random cloudflare URL (you must re-paste it
rem     every restart). Put your free ngrok static domain here instead --
rem     e.g. set "NGROK_DOMAIN=osama-dev.ngrok-free.app" -- and the URL
rem     never changes again, so this becomes genuinely one click.
rem =====================================================================

set "PORT=8787"
set "HERE=%~dp0"
set "TOKENFILE=%USERPROFILE%\.machine-bridge-token"

rem --- find Python. This is what failed for you last time: "python" is not on
rem --- PATH on a default Windows install, but the "py" launcher usually is.
set "PY="
for %%C in (py python python3) do (
  if not defined PY (
    %%C -c "import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1 && set "PY=%%C"
  )
)
if not defined PY (
  echo.
  echo   Python 3.8+ not found.
  echo   Install from https://www.python.org/downloads/
  echo   IMPORTANT: tick "Add python.exe to PATH" in the installer.
  echo.
  pause
  exit /b 1
)

if not exist "%ROOT%" (
  echo.
  echo   ROOT does not exist: %ROOT%
  echo   Edit the ROOT line at the top of this file.
  echo.
  pause
  exit /b 1
)

rem --- token: generated once, reused forever, so the registration stays valid
if not exist "%TOKENFILE%" (
  %PY% -c "import secrets,io;io.open(r'%TOKENFILE%','w').write(secrets.token_hex(24))"
  echo   Generated a new token: %TOKENFILE%
)
set /p TOKEN=<"%TOKENFILE%"

echo.
echo   root   %ROOT%
echo   port   %PORT%
echo   token  %TOKEN%
echo.

start "machine-bridge server" /min %PY% "%HERE%machine_mcp.py" --root "%ROOT%" --token %TOKEN% --port %PORT%

if defined NGROK_DOMAIN (
  echo   Registration line ^(paste to Claude ONCE, it never changes^):
  echo.
  echo   claude mcp add --transport http my-machine https://%NGROK_DOMAIN%/ --header "Authorization: Bearer %TOKEN%"
  echo.
  echo   Starting tunnel on your fixed domain. Ctrl-C to stop everything.
  echo.
  ngrok http --url=https://%NGROK_DOMAIN% %PORT%
) else (
  echo   No fixed domain set -- using a random cloudflare URL.
  echo   Copy the https://...trycloudflare.com line below and send it to Claude,
  echo   along with the token above. You will have to redo this every restart.
  echo.
  cloudflared tunnel --url http://localhost:%PORT%
)

echo.
echo   Tunnel closed. Stopping the server.
taskkill /FI "WINDOWTITLE eq machine-bridge server*" /F >nul 2>&1
pause
