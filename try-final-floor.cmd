@echo off
rem Temporary harness: jump into floor 20's final boss with a fully built hero.
rem Delete tests\try_final_floor.gd and this file when you are done testing.
setlocal
cd /d "%~dp0"
if exist "tools\Godot_v4.4.1-stable_win64.exe" (
  "tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0." --script res://tests/try_final_floor.gd
) else (
  echo Godot runtime not found in tools\.
  pause
)
