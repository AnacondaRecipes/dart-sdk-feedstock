@echo on
setlocal enabledelayedexpansion

cd /d "%SRC_DIR%\sdk"

:: Normally written by gclient sync; without it gn cannot resolve the root
:: BUILD.gn's import. Keeps the prebuilt DevTools bundle from third_party\devtools.
> build\config\gclient_args.gni echo build_devtools_from_sources = false

:: gclient normally populates tools\sdks\dart-sdk with a prebuilt SDK that
:: bootstraps kernel compilation; use the official release zip from the recipe
:: instead. The archive's top-level dir may or may not be stripped on
:: extraction, so resolve both layouts.
if exist "%SRC_DIR%\bootstrap\bin\dart.exe" (
  set "BOOTSTRAP_SDK=%SRC_DIR%\bootstrap"
) else (
  set "BOOTSTRAP_SDK=%SRC_DIR%\bootstrap\dart-sdk"
)
if not exist "tools\sdks" mkdir "tools\sdks"
robocopy /E "!BOOTSTRAP_SDK!" "tools\sdks\dart-sdk" >nul
if %ERRORLEVEL% GEQ 8 exit /b 1

:: Upstream gclient hooks: the version file and the package config consumed by
:: the snapshot-compiling create_sdk actions.
python tools\generate_sdk_version_file.py
if %ERRORLEVEL% NEQ 0 exit /b 1
python tools\generate_package_config.py
if %ERRORLEVEL% NEQ 0 exit /b 1

:: Use the conda-provided Visual Studio installation instead of the
:: depot_tools-downloaded toolchain (see build/vs_toolchain.py).
set "DEPOT_TOOLS_WIN_TOOLCHAIN=0"
set "GYP_MSVS_OVERRIDE_PATH=%VSINSTALLDIR%"
set "WINDOWSSDKDIR=%VSINSTALLDIR%Windows Kits\10\"

gn gen out --args="target_cpu = \"x64\" is_debug = false is_release = true verify_sdk_hash = false"
if %ERRORLEVEL% NEQ 0 exit /b 1

ninja -C out create_sdk -j %CPU_COUNT%
if %ERRORLEVEL% NEQ 0 exit /b 1

robocopy /E "out\dart-sdk\bin" "%LIBRARY_BIN%"
if %ERRORLEVEL% GEQ 8 exit /b 1

robocopy /E "out\dart-sdk\lib" "%LIBRARY_LIB%"
if %ERRORLEVEL% GEQ 8 exit /b 1

robocopy /E "out\dart-sdk\include" "%LIBRARY_INC%"
if %ERRORLEVEL% GEQ 8 exit /b 1

copy /Y LICENSE "%LIBRARY_PREFIX%\LICENSE"
if %ERRORLEVEL% NEQ 0 exit /b 1

exit /b 0
