@echo off
rem REMods Testbot starten. Optional: testbot.bat <ip> <port> <spiel>
cd /d "%~dp0"
remods_luarun.exe testbot.lua %*
pause
