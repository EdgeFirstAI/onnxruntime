#!/usr/bin/env bash
# package.sh — bundle a built ONNX Runtime tree into a redistributable
# tarball matching EDGEFIRST_ONNX.md §8 (modeled on tflite-rs releases).

set -euo pipefail

CONFIG="${CONFIG:-Release}"
TARGET_KEY="${TARGET_KEY:-linux-aarch64-jp62-cuda126}"
EDGEFIRST_BUILD="${EDGEFIRST_BUILD:-1}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/Linux/$CONFIG"
DIST_DIR="$REPO_ROOT/dist"

# ORT_VERSION derived from VERSION_NUMBER in the source tree (single source
# of truth — avoids drifting from the upstream version string).
ORT_VERSION="$(cat "$REPO_ROOT/VERSION_NUMBER" | tr -d '[:space:]')"
STAGE_NAME="onnxruntime-${ORT_VERSION}-edgefirst${EDGEFIRST_BUILD}-${TARGET_KEY}"
STAGE_DIR="$DIST_DIR/$STAGE_NAME"
TARBALL="$DIST_DIR/onnxruntime-${TARGET_KEY}.tar.gz"

echo "== Packaging =="
echo "version    : $ORT_VERSION"
echo "target key : $TARGET_KEY"
echo "build #    : $EDGEFIRST_BUILD"
echo "stage      : $STAGE_DIR"
echo "tarball    : $TARBALL"
echo

[ -d "$BUILD_DIR" ] || { echo "ERROR: build dir not found: $BUILD_DIR"; exit 1; }
[ -f "$BUILD_DIR/libonnxruntime.so" ] || { echo "ERROR: libonnxruntime.so missing in $BUILD_DIR"; exit 1; }

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/lib" "$STAGE_DIR/include"

# cp -P is load-bearing: preserves the symlink chain
#   libonnxruntime.so -> libonnxruntime.so.1 -> libonnxruntime.so.<ver>
# Without it, three full copies of the binary ship and SONAME linking breaks.
cp -P "$BUILD_DIR/"libonnxruntime.so* "$STAGE_DIR/lib/"
# Provider plugins are loaded by name via the shared providers framework;
# they are not part of the SONAME chain, so a plain cp is correct.
for so in libonnxruntime_providers_shared.so libonnxruntime_providers_cuda.so; do
    if [ -f "$BUILD_DIR/$so" ]; then
        cp "$BUILD_DIR/$so" "$STAGE_DIR/lib/"
    else
        echo "WARN: $so not found in $BUILD_DIR"
    fi
done

# C/C++ headers needed by consumers (rust ort, custom dlopen wrappers).
SRC_INC="$REPO_ROOT/include/onnxruntime/core/session"
if [ -d "$SRC_INC" ]; then
    cp "$SRC_INC/"onnxruntime_c_api.h "$STAGE_DIR/include/" 2>/dev/null || true
    cp "$SRC_INC/"onnxruntime_cxx_api.h "$STAGE_DIR/include/" 2>/dev/null || true
    cp "$SRC_INC/"onnxruntime_cxx_inline.h "$STAGE_DIR/include/" 2>/dev/null || true
    # CUDA EP provider options struct
    cp "$REPO_ROOT/include/onnxruntime/core/providers/cuda/"cuda_provider_options.h \
        "$STAGE_DIR/include/" 2>/dev/null || true
fi

cp "$REPO_ROOT/LICENSE" "$STAGE_DIR/"
cp "$REPO_ROOT/ThirdPartyNotices.txt" "$STAGE_DIR/" 2>/dev/null || true

# --- BUILD_INFO.txt provenance ----------------------------------------------
# Each probe is wrapped to never fail the build: a missing tool yields
# "unknown" rather than aborting under set -euo pipefail.
NVCC_BIN="$(command -v nvcc 2>/dev/null || echo /usr/local/cuda/bin/nvcc)"

# L4T: format "R<major>.<revision>" by joining "R36" and "4.7" from
# /etc/nv_tegra_release (avoids the brittle field-by-position approach).
L4T_MAJOR="$(grep -oE '^# R[0-9]+' /etc/nv_tegra_release 2>/dev/null | head -1 | sed 's/^# R//' || true)"
L4T_REV="$(grep -oE 'REVISION: [0-9.]+' /etc/nv_tegra_release 2>/dev/null | head -1 | sed 's/REVISION: //' || true)"
L4T_LINE="R${L4T_MAJOR:-?}.${L4T_REV:-?}"

# CUDA: extract just "12.6.68" from the "V12.6.68" tag in nvcc --version.
CUDA_LINE="$( "$NVCC_BIN" --version 2>/dev/null | grep -oE 'V[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^V//' || true)"
CUDA_LINE="${CUDA_LINE:-unknown}"

# CMake: prefer the cmake actually used by the build (CMakeCache.txt records
# its absolute path), so BUILD_INFO matches build-time even if the script is
# re-run outside the venv.
CMAKE_FROM_BUILD="$(grep '^CMAKE_COMMAND:' "$BUILD_DIR/CMakeCache.txt" 2>/dev/null | cut -d= -f2- || true)"
if [ -n "$CMAKE_FROM_BUILD" ] && [ -x "$CMAKE_FROM_BUILD" ]; then
    CMAKE_LINE="$("$CMAKE_FROM_BUILD" --version 2>/dev/null | head -1)"
else
    CMAKE_LINE="$(cmake --version 2>/dev/null | head -1 || echo unknown)"
fi

JETPACK_LINE="$(dpkg-query -W -f='${Version}\n' nvidia-jetpack 2>/dev/null \
    || dpkg-query -W -f='${Version}\n' nvidia-l4t-core 2>/dev/null \
    || echo unknown)"
CUDNN_LINE="$(dpkg-query -W -f='${Version}\n' libcudnn9-cuda-12 2>/dev/null || echo unknown)"
HW_LINE="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_DESC="$(git -C "$REPO_ROOT" describe --always --dirty 2>/dev/null || echo unknown)"
GCC_LINE="$(g++ --version 2>/dev/null | head -1 || echo unknown)"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$STAGE_DIR/BUILD_INFO.txt" <<INFO
ONNX Runtime ${ORT_VERSION}
EdgeFirst build: ${EDGEFIRST_BUILD}
Built: ${BUILT_AT}
Target: ${TARGET_KEY}
Hardware: ${HW_LINE} (sm_${CUDA_ARCH:-87})
L4T: ${L4T_LINE}
JetPack metapackage: ${JETPACK_LINE}
CUDA: ${CUDA_LINE}
cuDNN: ${CUDNN_LINE}
Compiler: ${GCC_LINE}
CMake: ${CMAKE_LINE}
Source commit: ${GIT_SHA}
Source describe: ${GIT_DESC}
Source: https://github.com/EdgeFirstAI/onnxruntime/tree/${GIT_SHA}
Upstream: https://github.com/microsoft/onnxruntime
INFO

echo "== Stage contents =="
ls -lhR "$STAGE_DIR"
echo

# --- tar + sha256 -----------------------------------------------------------
( cd "$DIST_DIR" && tar -czf "$(basename "$TARBALL")" "$(basename "$STAGE_DIR")" )
( cd "$DIST_DIR" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256" )

echo
echo "== Done =="
ls -lh "$TARBALL" "$TARBALL.sha256"
cat "$TARBALL.sha256"
