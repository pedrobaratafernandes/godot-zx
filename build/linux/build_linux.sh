#!/bin/bash

# Move to the project root directory (two levels up from this script in build/linux/)
cd "$(dirname "$0")/../.." || exit

# Target directory for binaries
BIN_DIR="GodotProject/bin"
mkdir -p "$BIN_DIR"

# Build for Linux
echo "Building for Linux (Release)..."
cargo build --release

if [ $? -eq 0 ]; then
    cp target/release/libgodot_zx.so "$BIN_DIR/"
    echo "------------------------------------------------"
    echo "Linux build successful: $BIN_DIR/libgodot_zx.so"
    echo "------------------------------------------------"
else
    echo "Linux build failed"
    exit 1
fi
