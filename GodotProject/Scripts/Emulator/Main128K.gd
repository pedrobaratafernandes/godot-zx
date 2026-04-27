extends Control

# ==============================================================================
# ZX Spectrum 128K Emulator Controller
# ==============================================================================

@onready var emulator: ZXEmulator128K = $ZXEmulator128K
@onready var display: TextureRect = $Display
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var menu: CanvasLayer = $GameMenu

var audio_playback: AudioStreamGeneratorPlayback
var audio_buffer: PackedVector2Array = []
var zx_actions: Array[StringName] = []
var mouse_accumulation: Vector2 = Vector2.ZERO

# Minimum safety buffer size at 44100Hz to prevent audio stuttering (underruns)
const MIN_BUFFER_FRAMES = 4096 

# DC Blocker filter state variables
var _last_raw_sample: Vector2 = Vector2.ZERO
var _filtered_sample: Vector2 = Vector2.ZERO

# Toggle for Arrow Mapping (Switched via Caps Lock)
var use_secondary_mapping: bool = false

@export_group("Primary Arrow Mapping (Default: QAOP)")
@export var key_up: String = "q"
@export var key_down: String = "a"
@export var key_left: String = "o"
@export var key_right: String = "p"
@export var key_fire: String = "space"

@export_group("Secondary Arrow Mapping (Default: 5678)")
@export var sec_up: String = "7"
@export var sec_down: String = "6"
@export var sec_left: String = "5"
@export var sec_right: String = "8"
@export var sec_fire: String = "0"

@export_group("Joystick Mapping")
@export var joystick_kempston: bool = false
@export var joystick_sinclair: bool = false
@export_range(1, 2) var sinclair_joy_num: int = 1

func _ready():
	print("[ZX] Initializing 128K Emulator...")
	if audio_player:
		audio_player.play()
		audio_playback = audio_player.get_stream_playback()
	
	for action in InputMap.get_actions():
		if action.begins_with("zx_"):
			zx_actions.append(action)
	
	menu.launcher_requested.connect(_on_launcher_requested)
	menu.save_requested.connect(_save_state)
	menu.load_requested.connect(_load_state)
	menu.reset_requested.connect(_on_reset_requested)
	menu.quit_requested.connect(_on_quit_requested)
	menu.fullscreen_requested.connect(_toggle_fullscreen)

	if has_node("VirtualKeyboard"):
		$VirtualKeyboard.zx_key_event.connect(func(key, pressed): emulator.send_key(key, pressed))
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	var game_name = Config.selected_game_path.get_file()
	if game_name == "": game_name = "None"
	menu.set_status("Machine: 128K | Game: " + game_name)
	
	_load_assets()
	
	if DisplayServer.is_touchscreen_available():
		if has_node("VirtualControls"): $VirtualControls.show()
		if has_node("FireButton"): $FireButton.show()
		if has_node("MenuButton"): $MenuButton.show()
		if has_node("VirtualKeyboard"): $VirtualKeyboard.show()
	

func _load_assets():
	var rom_data = Config.get_128k_rom_data()
	if rom_data.size() > 0:
		emulator.load_rom(rom_data)
	
	var game_path = Config.selected_game_path
	if game_path == "": return
		
	if FileAccess.file_exists(game_path):
		var ext = game_path.get_extension().to_lower()
		var data = FileAccess.get_file_as_bytes(game_path)
		match ext:
			"tap":
				emulator.load_tape(data)
				emulator.start_tape_load()
	else:
		push_error("Error: File not found: " + game_path)

func _process(_delta):
	if emulator.is_paused(): return
	var tex = emulator.get_texture()
	if tex: display.texture = tex
	# Unified Audio Processing: Fetches samples from the Rust core and pushes to Godot
	_update_audio()

func _update_audio():
	if not audio_playback: return

	# 1. Fetch ALL pending samples from the emulator and apply filtering
	var raw = emulator.get_audio_samples()
	if raw.size() > 0:
		var num_frames = raw.size() / 2.0
		var frames = PackedVector2Array()
		frames.resize(num_frames)
		for i in range(num_frames):
			var current_sample = Vector2(raw[i * 2], raw[i * 2 + 1])
			
			# DC Blocker Filter: Removes low-frequency noise and DC offset (prevents pops/clicks)
			_filtered_sample = current_sample - _last_raw_sample + (_filtered_sample * 0.995)
			_last_raw_sample = current_sample
			
			# Clamp to valid range and store
			frames[i] = _filtered_sample.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
		
		# Buffer the processed frames to ensure zero sample loss
		audio_buffer.append_array(frames)

	# 2. Check if Godot's audio playback has room for more data
	var frames_available = audio_playback.get_frames_available()
	if frames_available <= 0: return

	# 3. Safety Margin (Jitter Buffer):
	# Only start pushing data if we have enough buffered to handle timing variations
	if audio_buffer.size() < MIN_BUFFER_FRAMES:
		return

	# 4. Push samples to Godot's AudioStreamPlayer
	var to_push = min(audio_buffer.size(), frames_available)
	if to_push > 0:
		var chunk = audio_buffer.slice(0, to_push)
		audio_playback.push_buffer(chunk)
		audio_buffer = audio_buffer.slice(to_push)

	# 5. Latency Control:
	# If the buffer grows too large (e.g. system lag), trim it to keep audio in sync with video
	const MAX_LATENCY_FRAMES = 13230 # ~300ms
	if audio_buffer.size() > MAX_LATENCY_FRAMES:
		audio_buffer = audio_buffer.slice(audio_buffer.size() - MIN_BUFFER_FRAMES)

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

func _get_save_path() -> String:
	var game_path = Config.selected_game_path
	if game_path == "": return "user://saves/default_128k.sna"
	var safe_name = game_path.replace("res://", "").replace("/", "_").replace(":", "_").replace(".", "_")
	return "user://saves/" + safe_name + "_128k.sna"

func _save_state():
	if not DirAccess.dir_exists_absolute("user://saves"):
		DirAccess.make_dir_absolute("user://saves")
	var data = emulator.save_snapshot()
	if data.size() > 0:
		var path = _get_save_path()
		var file = FileAccess.open(_get_save_path(), FileAccess.WRITE)
		if file:
			file.store_buffer(data)

func _load_state():
	var path = _get_save_path()
	if FileAccess.file_exists(path):
		var data = FileAccess.get_file_as_bytes(path)
		if data.size() > 0:
			emulator.load_snapshot(data)
			_toggle_pause()

func _toggle_fullscreen():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _input(event: InputEvent):
	# 1. CAPS LOCK TOGGLE (Mapping Profile Switch)
	if event is InputEventKey and event.keycode == KEY_CAPSLOCK and event.pressed and not event.is_echo():
		use_secondary_mapping = not use_secondary_mapping
		var mode_name = "SECONDARY (6789)" if use_secondary_mapping else "PRIMARY (QAOP)"
		print("[ZX] Arrow Mapping switched to: ", mode_name)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if emulator.is_paused(): return

	# 2. ARROW MAPPING
	if event.is_action("arrow_up"):
		var target = sec_up if use_secondary_mapping else key_up
		var pressed = event.is_pressed()
		emulator.send_key(target.to_lower(), pressed)
		_send_joy("UP", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_down"):
		var target = sec_down if use_secondary_mapping else key_down
		var pressed = event.is_pressed()
		emulator.send_key(target.to_lower(), pressed)
		_send_joy("DOWN", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_left"):
		var target = sec_left if use_secondary_mapping else key_left
		var pressed = event.is_pressed()
		emulator.send_key(target.to_lower(), pressed)
		_send_joy("LEFT", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_right"):
		var target = sec_right if use_secondary_mapping else key_right
		var pressed = event.is_pressed()
		emulator.send_key(target.to_lower(), pressed)
		_send_joy("RIGHT", pressed)
		get_viewport().set_input_as_handled()
		return

	# 3. FIRE MAPPING
	if event.is_action("zx_fire") or event.is_action("arrow_fire"):
		var pressed = event.is_pressed()
		_send_joy("FIRE", pressed)
		if event.is_action("arrow_fire"):
			var target = sec_fire if use_secondary_mapping else key_fire
			emulator.send_key(target.to_lower(), pressed)
		get_viewport().set_input_as_handled()
		return

	# 4. DYNAMIC ACTIONS (zx_*)
	for action in zx_actions:
		if event.is_action(action):
			var zx_key_name = action.substr(3)
			emulator.send_key(zx_key_name.to_lower(), event.is_pressed())
			get_viewport().set_input_as_handled()
			return

	# 5. RAW KEYBOARD FALLBACK
	if event is InputEventKey and not event.is_echo():
		var key_name = OS.get_keycode_string(event.keycode)
		emulator.send_key(key_name.to_lower(), event.pressed)

func _on_launcher_requested():
	get_tree().change_scene_to_file("res://Scenes/Launcher/Launcher.tscn")

func _on_reset_requested():
	_load_assets()
	_toggle_pause()

func _on_quit_requested():
	get_tree().quit()
