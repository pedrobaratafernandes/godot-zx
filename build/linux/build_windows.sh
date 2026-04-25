#!/bin/bash

# Move to the project root directory (two levels up from this script in build/linux/)
cd "$(dirname "$0")/../.." || exit

# Target directory for binaries
BIN_DIR="GodotProject/bin"
mkdir -p "$BIN_DIR"

echo "Checking for Windows target..."
if ! rustup target list --installed | grep -q "x86_64-pc-windows-gnu"; then
    echo "Target x86_64-pc-windows-gnu not found. Installing..."
    rustup target add x86_64-pc-windows-gnu
else
    echo "Target x86_64-pc-windows-gnu is already installed."
fi

echo "Building for Windows (x86_64 Release)..."


cargo build --target x86_64-pc-windows-gnu --release

if [ $? -eq 0 ]; then
    cp target/x86_64-pc-windows-gnu/release/godot_zx.dll "$BIN_DIR/"
    echo "------------------------------------------------"
    echo "Windows build successful: $BIN_DIR/godot_zx.dll"
    echo "------------------------------------------------"
else
    echo "Windows build failed."
    echo "Make sure you have the 'mingw-w64' C toolchain installed on your Linux system."
    echo "sudo apt install mingw-w64 (on Ubuntu/Debian)"
    echo "sudo pacman -S mingw-w64-gcc (on Arch)"
    echo "sudo dnf install mingw-w64-gcc (on Fedora)"
    exit 1
fi
