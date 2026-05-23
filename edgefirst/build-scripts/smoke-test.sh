#!/usr/bin/env bash
# smoke-test.sh — post-build sanity check (EDGEFIRST_ONNX.md §11).
# Compiles a minimal C++ program against the freshly-built libonnxruntime
# and asserts that CUDAExecutionProvider is listed in available providers.
# A success here proves both the .so and the CUDA EP plugin load cleanly —
# the most common silent failure (cuDNN ABI mismatch) shows up as a missing
# CUDAExecutionProvider rather than a build error.

set -euo pipefail

CONFIG="${CONFIG:-Release}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/Linux/$CONFIG"
SMOKE_DIR="$REPO_ROOT/build/smoke"

mkdir -p "$SMOKE_DIR"
cat > "$SMOKE_DIR/smoke.cpp" <<'CPP'
#include <onnxruntime_cxx_api.h>
#include <iostream>

int main() {
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "smoke");
    auto providers = Ort::GetAvailableProviders();
    bool cuda_seen = false;
    std::cout << "Available providers (" << providers.size() << "):\n";
    for (const auto& p : providers) {
        std::cout << "  " << p << "\n";
        if (p == "CUDAExecutionProvider") cuda_seen = true;
    }
    if (!cuda_seen) {
        std::cerr << "FAIL: CUDAExecutionProvider not present\n";
        return 1;
    }
    std::cout << "OK: CUDAExecutionProvider present\n";
    return 0;
}
CPP

# Compile against the build tree's headers and libs.
# -Wl,-rpath,$ORIGIN/../lib would be used in the packaged tarball; here we
# point rpath at the build dir directly so we don't have to install first.
g++ -std=c++17 -O0 "$SMOKE_DIR/smoke.cpp" \
    -I "$REPO_ROOT/include/onnxruntime/core/session" \
    -L "$BUILD_DIR" \
    -lonnxruntime \
    -Wl,-rpath,"$BUILD_DIR" \
    -o "$SMOKE_DIR/smoke"

echo "== Running smoke test =="
"$SMOKE_DIR/smoke"
