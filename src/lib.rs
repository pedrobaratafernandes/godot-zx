use godot::prelude::*;

// We import our modules so the compiler knows they exist
// 'host' contains the implementation of the rustzx interface for Godot
// 'emulator_node' contains the actual Godot Nodes that can be used in scenes
mod host;
mod emulator_node;

/// This is the main structure for our GDExtension library.
/// It acts as the "anchor" point that Godot looks for when loading the library.
/// The name of the library is defined in the Cargo.toml file.
struct GodotZX;

/// The #[gdextension] macro tells godot-rust to generate the entry point
/// for this library (usually called 'gdext_rust_init').
/// This allows Godot to discover and register all #[derive(GodotClass)] 
/// structures we've defined in our modules.
///
/// We mark it as 'unsafe' because GDExtension initialization involves
/// interfacing directly with C-style pointers and memory.
#[gdextension]
unsafe impl ExtensionLibrary for GodotZX {}

