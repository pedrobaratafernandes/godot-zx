#!/bin/bash

# Build script for Godot ZX Emulator (Web/WASM)
# Follows official godot-rust documentation: https://godot-rust.github.io/book/toolchain/export-web.html

set -e

# Change to project root
cd "$(dirname "$0")/../.."

echo "Installing the Rust version fixed in rust-toolchain.toml (with rust-src and wasm target)..."
rustup toolchain install

echo "Building for Web (Release) using -Zbuild-std..."
# Note: Linker flags are managed in .cargo/config.toml

RUSTC_BOOTSTRAP=1 cargo build --release -Zbuild-std --target wasm32-unknown-emscripten

# Create bin directory if it doesn't exist
mkdir -p GodotProject/bin

# Copy the generated wasm file
cp target/wasm32-unknown-emscripten/release/godot_zx.wasm GodotProject/bin/godot_zx.wasm

echo "------------------------------------------------"
echo "Web build successful: GodotProject/bin/godot_zx.wasm"
echo "------------------------------------------------"
