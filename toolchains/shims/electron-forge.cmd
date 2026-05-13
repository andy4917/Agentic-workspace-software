@echo off
set "PATH=%LOCALAPPDATA%\OpenAI\Codex\bin;%PATH%"
"%APPDATA%\npm\electron-forge.cmd" %*
