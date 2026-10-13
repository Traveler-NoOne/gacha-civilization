@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo  Screenshot self-check (non-headless)
echo  Shots go to: tests\_shots\  (cleared before each run)
echo  Manifest  : tests\_shots\00_MANIFEST.md
echo ============================================================
echo.
"C:\Program Files\Godot_v4.4.1-stable_mono_win64\Godot_v4.7.2-stable_win64_console.exe" --path "%~dp0" --resolution 1280x720 res://tests/screenshot.tscn
echo.
echo Done. Look at tests\_shots\00_MANIFEST.md
pause
