@echo off
rem RE:Multiplayer Testbot starten. Optional: testbot.bat <ip> <port> <spiel>
cd /d "%~dp0"
remultiplayer_luarun.exe testbot.lua %*
pause
