@echo off
setlocal
cd /d "%~dp0"
if not exist dist mkdir dist
..\tools\fasm\FASM.EXE server.asm dist\vrc-chatbox-osc-asm.exe
