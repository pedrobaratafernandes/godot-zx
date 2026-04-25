# Binaries Directory

This folder contains the compiled GDExtension libraries for the project. These files are automatically generated when you run the build scripts in the `build/` directory.

### Expected Files:
*   **libgodot_zx.so** (Linux)
*   **godot_zx.dll** (Windows)
*   **godot_zx.wasm** (Web / WASM)
*   **godot_zx.threads.wasm** (Web / WASM with Threads)

### How to update:
To generate or update these files, use the scripts provided in the project root:
- Linux: `bash build/linux/build_linux.sh`
- Windows: `bash build/linux/build_windows.sh` (from Linux) or `build\win\build_windows.bat` (on Windows)
- Web (WASM): `bash build/linux/build_web_docker.sh`

*Note: These files are required for the Godot editor and exported games to function correctly.*
