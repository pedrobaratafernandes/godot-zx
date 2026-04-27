@tool
extends Control

# ==============================================================================
# Standalone 128K Emulator Controller
# ------------------------------------------------------------------------------
# Designed for exported "Single Game" versions of the 128K model.
# ==============================================================================

@onready var emulator: ZXEmulator128K = $ZXEmulator128K
@onready var display: TextureRect = $Display
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var menu: CanvasLayer = $GameMenu

@export_category("Standalone Configuration")
## The specific Spectrum 128K game file (.tap) to load.
@export_file("*.tap") var game_path: String = ""

@export var web_autoload: bool = false:
	set(value):
		web_autoload = value
		if web_autoload:
			game_path = ""
			print("[Standalone] Web Autoload enabled.")
		notify_property_list_changed()

@export_file("*.rom") var rom_128k_path: String = "res://roms/128.rom"
@export_file("*.rom") var rom_128_0_path: String = ""
@export_file("*.rom") var rom_128_1_path: String = ""

var zx_actions: Array[StringName] = []
var audio_playback: AudioStreamGeneratorPlayback
var audio_buffer: PackedVector2Array = []
var mouse_accumulation: Vector2 = Vector2.ZERO

# Safety buffer size (in frames) to prevent audio stuttering (underruns)
var min_buffer_frames = 2048

# DC Blocker filter state variables
var _last_raw_sample: Vector2 = Vector2.ZERO
var _filtered_sample: Vector2 = Vector2.ZERO

@export_group("Spectrum Arrow Mapping")
@export var key_up: String = "q"
@export var key_down: String = "a"
@export var key_left: String = "o"
@export var key_right: String = "p"
@export var key_fire: String = "space"

@export_group("Joystick Mapping")
@export var joystick_kempston: bool = false
@export var joystick_sinclair: bool = false
@export_range(1, 2) var sinclair_joy_num: int = 1

func _ready():
	if Engine.is_editor_hint(): return
	
	print("[Standalone] Starting 128K Standalone Mode...")
	if audio_player:
		# Platform-specific buffer tuning
		if OS.has_feature("mobile"):
			min_buffer_frames = 4096  # ~93ms (Safe for Android/iOS)
		elif OS.has_feature("web"):
			min_buffer_frames = 2048  # ~46ms (Browser stability)
		else:
			min_buffer_frames = 1024  # ~23ms (Low latency for Desktop)

		var gen = AudioStreamGenerator.new()
		gen.mix_rate = 44100.0
		gen.buffer_length = 0.3 if not OS.has_feature("mobile") else 0.5
		audio_player.stream = gen
		audio_player.play()
		audio_playback = audio_player.get_stream_playback()
	
	for action in InputMap.get_actions():
		if action.begins_with("zx_"):
			zx_actions.append(action)
	
	menu.resume_requested.connect(_toggle_pause)
	menu.save_requested.connect(_save_state)
	menu.load_requested.connect(_load_state)
	menu.reset_requested.connect(_on_reset_requested)
	menu.quit_requested.connect(_on_quit_requested)
	menu.fullscreen_requested.connect(_toggle_fullscreen)

	if has_node("VirtualKeyboard"):
		$VirtualKeyboard.zx_key_event.connect(func(key, pressed): emulator.send_key(key, pressed))
	
	if menu.has_node("%LauncherButton"):
		menu.get_node("%LauncherButton").hide()
	
	var game_name = game_path.get_file()
	if game_name == "": game_name = "Standalone Game"
	menu.set_status("Machine: 128K | Game: " + game_name)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if web_autoload and OS.has_feature("web") and game_path == "":
		_try_web_autoload()
	else:
		_load_standalone_game()
	
	if DisplayServer.is_touchscreen_available():
		if has_node("VirtualControls"): $VirtualControls.show()
		if has_node("FireButton"): $FireButton.show()
		if has_node("MenuButton"): $MenuButton.show()
		if has_node("VirtualKeyboard"): $VirtualKeyboard.show()
		

func _load_standalone_game():
	_load_standalone_roms()
	
	if game_path != "" and FileAccess.file_exists(game_path):
		var ext = game_path.get_extension().to_lower()
		var data = FileAccess.get_file_as_bytes(game_path)
		
		if ext == "tap":
			print("[Standalone] Loading 128K TAP file: ", game_path)
			emulator.load_tape(data)
			emulator.start_tape_load()
		else:
			push_error("[Standalone] Error: Only .tap files are supported. Found: ." + ext)
	else:
		print("[Standalone] Waiting for .tap file load.")

func _load_standalone_roms():
	var rom_data: PackedByteArray
	if rom_128_0_path != "" and rom_128_1_path != "" and FileAccess.file_exists(rom_128_0_path) and FileAccess.file_exists(rom_128_1_path):
		rom_data.append_array(FileAccess.get_file_as_bytes(rom_128_0_path))
		rom_data.append_array(FileAccess.get_file_as_bytes(rom_128_1_path))
	elif rom_128k_path != "" and FileAccess.file_exists(rom_128k_path):
		rom_data = FileAccess.get_file_as_bytes(rom_128k_path)
	
	if rom_data.size() == 0:
		rom_data = Config.get_128k_rom_data()
	
	if rom_data.size() > 0:
		emulator.load_rom(rom_data)

func _try_web_autoload():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_autoload_completed)
	
	var url = "autoload.tap"
	if OS.has_feature("web"):
		var base_url = JavaScriptBridge.eval("window.location.href.substring(0, window.location.href.lastIndexOf('/'))")
		if base_url: url = base_url + "/autoload.tap"
			
	print("[Standalone] Web: Attempting autoload from: ", url)
	http.request(url)

func _on_autoload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
		print("[Standalone] Web Success: autoload.tap loaded.")
		_load_standalone_roms()
		emulator.load_tape(body)
		emulator.start_tape_load()
	else:
		_load_standalone_game()

func _process(_delta):
	if Engine.is_editor_hint(): return
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
	if audio_buffer.size() < min_buffer_frames:
		return

	# 4. Push samples to Godot's AudioStreamPlayer
	var to_push = min(audio_buffer.size(), frames_available)
	if to_push > 0:
		var chunk = audio_buffer.slice(0, to_push)
		audio_playback.push_buffer(chunk)
		audio_buffer = audio_buffer.slice(to_push)

	# 5. Latency Control:
	# Trims the buffer if it grows too large to keep audio in sync with video
	var max_latency = min_buffer_frames * 3
	if audio_buffer.size() > max_latency:
		audio_buffer = audio_buffer.slice(audio_buffer.size() - min_buffer_frames)

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
	if game_path == "": return "user://saves/standalone_128k.sna"
	var safe_name = game_path.replace("res://", "").replace("/", "_").replace(":", "_").replace(".", "_")
	return "user://saves/" + safe_name + "_128k.sna"

func _save_state():
	if not DirAccess.dir_exists_absolute("user://saves"):
		DirAccess.make_dir_absolute("user://saves")
	var data = emulator.save_snapshot()
	if data.size() > 0:
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
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	
	if emulator.is_paused(): return
	
	# 1. SINGLE ARROW MAPPING
	if event.is_action("arrow_up"):
		var pressed = event.is_pressed()
		emulator.send_key(key_up.to_lower(), pressed)
		_send_joy("UP", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_down"):
		var pressed = event.is_pressed()
		emulator.send_key(key_down.to_lower(), pressed)
		_send_joy("DOWN", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_left"):
		var pressed = event.is_pressed()
		emulator.send_key(key_left.to_lower(), pressed)
		_send_joy("LEFT", pressed)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("arrow_right"):
		var pressed = event.is_pressed()
		emulator.send_key(key_right.to_lower(), pressed)
		_send_joy("RIGHT", pressed)
		get_viewport().set_input_as_handled()
		return

	# 2. FIRE MAPPING
	if event.is_action("zx_fire") or event.is_action("arrow_fire"):
		var pressed = event.is_pressed()
		_send_joy("FIRE", pressed)
		if event.is_action("arrow_fire"):
			emulator.send_key(key_fire.to_lower(), pressed)
		get_viewport().set_input_as_handled()
		return

	# 3. DYNAMIC ACTIONS (zx_*)
	for action in zx_actions:
		if event.is_action(action):
			var zx_key_name = action.substr(3)
			emulator.send_key(zx_key_name.to_lower(), event.is_pressed())
			get_viewport().set_input_as_handled()
			return
	
	# 4. RAW KEYBOARD FALLBACK
	if event is InputEventKey and not event.is_echo():
		var key_name = OS.get_keycode_string(event.keycode)
		emulator.send_key(key_name.to_lower(), event.pressed)

func _on_reset_requested():
	_load_standalone_game()
	_toggle_pause()

func _on_quit_requested():
	get_tree().quit()
