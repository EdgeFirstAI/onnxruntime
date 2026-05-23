#!/usr/bin/env bash
# build-jetson.sh — canonical EdgeFirst recipe for building ONNX Runtime
# with the CUDA execution provider on a Jetson device.
#
# Tested on: Jetson Orin Nano Super (sm_87), L4T R36.4.7, JetPack 6.2-era,
# CUDA 12.6, cuDNN 9.3, gcc 11.4.

set -euo pipefail

ORT_BUILD_TAG="${ORT_BUILD_TAG:-$(git describe --always --dirty 2>/dev/null || echo unknown)}"
EDGEFIRST_BUILD="${EDGEFIRST_BUILD:-1}"
# sm_87 = Orin (Ampere/Tegra). Fat binaries triple build time.
CUDA_ARCH="${CUDA_ARCH:-87}"
# -j6+ OOMs on 8 GB Orin Nano even with disk swap.
PARALLEL="${PARALLEL:-4}"
CONFIG="${CONFIG:-Release}"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
# Jetson puts cuDNN headers under /usr/include and libs under
# /usr/lib/aarch64-linux-gnu — passing /usr lets build.sh derive both.
CUDNN_HOME="${CUDNN_HOME:-/usr}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "== Preflight =="
echo "repo root : $REPO_ROOT"
echo "git tag   : $ORT_BUILD_TAG"
echo "cuda home : $CUDA_HOME"
echo "cudnn home: $CUDNN_HOME"
echo "cuda arch : sm_$CUDA_ARCH"
echo "parallel  : $PARALLEL"
echo "config    : $CONFIG"
echo

command -v cmake >/dev/null || { echo "ERROR: cmake not on PATH"; exit 1; }
command -v ninja >/dev/null || { echo "ERROR: ninja not on PATH"; exit 1; }
command -v nvcc  >/dev/null || command -v "$CUDA_HOME/bin/nvcc" >/dev/null \
    || { echo "ERROR: nvcc not found"; exit 1; }
[ -f "$CUDNN_HOME/include/aarch64-linux-gnu/cudnn_version_v9.h" ] \
    || [ -f "$CUDNN_HOME/include/cudnn_version.h" ] \
    || { echo "ERROR: cudnn headers not under $CUDNN_HOME/include"; exit 1; }

echo "== Memory before build =="
free -h
echo

# Flag rationale (EDGEFIRST_ONNX.md §7):
#   --build_shared_lib  → libonnxruntime.so.<ver> + EP plugins
#   --skip_tests        → halves build time; smoke-test separately
#   --use_cuda          → libonnxruntime_providers_cuda.so
#   CMAKE_CUDA_ARCHITECTURES=87 → pin to Orin sm_87
./build.sh \
    --config "$CONFIG" \
    --build_shared_lib \
    --parallel "$PARALLEL" \
    --skip_tests \
    --use_cuda \
    --cuda_home "$CUDA_HOME" \
    --cudnn_home "$CUDNN_HOME" \
    --cmake_extra_defines \
        "CMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH" \
        "onnxruntime_BUILD_UNIT_TESTS=OFF" \
    --allow_running_as_root

echo
echo "== Build succeeded =="
ls -lh "$REPO_ROOT/build/Linux/$CONFIG/"libonnxruntime*.so* 2>/dev/null || true
