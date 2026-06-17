@echo off
setlocal

set "GODOT_EXE=%USERPROFILE%\Desktop\R2\Godot_v4.6.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
	echo Could not find Godot at:
	echo   %GODOT_EXE%
	echo.
	echo Right-click this file and choose Edit if your Godot path is different.
	pause
	exit /b 1
)

pushd "%~dp0\.."
echo Running tests...
"%GODOT_EXE%" --headless --path . --script res://tests/test_runner.gd
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Exit code: %EXITCODE%
pause
popd
exit /b %EXITCODE%