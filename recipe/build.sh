#!/bin/bash
set -ex

cd "$SRC_DIR/sdk"

# Upstream generates this file via a gclient hook before building; the ninja
# create_sdk target and version stamping read it.
python3 tools/generate_sdk_version_file.py

# Wire the conda toolchain into the GN build the same way Arch does with sed:
# upstream hardcodes depot_tools/CIPD toolchain paths that we don't fetch.
GN_ARGS="is_debug = false is_release = true verify_sdk_hash = false"
if [[ "$(uname)" == "Darwin" ]]; then
  # The mac toolchain file hardcodes //buildtools/mac-*/clang/bin (CIPD clang);
  # point it at the conda toolchain instead.
  if [[ "$(uname -m)" == "arm64" ]]; then
    TC_FILE="build/toolchain/mac/mac_toolchain.gni"
    SED_EXPR='s|rebase_path("//buildtools/mac-arm64/clang/bin", root_build_dir)|rebase_path("'"$BUILD_PREFIX"'/bin", root_build_dir)|'
  else
    TC_FILE="build/toolchain/mac/mac_toolchain.gni"
    SED_EXPR='s|rebase_path("//buildtools/mac-x64/clang/bin", root_build_dir)|rebase_path("'"$BUILD_PREFIX"'/bin", root_build_dir)|'
  fi
  sed -i.bak "$SED_EXPR" "$TC_FILE" && rm -f "$TC_FILE.bak"
  GN_ARGS="$GN_ARGS mac_sdk_path = \"${CONDA_BUILD_SYSROOT}\""
  GN_ARGS="$GN_ARGS mac_sdk_min = \"${MACOSX_DEPLOYMENT_TARGET:-10.13}\""
  if [[ "$(uname -m)" == "arm64" ]]; then
    GN_ARGS="$GN_ARGS target_cpu = \"arm64\""
  else
    GN_ARGS="$GN_ARGS target_cpu = \"x64\""
  fi
else
  # gcc toolchain suites take a binary-name prefix via gn args; conda's
  # cross-prefixed gcc/binutils names come straight from $CC.
  TC_PREFIX="${CC%-gcc}-"
  GN_ARGS="$GN_ARGS is_clang = false"
  if [[ "$(uname -m)" == "aarch64" ]]; then
    GN_ARGS="$GN_ARGS target_cpu = \"arm64\""
    GN_ARGS="$GN_ARGS arm64_toolchain_prefix = \"${TC_PREFIX}\""
  else
    GN_ARGS="$GN_ARGS target_cpu = \"x64\""
    GN_ARGS="$GN_ARGS x64_toolchain_prefix = \"${TC_PREFIX}\""
  fi
fi

gn gen out --args="$GN_ARGS"

# Build the VM first, then use it to generate the package config that the
# snapshot-compiling create_sdk actions consume (upstream uses a checked-in
# prebuilt dart-sdk for this; we self-bootstrap instead).
ninja -C out dart -j "${CPU_COUNT}"
out/dart --packages=tools/empty_package_config.json tools/generate_package_config.dart

ninja -C out create_sdk -j "${CPU_COUNT}"

cp -R out/dart-sdk/bin "$PREFIX"/
cp -R out/dart-sdk/lib "$PREFIX"/
cp -R out/dart-sdk/include "$PREFIX"/
cp LICENSE "$PREFIX"/
