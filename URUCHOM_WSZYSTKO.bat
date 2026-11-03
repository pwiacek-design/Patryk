@echo off
rem Uruchamia URUCHOM_WSZYSTKO.ps1 z uprawnieniami administratora. Okno nie zamyka sie samo.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0URUCHOM_WSZYSTKO.ps1"
pause
