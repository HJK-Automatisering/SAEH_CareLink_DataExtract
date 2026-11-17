@echo off

rem Restart this script in a minimized window; Python brings the window back up if something fails
if not "%CARELINK_MINIMIZED%"=="1" (
	set CARELINK_MINIMIZED=1
	start "CareLink Extract" /min cmd /c ""%~f0" %*"
	exit /b
)

pushd "%~dp0"

rem Get the latest version from GitHub before running. Skipped if git is missing or this is not a git clone,
rem and if the update fails (offline, local changes, ...) the current version is used instead.
rem Never wait for a username/password typed in this minimized window (the Git Credential Manager popup still works)
set GIT_TERMINAL_PROMPT=0
set "OLD_HEAD="
for /f %%h in ('git rev-parse HEAD 2^>nul') do set "OLD_HEAD=%%h"
rem Everything below is inside one block on purpose: cmd reads the whole block before running it,
rem so it is safe even when git pull replaces this file while it is running
if defined OLD_HEAD if not defined CARELINK_UPDATED (
	set CARELINK_UPDATED=1
	echo Checking for updates...
	git pull --ff-only --quiet
	if errorlevel 1 (
		echo Could not update from GitHub. Running the current version.
	) else (
		git diff --quiet %OLD_HEAD% HEAD -- requirements.txt || (
			echo Installing updated Python packages...
			python -m pip install -r requirements.txt --quiet --disable-pip-version-check || echo Could not install the updated packages.
		)
		git diff --quiet %OLD_HEAD% HEAD -- CareLinkExtract.bat || (
			echo The launcher was updated. Restarting...
			popd
			rem The new launcher shows its own result and error window; this window just closes afterwards
			cmd /c ""%~f0" %*"
			exit /b
		)
	)
)

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
