@echo off
setlocal

set /p DISCORD_APPLICATION_ID=Discord Application ID [ex: 123456789012345678]: 
set /p DISCORD_GUILD_ID=Discord Guild ID [ex: 123456789012345678]: 
set /p DISCORD_BOT_TOKEN=Discord Bot Token [cole o token aqui]: 
set /p DISCORD_COMMAND_NAME=Command name [valheim]: 

if "%DISCORD_COMMAND_NAME%"=="" set DISCORD_COMMAND_NAME=valheim

node "%~dp0register-discord-commands.mjs"
if errorlevel 1 exit /b %errorlevel%

echo.
echo Command registration request completed.

endlocal
