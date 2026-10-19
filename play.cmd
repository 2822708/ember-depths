@echo off
setlocal
cd /d "%~dp0"
if exist "tools\Godot_v4.4.1-stable_win64.exe" (
  start "Ember Depths" "tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0."
) else (
  echo Godot runtime not found. Open project.godot with Godot 4.4 or newer.
  pause
)
