#!/bin/bash
set -ex

cd "$SRC_DIR/sdk"

# Normally written by gclient sync; without it gn cannot resolve the root
# BUILD.gn's import. build_devtools_from_sources=false keeps the prebuilt
# DevTools bundle from third_party/devtools (fetched via CIPD in the recipe).
cat > build/config/gclient_args.gni <<'GNI'
build_devtools_from_sources = false
GNI

# gclient normally populates tools/sdks/dart-sdk with a prebuilt SDK that
# bootstraps kernel compilation (bootstrap_compile_platform); use the official
# release zip from the recipe instead. The archive's top-level dir may or may
# not be stripped on extraction, so resolve both layouts.
if [[ -x "$SRC_DIR/bootstrap/bin/dart" ]]; then
  BOOTSTRAP_SDK="$SRC_DIR/bootstrap"
else
  BOOTSTRAP_SDK="$SRC_DIR/bootstrap/dart-sdk"
fi
mkdir -p tools/sdks
ln -sfn "$BOOTSTRAP_SDK" tools/sdks/dart-sdk

# Upstream gclient hooks: the version file and the package config consumed by
# the snapshot-compiling create_sdk actions (both run with the bootstrap dart).
python3 tools/generate_sdk_version_file.py
python3 tools/generate_package_config.py

# Wire the conda toolchain into the GN build the same way Arch does with sed:
# upstream hardcodes depot_tools/CIPD toolchain paths that we don't fetch.
GN_ARGS="is_debug = false is_release = true verify_sdk_hash = false"
if [[ "$(uname)" == "Darwin" ]]; then
  host_cpu_dir="mac-x64"
  if [[ "$(uname -m)" == "arm64" ]]; then
    host_cpu_dir="mac-arm64"
  fi
  # The mac toolchain file hardcodes //buildtools/mac-*/clang/bin (CIPD clang);
  # point it at the conda toolchain instead.
  sed -i.bak \
    "s|rebase_path(\"//buildtools/${host_cpu_dir}/clang/bin\", root_build_dir)|rebase_path(\"$BUILD_PREFIX/bin\", root_build_dir)|" \
    build/toolchain/mac/mac_toolchain.gni
  rm -f build/toolchain/mac/mac_toolchain.gni.bak
  # compiler/BUILD.gn reads a CIPD toolchain version stamp for is_clang builds
  # (to force relinks when the toolchain changes); synthesize it for conda clang.
  mkdir -p "buildtools/${host_cpu_dir}/clang/.versions"
  printf '{"instance_id": "conda-clang"}\n' > "buildtools/${host_cpu_dir}/clang/.versions/clang.cipd_version"
  # mac_sdk.gni runs find_sdk.py unconditionally, which rejects conda workers
  # without Xcode; guard discovery so mac_sdk_path (the conda sysroot) wins.
  python3 - <<'PY'
p = 'build/config/mac/mac_sdk.gni'
s = open(p).read()
old = '''find_sdk_lines =
    exec_script("//build/mac/find_sdk.py", find_sdk_args, "list lines")
mac_sdk_version = find_sdk_lines[1]
if (mac_sdk_path == "") {
  mac_sdk_path = find_sdk_lines[0]
}'''
new = '''if (mac_sdk_path == "") {
  find_sdk_lines =
      exec_script("//build/mac/find_sdk.py", find_sdk_args, "list lines")
  mac_sdk_version = find_sdk_lines[1]
  mac_sdk_path = find_sdk_lines[0]
} else {
  mac_sdk_version = mac_sdk_min
}'''
assert s.count(old) == 1
open(p, 'w').write(s.replace(old, new))
PY
  GN_ARGS="$GN_ARGS mac_sdk_path = \"${CONDA_BUILD_SYSROOT}\""
  GN_ARGS="$GN_ARGS mac_sdk_min = \"${MACOSX_DEPLOYMENT_TARGET:-10.13}\""
  if [[ "$(uname -m)" == "arm64" ]]; then
    GN_ARGS="$GN_ARGS target_cpu = \"arm64\""
  else
    GN_ARGS="$GN_ARGS target_cpu = \"x64\""
  fi
else
  # gcc toolchain suites take a binary-name prefix via gn args; conda's
  # cross-prefixed gcc/binutils names come from CONDA_TOOLCHAIN_HOST (the
  # compiler binary itself may end in -cc or -gcc, so strip either).
  TC_PREFIX="${CONDA_TOOLCHAIN_HOST:-$(basename "$CC")}"
  TC_PREFIX="${TC_PREFIX%-cc}"
  TC_PREFIX="${TC_PREFIX%-gcc}"
  TC_PREFIX="${TC_PREFIX}-"
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
ninja -C out create_sdk -j "${CPU_COUNT}"

cp -R out/dart-sdk/bin "$PREFIX"/
cp -R out/dart-sdk/lib "$PREFIX"/
cp -R out/dart-sdk/include "$PREFIX"/
cp LICENSE "$PREFIX"/
