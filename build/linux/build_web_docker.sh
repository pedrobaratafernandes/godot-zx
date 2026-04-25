#!/bin/bash

# Multi-build script for Godot ZX Emulator (Web/WASM)
# Uses Nightly Rust and -Zbuild-std for maximum compatibility
set -e

# Change to project root
cd "$(dirname "$0")/../.."

echo "Building Docker image..."
docker build -t zx-emulator-web -f Dockerfile.web .

# --- 1. Threaded Build ---
echo "Building Threaded WASM (godot_zx.threads.wasm)..."
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "/$(pwd):/src" \
    -e RUSTFLAGS="-C link-args=-pthread -C target-feature=+atomics -C link-args=-sSIDE_MODULE=2 -C llvm-args=-enable-emscripten-cxx-exceptions=0 -Z default-visibility=hidden -Z link-native-libraries=no -Z emscripten-wasm-eh=false" \
    zx-emulator-web cargo +nightly build --release -Zbuild-std=std,panic_abort --target wasm32-unknown-emscripten

mkdir -p GodotProject/bin

if [ -f "target/wasm32-unknown-emscripten/release/godot_zx.wasm" ]; then
    cp target/wasm32-unknown-emscripten/release/godot_zx.wasm GodotProject/bin/godot_zx.threads.wasm
else
    echo "Error: Threaded WASM file not found in target directory!"
    ls -R target/wasm32-unknown-emscripten/release/
    exit 1
fi

# --- 2. Non-threaded Build ---
echo "Building Non-threaded WASM (godot_zx.wasm)..."
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "/$(pwd):/src" \
    zx-emulator-web cargo +nightly build --release --features nothreads -Zbuild-std=std,panic_abort --target wasm32-unknown-emscripten

if [ -f "target/wasm32-unknown-emscripten/release/godot_zx.wasm" ]; then
    cp target/wasm32-unknown-emscripten/release/godot_zx.wasm GodotProject/bin/godot_zx.wasm
else
    echo "Error: WASM file not found in target directory!"
    ls -R target/wasm32-unknown-emscripten/release/
    exit 1
fi

echo "------------------------------------------------"
echo "Web Multi-build successful!"
echo "Files in GodotProject/bin/:"
echo "  - godot_zx.threads.wasm"
echo "  - godot_zx.wasm"
echo "------------------------------------------------"
