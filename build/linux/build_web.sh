#!/bin/bash

# Build script for Godot ZX Emulator (Web/WASM)
# Follows official godot-rust documentation: https://godot-rust.github.io/book/toolchain/export-web.html

set -e

# Change to project root
cd "$(dirname "$0")/../.."

echo "Checking Rust Nightly and components..."
rustup toolchain install nightly
rustup component add rust-src --toolchain nightly
rustup target add wasm32-unknown-emscripten --toolchain nightly

echo "Building for Web (Release) using Nightly -Zbuild-std..."
# Note: Linker flags are managed in .cargo/config.toml

cargo +nightly build --release -Zbuild-std --target wasm32-unknown-emscripten

# Create bin directory if it doesn't exist
mkdir -p GodotProject/bin

# Copy the generated wasm file
cp target/wasm32-unknown-emscripten/release/godot_zx.wasm GodotProject/bin/godot_zx.wasm

echo "------------------------------------------------"
echo "Web build successful: GodotProject/bin/godot_zx.wasm"
echo "------------------------------------------------"
