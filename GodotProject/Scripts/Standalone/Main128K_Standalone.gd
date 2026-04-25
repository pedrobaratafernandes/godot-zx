@tool
extends Control

# This script is a "Standalone" version of the 128K emulator.
# It is designed to be used when exporting a single 128K game as its own executable.

@onready var emulator: ZXEmulator128K = $ZXEmulator128K
@onready var display: TextureRect = $Display
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var menu: CanvasLayer = $GameMenu

@export_category("Standalone Configuration")
## The specific Spectrum 128K game file (.tap, .sna, .z80) to load.
@export_file("*.tap", "*.sna", "*.szx", "*.z80", "*.scr") var game_path: String = ""

## If enabled, the game will try to load 'autoload.tap' from the web server when running in a browser.
@export var web_autoload: bool = true:
	set(value):
		web_autoload = value
		if web_autoload:
			game_path = ""
			print("[Standalone] Web Autoload enabled. Clearing game_path.")
		notify_property_list_changed()

## The 128K ROM file (32KB combined).
@export_file("*.rom") var rom_128k_path: String = "res://roms/128.rom"

## Separate 128K ROM - Bank 0 (16KB).
@export_file("*.rom") var rom_128_0_path: String = ""

## Separate 128K ROM - Bank 1 (16KB).
@export_file("*.rom") var rom_128_1_path: String = ""


var zx_actions: Array[StringName] = []
var audio_playback: AudioStreamGeneratorPlayback
var mouse_accumulation: Vector2 = Vector2.ZERO

@export_group("Spectrum Arrow Mapping")
## Spectrum key to press when Arrow Up is held.
@export var key_up: String = "7"
## Spectrum key to press when Arrow Down is held.
@export var key_down: String = "6"
## Spectrum key to press when Arrow Left is held.
@export var key_left: String = "5"
## Spectrum key to press when Arrow Right is held.
@export var key_right: String = "8"

@export_group("Joystick Mapping")
## Enable Kempston Joystick signals on arrow keys / D-pad.
@export var joystick_kempston: bool = true
## Enable Sinclair Joystick signals on arrow keys / D-pad.
@export var joystick_sinclair: bool = true
## Which Sinclair Joystick to use (1 = keys 6-0, 2 = keys 1-5).
@export_range(1, 2) var sinclair_joy_num: int = 1

func _get_save_path() -> String:
	if game_path == "": return "user://saves/standalone_128k.sna"
	var safe_name = game_path.replace("res://", "").replace("/", "_").replace(":", "_").replace(".", "_")
	return "user://saves/" + safe_name + "_128k.sna"

func _validate_property(property: Dictionary):
	if property.name == "game_path":
		if web_autoload:
			property.usage = PROPERTY_USAGE_NONE # Completamente escondido
		else:
			property.usage = PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE

func _ready():
	if Engine.is_editor_hint(): return
	
	# 1. Initialize Audio
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()
	
	# 2. Initialize Input Mapping
	for action in InputMap.get_actions():
		if action.begins_with("zx_"):
			zx_actions.append(action)
	
	# 3. Connect Menu signals for UI interaction
	menu.resume_requested.connect(_toggle_pause)
	menu.save_requested.connect(_save_state)
	menu.load_requested.connect(_load_state)
	menu.reset_requested.connect(_on_reset_requested)
	menu.quit_requested.connect(_on_quit_requested)
	menu.volume_changed.connect(_change_volume)
	menu.fullscreen_requested.connect(_toggle_fullscreen)
	
	if menu.has_node("%LauncherButton"):
		menu.get_node("%LauncherButton").hide()
	
	# 4. Update Menu Status
	var game_name = game_path.get_file()
	if game_name == "": game_name = "Standalone"
	menu.set_status("Machine: 128K | Game: " + game_name)
	
	# 5. Capture Mouse for Kempston Mouse support
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# 6. Load the specific standalone game
	if web_autoload and OS.has_feature("web") and game_path == "":
		_try_web_autoload()
	else:
		_load_standalone_game()

func _load_standalone_game():
	# 1. ROM Loading
	_load_standalone_roms()
	
	# 2. Game Loading
	if game_path != "" and FileAccess.file_exists(game_path):
		var ext = game_path.get_extension().to_lower()
		var data = FileAccess.get_file_as_bytes(game_path)
		
		match ext:
			"tap":
				emulator.load_tape(data)
				emulator.start_tape_load()
				print("Standalone 128K Tape loaded: ", game_path)
			"sna", "z80":
				emulator.load_snapshot(data)
				print("Standalone 128K Snapshot loaded: ", game_path)
			"szx":
				push_warning("SZX format not supported in this build. Use .SNA or .Z80.")
			"scr":
				print("Standalone 128K Screen dump preview only: ", game_path)
			_:
				push_error("Standalone Error: Unsupported file format: " + ext)
	else:
		push_warning("[ZX] Starting with ROM only. (No game selected)")

func _load_standalone_roms():
	var rom_data: PackedByteArray
	
	# A) Check if separate banks are provided in the inspector
	if rom_128_0_path != "" and rom_128_1_path != "" and FileAccess.file_exists(rom_128_0_path) and FileAccess.file_exists(rom_128_1_path):
		var data0 = FileAccess.get_file_as_bytes(rom_128_0_path)
		var data1 = FileAccess.get_file_as_bytes(rom_128_1_path)
		rom_data.append_array(data0)
		rom_data.append_array(data1)
		if rom_data.size() == 32768:
			print("Standalone 128K ROM loaded from separate inspector paths.")
		else:
			rom_data.clear() # Invalid size
	
	# B) Check if combined ROM is provided in the inspector
	if rom_data.size() == 0 and rom_128k_path != "" and FileAccess.file_exists(rom_128k_path):
		rom_data = FileAccess.get_file_as_bytes(rom_128k_path)
		print("Standalone 128K ROM loaded from combined inspector path: ", rom_128k_path)
	
	# C) Automatic Discovery Fallback
	if rom_data.size() == 0:
		rom_data = Config.get_128k_rom_data()
		if rom_data.size() > 0:
			print("Standalone 128K ROM loaded via automatic discovery.")
		else:
			push_error("Standalone Error: 128K ROM not found. Please check paths in res://roms/")
			return
			
	emulator.load_rom(rom_data)

# --- WEB AUTOLOAD LOGIC ---

func _try_web_autoload():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_autoload_completed)
	
	# Construct absolute URL using JavaScript
	var url = "autoload.tap"
	if OS.has_feature("web"):
		var base_url = JavaScriptBridge.eval("window.location.href.substring(0, window.location.href.lastIndexOf('/'))")
		if base_url:
			url = base_url + "/autoload.tap"
			
	print("[ZX] Attempting web autoload at: ", url)
	
	var err = http.request(url)
	if err != OK:
		print("[ZX] Error starting HTTP request: ", err)
		_load_standalone_game()

func _on_autoload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
		print("[ZX] SUCCESS! autoload.tap loaded (", body.size(), " bytes).")
		
		# Ensure ROM is loaded first
		_load_standalone_roms()
		
		emulator.load_tape(body)
		emulator.start_tape_load()
		menu.set_status("Machine: 128K | Game: autoload.tap (Web)")
	else:
		print("[ZX] Autoload failed.")
		print("  - Godot Error: ", result)
		print("  - HTTP Code: ", response_code)
		_load_standalone_game()

func _process(_delta):
	if emulator.is_paused(): return
	var tex = emulator.get_texture()
	if tex: display.texture = tex
	_fill_audio_buffer()

func _fill_audio_buffer():
	if not audio_playback: return
	var samples = emulator.get_audio_samples()
	if samples.size() > 0:
		var frames = samples.size() / 2
		for i in range(frames):
			audio_playback.push_frame(Vector2(samples[i * 2], samples[i * 2 + 1]))

## Sends a joystick direction/fire signal to the enabled joystick interfaces.
func _send_joy(direction: String, pressed: bool):
	if joystick_kempston:
		emulator.send_joystick(direction, pressed)
	if joystick_sinclair:
		emulator.send_sinclair(sinclair_joy_num, direction, pressed)

func _toggle_pause():
	var new_state = not emulator.is_paused()
	emulator.set_paused(new_state)
	if new_state:
		menu.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _save_state():
	if not DirAccess.dir_exists_absolute("user://saves"):
		DirAccess.make_dir_absolute("user://saves")
		
	var data = emulator.save_snapshot()
	if data.size() > 0:
		var file = FileAccess.open(_get_save_path(), FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			print("Standalone Snapshot saved: ", _get_save_path())

func _load_state():
	var path = _get_save_path()
	if FileAccess.file_exists(path):
		var data = FileAccess.get_file_as_bytes(path)
		if data.size() > 0:
			emulator.load_snapshot(data)
			print("Standalone Snapshot loaded: ", path)
			_toggle_pause()

func _change_volume(v):
	audio_player.volume_db = linear_to_db(v)

func _toggle_fullscreen():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _input(event):
	# Toggle Pause Menu
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	
	if emulator.is_paused(): return
	
	# 1. ARROW / JOYSTICK DIRECTION MAPPING
	if event.is_action("arrow_up"):
		var pressed = event.is_pressed()
		emulator.send_key(key_up, pressed)
		_send_joy("UP", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_down"):
		var pressed = event.is_pressed()
		emulator.send_key(key_down, pressed)
		_send_joy("DOWN", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_left"):
		var pressed = event.is_pressed()
		emulator.send_key(key_left, pressed)
		_send_joy("LEFT", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_right"):
		var pressed = event.is_pressed()
		emulator.send_key(key_right, pressed)
		_send_joy("RIGHT", pressed)
		get_viewport().set_input_as_handled()
		return

	# 2. JOYSTICK FIRE MAPPING (zx_fire action)
	if event.is_action("zx_fire"):
		_send_joy("FIRE", event.is_pressed())
		get_viewport().set_input_as_handled()
		return

	# 3. DYNAMIC KEYBOARD MAPPING
	for action in zx_actions:
		if event.is_action(action):
			var zx_key_name = action.substr(3)
			var pressed = event.is_pressed()
			emulator.send_key(zx_key_name, pressed)
			get_viewport().set_input_as_handled()
			return

	# 4. RAW KEYBOARD FALLBACK
	if event is InputEventKey:
		emulator.send_key(OS.get_keycode_string(event.keycode), event.pressed)
		return

	# 5. KEMPSTON MOUSE SUPPORT
	if event is InputEventMouseMotion:
		var display_scale = display.size.x / 256.0
		if display_scale > 0:
			mouse_accumulation += event.relative / display_scale
			var delta_x = int(mouse_accumulation.x)
			var delta_y = int(mouse_accumulation.y)
			if delta_x != 0 or delta_y != 0:
				emulator.send_mouse_move(delta_x, delta_y)
				mouse_accumulation.x -= delta_x
				mouse_accumulation.y -= delta_y
	
	if event is InputEventMouseButton:
		if event.pressed and not emulator.is_paused():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		var btn = -1
		match event.button_index:
			MOUSE_BUTTON_LEFT: btn = 0
			MOUSE_BUTTON_RIGHT: btn = 1
			MOUSE_BUTTON_MIDDLE: btn = 2
		if btn != -1:
			emulator.send_mouse_button(btn, event.pressed)

func _on_reset_requested():
	print("Standalone: Performing Reset...")
	_load_standalone_game()
	_toggle_pause()

func _on_quit_requested():
	get_tree().quit()
