@echo off
:: Change to the project root directory
pushd "%~dp0"
cd ..\..

set BIN_DIR=GodotProject\bin
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

echo Building for Windows (Release)...
cargo build --release

if %ERRORLEVEL% EQU 0 (
    copy /Y target\release\godot_zx.dll "%BIN_DIR%\"
    echo ------------------------------------------------
    echo Windows build successful: %BIN_DIR%\godot_zx.dll
    echo ------------------------------------------------
) else (
    echo Windows build failed.
    pause
    popd
    exit /b 1
)

pause
popd
