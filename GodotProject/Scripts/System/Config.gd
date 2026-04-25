extends Node

## Central Configuration Class
## This class manages global paths for ROMs and Games, and tracks the currently selected game.
## It uses static variables to act as a Global Singleton that doesn't strictly need to be an Autoload, 
## though it is often used as one for initialization.

# --- ROM PATHS ---

## Standard 48K ROM (16KB) - The heart of the Sinclair ZX Spectrum 48K.
static var ROM_48K: String = ""

## Combined 128K ROM (32KB containing both Bank 0 and Bank 1).
## Most emulators expect a single 32KB file for the 128K model.
static var ROM_128K: String = "res://roms/128.rom"

## Separate 128K ROM - Bank 0 (16KB). Usually the 128K editor/menu ROM.
static var ROM_128_0: String = "res://roms/128-0"

## Separate 128K ROM - Bank 1 (16KB). Usually the 48K compatibility ROM.
static var ROM_128_1: String = "res://roms/128-1"


# --- HELPER METHODS ---

## Attempts to load 128K ROM data. 
## It first looks for a combined 32KB file, then for separate bank files.
static func get_128k_rom_data() -> PackedByteArray:
	# 1. Try the main combined ROM path (from Inspector or default 128.rom)
	if ROM_128K != "" and FileAccess.file_exists(ROM_128K):
		return FileAccess.get_file_as_bytes(ROM_128K)
	
	# 2. Try the separate bank paths defined in variables (ROM_128_0 and ROM_128_1)
	# Also tries lowercase and .rom extensions for maximum compatibility.
	var p0 = ""
	if FileAccess.file_exists(ROM_128_0): p0 = ROM_128_0
	elif FileAccess.file_exists(ROM_128_0 + ".rom"): p0 = ROM_128_0 + ".rom"
	elif FileAccess.file_exists(ROM_128_0.to_lower()): p0 = ROM_128_0.to_lower()
	elif FileAccess.file_exists(ROM_128_0.to_lower() + ".rom"): p0 = ROM_128_0.to_lower() + ".rom"

	if p0 != "":
		var p1 = ""
		var alt1 = "res://roms/ROM_128"
		
		# Check candidates for Bank 1
		var candidates = [ROM_128_1, ROM_128_1 + ".rom", ROM_128_1.to_lower(), ROM_128_1.to_lower() + ".rom", 
						  alt1, alt1 + ".rom", alt1.to_lower(), alt1.to_lower() + ".rom"]
		
		for c in candidates:
			if FileAccess.file_exists(c):
				p1 = c
				break
			
		if p1 != "":
			var data0 = FileAccess.get_file_as_bytes(p0)
			var data1 = FileAccess.get_file_as_bytes(p1)
			var combined = PackedByteArray()
			combined.append_array(data0)
			combined.append_array(data1)
			if combined.size() == 32768:
				print("Config: Auto-discovered separate ROMs: ", p0, " and ", p1)
				return combined

	# 3. Last fallback: legacy filenames
	var legacy_0 = "res://roms/128-0.rom"
	var legacy_1 = "res://roms/128-1.rom"
	if FileAccess.file_exists(legacy_0) and FileAccess.file_exists(legacy_1):
		var data0 = FileAccess.get_file_as_bytes(legacy_0)
		var data1 = FileAccess.get_file_as_bytes(legacy_1)
		var combined = PackedByteArray()
		combined.append_array(data0)
		combined.append_array(data1)
		if combined.size() == 32768:
			return combined

	return PackedByteArray()


# --- GAME PATHS ---

## Root directory where game files (.tap, .sna, .z80) are stored.
static var GAMES_DIR: String = "res://games/"

## The path of the game selected in the Launcher. 
static var selected_game_path: String = ""

# --- INITIALIZATION ---

## Checks if essential directories exist and creates them if they don't.
## This prevents "File not found" errors on fresh project installs.
static func setup():
	if not DirAccess.dir_exists_absolute("res://roms/"):
		DirAccess.make_dir_absolute("res://roms/")
		print("Config: Created missing ROMs directory.")
		
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		DirAccess.make_dir_absolute(GAMES_DIR)
		print("Config: Created missing Games directory.")

func _ready():
	# Automatically run directory setup when the app starts if this script is an Autoload.
	# This ensures the folder structure is always valid.
	setup()
