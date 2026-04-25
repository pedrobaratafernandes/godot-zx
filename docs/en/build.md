# Build Instructions

## Build for Linux
Run the dedicated script from the root:
```bash
bash build/linux/build_linux.sh
```

## Build for Windows
### From Linux (Cross-compilation)
The script will automatically check for the required Rust target and install it if missing:
```bash
bash build/linux/build_windows.sh
```
*Note: Requires mingw-w64 installed on your host system.*

### From Windows (Native)
If you are developing directly on a Windows machine, use the batch script. It performs the same tasks as the Linux script (compiling and copying the DLL) but uses native Windows commands:
```batch
.\build\win\build_windows.bat
```

## Build for Web (WASM)
There are two ways to build for the web. The Docker method is recommended as it handles all toolchain dependencies (Emscripten, Rust Nightly) automatically.

### Using Docker (Recommended)
This script builds both threaded and non-threaded versions of the WASM binary:
```bash
bash build/linux/build_web_docker.sh
```
*Tip for Linux: If you get a permission error, ensure your user is in the docker group to run without `sudo`:*
```bash
sudo usermod -aG docker $USER
# Then log out and log back in.
```

### Native Build
Requires Rust Nightly and Emscripten installed on your system:
```bash
bash build/linux/build_web.sh
```
