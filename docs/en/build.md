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
There are two ways to build for the web. The Docker method is recommended as it handles all toolchain dependencies (Emscripten, Rust at the version fixed in `rust-toolchain.toml`) automatically.

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
Requires Emscripten 4.0.20 installed on your system (Rust is installed automatically at the version fixed in `rust-toolchain.toml`):
```bash
bash build/linux/build_web.sh
```

## Automated tests
The tests drive the emulator core without Godot (no need to build the extension or open the editor):
```bash
cargo test
```
What is checked:
- **TAP** (48K and 128K, with and without fastload): `znake.tap` ends up loaded in memory.
- **TZX** (48K and 128K): `znake.tap` is converted to TZX during the test and must load with fastload. A TZX with a turbo block must play in real time.
- **Turbo load**: the tape-playing detector covers the whole load, turns off when the tape ends or stalls, and barely acts with fastload.
- **SZX** (48K and 128K, with and without zlib compression): the same state loaded from SNA and from SZX runs identically, frame by frame.
- **SNA**: saving and restoring a running game (the save-state format).
- **Every game in `GodotProject/games/`**: each `.tap`, `.tzx`, `.sna` or `.szx` file must load without errors and show a picture 20 emulated seconds after the tape stops. Files with `128` in the name run in 128K mode. To test a new game, just copy it into that folder.

The tests live in `src/tests.rs`.
