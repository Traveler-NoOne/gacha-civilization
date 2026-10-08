@echo off
rem ---------------------------------------------------------------
rem  Gacha Civilization - Self Check launcher
rem  Keep this file ASCII-only: cmd.exe mis-parses non-ASCII in .bat.
rem  All Chinese output comes from tests\run_all_selfcheck.ps1
rem ---------------------------------------------------------------
chcp 65001 >nul
title Gacha Civilization - Self Check
pushd "%~dp0"

where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\run_all_selfcheck.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\run_all_selfcheck.ps1"
)

echo.
pause
popd
