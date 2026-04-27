@tool
extends Control

# ==============================================================================
# Standalone 48K Emulator Controller
# ------------------------------------------------------------------------------
# Designed for exported "Single Game" versions of the 48K model.
# ==============================================================================

@onready var emulator: ZXEmulator48K = $ZXEmulator48K
@onready var display: TextureRect = $Display
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var menu: CanvasLayer = $GameMenu

@export_category("Standalone Configuration")
## The specific Spectrum game file (.tap) to load.
@export_file("*.tap") var game_path: String = ""

@export var web_autoload: bool = false:
    set(value):
        web_autoload = value
        if web_autoload:
            game_path = ""
            print("[Standalone] Web Autoload enabled.")
        notify_property_list_changed()

@export_file("*.rom") var custom_rom_path: String = ""

var zx_actions: Array[StringName] = []
var audio_playback: AudioStreamGeneratorPlayback
var audio_buffer: PackedVector2Array = []

# Minimum safety buffer size at 44100Hz to prevent audio stuttering (underruns)
const MIN_BUFFER_FRAMES = 4096 

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
    
    print("[Standalone] Starting 48K Standalone Mode...")
    if audio_player:
        var gen = AudioStreamGenerator.new()
        gen.mix_rate = 44100.0
        gen.buffer_length = 0.5 # 500ms - Perfeito para estabilidade Android
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
    
    if menu.has_node("%LauncherButton"):
        menu.get_node("%LauncherButton").hide()
    
    var game_name = game_path.get_file()
    if game_name == "": game_name = "Standalone Game"
    menu.set_status("Machine: 48K | Game: " + game_name)
    
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    
    if web_autoload and OS.has_feature("web") and game_path == "":
        _try_web_autoload()
    else:
        _load_standalone_game()
        
    if DisplayServer.is_touchscreen_available():
        if has_node("VirtualControls"): $VirtualControls.show()
        if has_node("FireButton"): $FireButton.show()


func _load_standalone_game():
    _load_standalone_roms()
    if game_path != "" and FileAccess.file_exists(game_path):
        var ext = game_path.get_extension().to_lower()
        var data = FileAccess.get_file_as_bytes(game_path)
        
        if ext == "tap":
            print("[Standalone] Loading TAP file: ", game_path)
            emulator.load_tape(data)
            emulator.start_tape_load()
        else:
            push_error("[Standalone] Error: Only .tap files are supported.")


func _load_standalone_roms():
    if custom_rom_path != "" and FileAccess.file_exists(custom_rom_path):
        emulator.load_rom(FileAccess.get_file_as_bytes(custom_rom_path))


func _try_web_autoload():
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_autoload_completed)
    
    var url = "autoload.tap"
    if OS.has_feature("web"):
        var base_url = JavaScriptBridge.eval("window.location.href.substring(0, window.location.href.lastIndexOf('/'))")
        if base_url: url = base_url + "/autoload.tap"
            
    http.request(url)


func _on_autoload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
        _load_standalone_roms()
        emulator.load_tape(body)
        emulator.start_tape_load()
    else:
        _load_standalone_game()


# ARCHITECTURE NOTE: All audio and inputs are processed here in _process (60 FPS)
# for maximum responsiveness and to stay in sync with the visual frame rate.
func _process(_delta):
    if Engine.is_editor_hint(): return
    if emulator.is_paused(): return
    
    var tex = emulator.get_texture()
    if tex: display.texture = tex
    
    # Unified Audio Processing: Fetches samples from the Rust core and pushes to Godot
    if audio_playback:
        _update_audio()
    
    # Handle Dynamic Virtual Actions (zx_*)
    for action in zx_actions:
        if Input.is_action_just_pressed(action):
            emulator.send_key(action.substr(3).to_lower(), true)
        elif Input.is_action_just_released(action):
            emulator.send_key(action.substr(3).to_lower(), false)
            
    # Handle Arrow Keys / D-pad Input
    if Input.is_action_just_pressed("arrow_up"): emulator.send_key(key_up.to_lower(), true); _send_joy("UP", true)
    if Input.is_action_just_released("arrow_up"): emulator.send_key(key_up.to_lower(), false); _send_joy("UP", false)
    
    if Input.is_action_just_pressed("arrow_down"): emulator.send_key(key_down.to_lower(), true); _send_joy("DOWN", true)
    if Input.is_action_just_released("arrow_down"): emulator.send_key(key_down.to_lower(), false); _send_joy("DOWN", false)
    
    if Input.is_action_just_pressed("arrow_left"): emulator.send_key(key_left.to_lower(), true); _send_joy("LEFT", true)
    if Input.is_action_just_released("arrow_left"): emulator.send_key(key_left.to_lower(), false); _send_joy("LEFT", false)
    
    if Input.is_action_just_pressed("arrow_right"): emulator.send_key(key_right.to_lower(), true); _send_joy("RIGHT", true)
    if Input.is_action_just_released("arrow_right"): emulator.send_key(key_right.to_lower(), false); _send_joy("RIGHT", false)
    
    if Input.is_action_just_pressed("arrow_fire"): emulator.send_key(key_fire.to_lower(), true); _send_joy("FIRE", true)
    if Input.is_action_just_released("arrow_fire"): emulator.send_key(key_fire.to_lower(), false); _send_joy("FIRE", false)
    
    if Input.is_action_just_pressed("zx_fire"): _send_joy("FIRE", true)
    if Input.is_action_just_released("zx_fire"): _send_joy("FIRE", false)


# NOTE: _physics_process was intentionally removed. Handling emulation in the 
# physics step caused audio jitter and synchronization issues.


func _update_audio():
    # 1. Fetch ALL pending samples from the emulator and apply filtering
    var raw = emulator.get_audio_samples()
    if raw.size() > 0:
        var num_frames = raw.size() / 2
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
    if game_path == "": return "user://saves/standalone_48k.sna"
    var safe_name = game_path.replace("res://", "").replace("/", "_").replace(":", "_").replace(".", "_")
    return "user://saves/" + safe_name + "_48k.sna"


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


func _input(event):
    if event.is_action_pressed("ui_cancel"):
        _toggle_pause()
        get_viewport().set_input_as_handled()
        return
    
    if emulator.is_paused(): return
    
    if event is InputEventKey and not event.is_echo():
        var key_name = OS.get_keycode_string(event.keycode)
        emulator.send_key(key_name.to_lower(), event.pressed)


func _on_reset_requested():
    _load_standalone_game()
    _toggle_pause()


func _on_quit_requested():
    get_tree().quit()