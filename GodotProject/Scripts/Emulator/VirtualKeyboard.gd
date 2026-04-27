extends Control

# Signal emitted when a virtual key is interacted with
signal zx_key_event(key_name: String, pressed: bool)

@onready var keyboard_panel = $KeyboardPanel
@onready var toggle_button = $ToggleButton
@onready var grid = %KeyGrid

const KEYS_09 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
const KEYS_Q_P = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
const KEYS_A_L = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
const KEYS_Z_M = ["z", "x", "c", "v", "b", "n", "m"]

func _ready():
	keyboard_panel.hide()
	toggle_button.pressed.connect(_on_toggle_pressed)
	
	# Create the keys dynamically
	_create_row(KEYS_09)
	_create_row(KEYS_Q_P)
	_create_row(KEYS_A_L)
	_create_row(KEYS_Z_M)
	
	# Add some special keys for usability
	_create_key("space", "SPACE", 2)
	_create_key("enter", "ENTER", 1.5)

func _create_row(keys: Array):
	for k in keys:
		_create_key(k, k.to_upper())

func _create_key(key_id: String, label: String, stretch: float = 1.0):
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(55 * stretch, 55)
	btn.add_theme_font_size_override("font_size", 24)
	btn.focus_mode = Control.FOCUS_NONE # Prevent stealing focus from emulator
	
	# We use gui_input to detect press and release
	btn.button_down.connect(_on_key_event.bind(key_id, true))
	btn.button_up.connect(_on_key_event.bind(key_id, false))
	
	grid.add_child(btn)

func _on_toggle_pressed():
	keyboard_panel.visible = not keyboard_panel.visible
	if keyboard_panel.visible:
		toggle_button.text = "Close KB"
	else:
		toggle_button.text = "Keyboard"

func _on_key_event(key_id: String, pressed: bool):
	zx_key_event.emit(key_id, pressed)
