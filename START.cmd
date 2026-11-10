@echo off
cd /d "%~dp0"
if not exist node_modules (
  call npm ci
  if errorlevel 1 goto failed
)
echo.
echo Smart Pantry startet. Die angezeigte lokale Adresse im Browser oeffnen.
call npm run dev
exit /b
:failed
echo Installation fehlgeschlagen. Ist Node.js 22.12 oder neuer installiert?
pause
