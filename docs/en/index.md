# Introduction

A high-performance ZX Spectrum emulator integrated into Godot 4.3+ using Rust and GDExtension. This project is designed to be highly modular, Steam-ready, and supports both common computer usage and full gamepad navigation.

## Documentation Index
- [Build Instructions](build.md)
- [User Guide & Features](guide.md)
- [Keyboard & Controls](controls.md)

## Technical Specifications
- **Core Engine**: rustzx-core (Rust)
- **Godot Bridge**: godot-rust (GDExtension)
- **Rust Version**: 1.95.0
- **Godot Version**: 4.3 or higher

## Technical Architecture
This project uses a high-performance hybrid architecture:
*   **Core (Rust)**: The emulation engine (`rustzx-core`) runs in Rust, handling Z80 CPU, video generation, and sound synthesis.
*   **GDExtension**: Using `godot-rust`, the code is compiled into a native library (`.dll`, `.so`, or `.wasm`). Godot loads this as a native `EmulatorNode`.
*   **Frontend (Godot)**: Handles visuals, UI, input processing, and final audio output via `AudioStreamGenerator`.
