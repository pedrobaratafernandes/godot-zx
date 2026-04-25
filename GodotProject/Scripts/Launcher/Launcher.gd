extends Control

# The Launcher is the first scene the user sees.
# It allows selecting a game from the 'res://games/' folder and choosing the machine model.

@onready var btn_48k = %Btn48K
@onready var btn_128k = %Btn128K
@onready var game_list = %GameList

var games_dir = "res://games/"
# Internal list to store actual filenames corresponding to list items.
var game_files: Array[String] = []

@export_category("Configuration")
## The 48K ROM file (Leave empty to use built-in Sinclair ROM).
@export_file("*.rom") var rom_48k_path: String = ""

## The 128K ROM file (32KB combined).
@export_file("*.rom") var rom_128k_path: String = ""

## Separate 128K ROM - Bank 0 (16KB).
@export_file("*.rom") var rom_128_0_path: String = ""

## Separate 128K ROM - Bank 1 (16KB).
@export_file("*.rom") var rom_128_1_path: String = ""

func _ready():
	# 1. Connect Button and List signals
	btn_48k.pressed.connect(_on_48k_pressed)
	btn_128k.pressed.connect(_on_128k_pressed)
	game_list.item_selected.connect(_on_game_selected)
	
	# 2. Add visual feedback for UI focus (making it feel premium)
	for btn in [btn_48k, btn_128k]:
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		btn.mouse_exited.connect(_on_button_unhover.bind(btn))
		btn.focus_entered.connect(_on_button_hover.bind(btn))
		btn.focus_exited.connect(_on_button_unhover.bind(btn))
		btn.pressed.connect(_on_button_pressed.bind(btn))
	
	# 3. Scan the games directory for .tap, .sna, and .z80 files
	_scan_games()
	
	# 4. Set initial focus for keyboard/controller navigation
	if game_list.item_count > 0:
		game_list.select(0)
		_on_game_selected(0)
		# Set up focus neighbors for easy D-pad/Arrow navigation
		game_list.focus_next = btn_48k.get_path()
		btn_48k.focus_neighbor_left = game_list.get_path()
		btn_128k.focus_neighbor_left = game_list.get_path()
		
		game_list.grab_focus()
	else:
		btn_48k.grab_focus()
	
	# 5. Simple fade-in effect
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)

func _scan_games():
	# Clears existing items before scanning
	game_list.clear()
	game_files.clear()
	
	if not DirAccess.dir_exists_absolute(games_dir):
		DirAccess.make_dir_absolute(games_dir)
	
	var dir = DirAccess.open(games_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var ext = file_name.get_extension().to_lower()
				# We support Tapes (.tap) and Snapshots (.sna, .szx, .z80) and Screenshots (.scr)
				if ext in ["tap", "sna", "z80"]:
					game_files.append(file_name)
					game_list.add_item(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	if game_list.item_count == 0:
		game_list.add_item("No games found in res://games/")

func _on_game_selected(index):
	# Update the global Config with the selected game's path
	if index < game_files.size():
		var file_path = games_dir + game_files[index]
		Config.selected_game_path = file_path
		print("Selected game: ", Config.selected_game_path)
		
		# Update Preview
		_update_preview(file_path)

func _update_preview(file_path: String):
	var preview_node = %GamePreview
	if not preview_node: return
	
	# 1. Try to find a standard image file first (.png, .jpg, .jpeg)
	var base_path = file_path.get_basename()
	var img_extensions = ["png", "jpg", "jpeg", "PNG", "JPG", "JPEG"]
	
	for ext in img_extensions:
		var img_path = base_path + "." + ext
		if FileAccess.file_exists(img_path):
			var img = Image.load_from_file(img_path)
			if img:
				preview_node.texture = ImageTexture.create_from_image(img)
				return

	# 2. Fallback to .scr file (Spectrum format)
	var scr_path = ""
	if file_path.get_extension().to_lower() == "scr":
		scr_path = file_path
	else:
		if FileAccess.file_exists(base_path + ".scr"):
			scr_path = base_path + ".scr"
		elif FileAccess.file_exists(base_path + ".SCR"):
			scr_path = base_path + ".SCR"
	
	if scr_path != "" and FileAccess.file_exists(scr_path):
		var data = FileAccess.get_file_as_bytes(scr_path)
		if data.size() >= 6912:
			var tex = _load_scr_to_texture(data)
			preview_node.texture = tex
			return
	
	# If no preview found, show a default icon or clear
	preview_node.texture = null

func _load_scr_to_texture(data: PackedByteArray) -> ImageTexture:
	var image = Image.create(256, 192, false, Image.FORMAT_RGB8)
	
	var colors = [
		Color8(0, 0, 0), Color8(0, 0, 205), Color8(205, 0, 0), Color8(205, 0, 205),
		Color8(0, 205, 0), Color8(0, 205, 205), Color8(205, 205, 0), Color8(205, 205, 205),
		Color8(0, 0, 0), Color8(0, 0, 255), Color8(255, 0, 0), Color8(255, 0, 255),
		Color8(0, 255, 0), Color8(0, 255, 255), Color8(255, 255, 0), Color8(255, 255, 255)
	]
	
	for y in range(192):
		for x in range(32): # 32 columns of 8 pixels
			# Spectrum memory layout for screen:
			# y7 y6 y2 y1 y0 y5 y4 y3 x4 x3 x2 x1 x0
			var addr = ((y & 0xC0) << 5) | ((y & 0x07) << 8) | ((y & 0x38) << 2) | x
			var byte = data[addr]
			
			# Attributes are at data[6144 + (y/8)*32 + x]
			var attr_addr = 6144 + (int(y / 8) * 32) + x
			var attr = data[attr_addr]
			
			var ink = attr & 0x07
			var paper = (attr >> 3) & 0x07
			var bright = (attr >> 6) & 0x01
			
			if bright:
				ink += 8
				paper += 8
			
			for bit in range(8):
				var pixel_on = (byte >> (7 - bit)) & 0x01
				var color = colors[ink] if pixel_on else colors[paper]
				image.set_pixel(x * 8 + bit, y, color)
	
	return ImageTexture.create_from_image(image)

func _on_button_pressed(btn: Button):
	_stop_pulse(btn)
	btn.pivot_offset = btn.size / 2
	
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.2, 0.8), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2(0.9, 1.1), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	if btn.is_hovered() or btn.has_focus():
		_start_pulse(btn)

func _on_button_hover(btn: Button):
	btn.grab_focus()
	_start_pulse(btn)

func _on_button_unhover(btn: Button):
	_stop_pulse(btn)
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)

func _start_pulse(btn: Button):
	if btn.has_meta("pulse_tween"):
		return
	btn.pivot_offset = btn.size / 2
	
	var tween = create_tween().set_loops()
	tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	btn.set_meta("pulse_tween", tween)

func _stop_pulse(btn: Button):
	if btn.has_meta("pulse_tween"):
		var old_tween = btn.get_meta("pulse_tween")
		if old_tween: old_tween.kill()
		btn.remove_meta("pulse_tween")

func _on_48k_pressed():
	await get_tree().create_timer(0.3).timeout
	# Update ROM path in config (empty means use internal)
	Config.ROM_48K = rom_48k_path
	
	# Switch to 48K Emulator scene
	get_tree().change_scene_to_file("res://Scenes/Emulator/Main48K.tscn")

func _on_128k_pressed():
	await get_tree().create_timer(0.3).timeout
	# Update ROM paths in config if specified
	if rom_128k_path != "":
		Config.ROM_128K = rom_128k_path
	if rom_128_0_path != "":
		Config.ROM_128_0 = rom_128_0_path
	if rom_128_1_path != "":
		Config.ROM_128_1 = rom_128_1_path
	
	# Switch to 128K Emulator scene
	get_tree().change_scene_to_file("res://Scenes/Emulator/Main128K.tscn")

