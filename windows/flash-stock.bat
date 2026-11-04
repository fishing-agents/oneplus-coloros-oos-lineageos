@echo off
rem Double-click or: flash-stock.bat <firmware.zip> [-Recovery recovery.img] [-SkipPhysical]
if "%~1"=="" (
  echo Drag the firmware zip onto this file, or run: flash-stock.bat ^<firmware.zip^>
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-stock.ps1" %*
