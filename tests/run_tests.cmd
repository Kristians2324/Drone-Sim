@echo off
setlocal

:: =============================================================================
:: Drone Sim – Headless Test Runner (Windows CMD)
:: Runs the full test suite including:
:: - BoidManager
:: - DroneInput
:: - DroneShowLightRig
:: - Boid
:: - SwarmController
:: - Menu / ESC Key Toggling
:: =============================================================================

set "GODOT_EXE=%USERPROFILE%\Desktop\godot\Godot_v4.6.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
	for %%F in ("%USERPROFILE%\Desktop\godot\*.exe") do (
		if exist "%%~fF" set "GODOT_EXE=%%~fF"
	)
)

if not exist "%GODOT_EXE%" (
	set "GODOT_EXE=%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe"
)

if not exist "%GODOT_EXE%" (
	echo Could not find Godot at:
	echo   %USERPROFILE%\Desktop\godot\*.exe
	echo   %USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe
	echo.
	echo Put Godot in a folder named ^"godot^" on your Desktop, or update this script.
	pause
	exit /b 1
)

pushd "%~dp0\.."

set "LOG=%~dp0test_output.txt"

echo Running tests...
echo.

:: Godot on Windows does not pipe stdout to the console when launched from cmd.
:: We redirect its output to a log file and then print it here.
"%GODOT_EXE%" --headless --path . --script res://tests/test_runner.gd > "%LOG%" 2>&1
set "EXITCODE=%ERRORLEVEL%"

:: Print the log to the console
type "%LOG%"

echo.
if "%EXITCODE%"=="0" (
	echo [ALL TESTS PASSED] Exit code: 0
) else (
	echo [TESTS FAILED] Exit code: %EXITCODE%
)

popd
pause
exit /b %EXITCODE%