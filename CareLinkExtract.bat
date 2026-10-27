@echo off

rem Restart this script in a minimized window; Python brings the window back up if something fails
if not "%CARELINK_MINIMIZED%"=="1" (
	set CARELINK_MINIMIZED=1
	start "CareLink Extract" /min cmd /c ""%~f0" %*"
	exit /b
)

pushd "%~dp0"
echo Starting CareLink data extract...
python -m src.main %*
set RESULT=%errorlevel%
popd

rem 0 = success (Python already showed a result popup), 2 = cancelled by the user: close the window
if "%RESULT%"=="0" exit /b 0
if "%RESULT%"=="2" exit /b 2

rem Anything else is an error: keep the window open until the user closes it
echo.
echo Failed to extract and send data. See the error above.
echo.
echo You can close this window now.
:wait
pause >nul
goto wait
