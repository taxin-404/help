@echo off
REM ============================================================
REM setup-remote.bat
REM Double-click this file to set up remote access to this PC.
REM It will ask for Administrator permission (click Yes).
REM ============================================================

REM >>>> EDIT THIS LINE with your own ZeroTier Network ID <<<<
REM Get one free at https://my.zerotier.com  (Create A Network)
set NETWORK_ID=633e31d8a2e3401d

REM ---- self-elevate to Administrator if not already ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

if "%NETWORK_ID%"=="PUT_YOUR_16_CHAR_NETWORK_ID_HERE" (
    echo.
    echo [X] You need to edit this .bat file first and set NETWORK_ID
    echo     to your real ZeroTier network ID from https://my.zerotier.com
    echo.
    pause
    exit /b 1
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\zerossh-windows.ps1" -NetworkID "%NETWORK_ID%"

echo.
pause
