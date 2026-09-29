@echo on
setlocal enabledelayedexpansion

cd /d "%SRC_DIR%\sdk"

:: Upstream generates this file via a gclient hook before building.
python tools\generate_sdk_version_file.py

:: Use the conda-provided Visual Studio installation instead of the
:: depot_tools-downloaded toolchain (see build/vs_toolchain.py).
set "DEPOT_TOOLS_WIN_TOOLCHAIN=0"
set "GYP_MSVS_OVERRIDE_PATH=%VSINSTALLDIR%"
set "WINDOWSSDKDIR=%VSINSTALLDIR%Windows Kits\10\"

gn gen out --args="target_cpu = \"x64\" is_debug = false is_release = true verify_sdk_hash = false"

:: Build the VM first, then use it to generate the package config that the
:: snapshot-compiling create_sdk actions consume (upstream uses a checked-in
:: prebuilt dart-sdk for this; we self-bootstrap instead).
ninja -C out dart -j %CPU_COUNT%
out\dart.exe --packages=tools\empty_package_config.json tools\generate_package_config.dart

ninja -C out create_sdk -j %CPU_COUNT%

robocopy /E "out\dart-sdk\bin" "%LIBRARY_BIN%"
if %ERRORLEVEL% GEQ 8 exit /b 1

robocopy /E "out\dart-sdk\lib" "%LIBRARY_LIB%"
if %ERRORLEVEL% GEQ 8 exit /b 1

robocopy /E "out\dart-sdk\include" "%LIBRARY_INC%"
if %ERRORLEVEL% GEQ 8 exit /b 1

copy /Y LICENSE "%LIBRARY_PREFIX%\LICENSE"
if %ERRORLEVEL% NEQ 0 exit /b 1

exit /b 0
