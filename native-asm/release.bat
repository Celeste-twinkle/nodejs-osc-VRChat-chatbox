@echo off
setlocal
cd /d "%~dp0"
call build.bat || exit /b 1
if exist release rmdir /s /q release
mkdir release
copy /y dist\vrc-chatbox-osc-asm.exe release\vrc-chatbox-osc.exe >nul
echo release\vrc-chatbox-osc.exe
