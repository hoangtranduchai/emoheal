@echo off
chcp 65001 >nul
cd /d "%~dp0"
title EmoHeal - 1-Click Wireless Phone Runner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "run_wireless.ps1"
pause
