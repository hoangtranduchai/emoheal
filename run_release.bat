@echo off
chcp 65001 >nul
cd /d "%~dp0"
title EmoHeal - Release Wireless Phone Runner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "run_wireless.ps1" -ReleaseMode
pause
