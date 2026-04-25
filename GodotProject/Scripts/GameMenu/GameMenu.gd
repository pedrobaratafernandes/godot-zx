extends CanvasLayer

# This script handles the Pause Menu that appears when the user presses ESC.
# It doesn't perform logic itself; instead, it emits signals that the Main emulator scenes handle.

signal volume_changed(value: float)
signal save_requested
signal load_requested
signal launcher_requested
signal resume_requested
signal reset_requested
signal quit_requested
signal fullscreen_requested

@onready var volume_slider = %VolumeSlider
@onready var save_button = %SaveButton
@onready var load_button = %LoadButton
@onready var launcher_button = %LauncherButton
@onready var quit_button = %QuitButton
@onready var resume_button = %ResumeButton
@onready var reset_button = %ResetButton
@onready var fullscreen_button = %FullscreenButton
@onready var status_label = %StatusLabel


func _ready():
	hide()
	volume_slider.value_changed.connect(_on_volume_changed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	launcher_button.pressed.connect(_on_launcher_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	
	if fullscreen_button:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	
	# Web adjustments
	if OS.has_feature("web"):
		quit_button.hide()
		
	visibility_changed.connect(_on_visibility_changed)
	_setup_button_animations()

func _setup_button_animations():
	var buttons = [save_button, load_button, reset_button, launcher_button, quit_button, fullscreen_button, resume_button, screenshot_button]
	for btn in buttons:
		if btn:
			btn.mouse_entered.connect(_on_button_hover.bind(btn))
			btn.mouse_exited.connect(_on_button_unhover.bind(btn))
			btn.focus_entered.connect(_on_button_hover.bind(btn))
			btn.focus_exited.connect(_on_button_unhover.bind(btn))
			btn.pressed.connect(_on_button_pressed.bind(btn))

func _on_button_pressed(btn: Button):
	_stop_pulse(btn)
	btn.pivot_offset = btn.size / 2
	
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.2, 0.8), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2(0.9, 1.1), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	# Resume pulse if still focused or hovered
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
	# If already pulsing, don't restart to avoid double-bounce effect
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

func _on_visibility_changed():
	if visible:
		# Wait a frame to ensure visibility is updated in the tree
		await get_tree().process_frame
		resume_button.grab_focus()

func set_status(text: String):
	status_label.text = text

func _on_volume_changed(value):
	volume_changed.emit(value)

func _on_save_pressed():
	await get_tree().create_timer(0.3).timeout
	save_requested.emit()

func _on_load_pressed():
	await get_tree().create_timer(0.3).timeout
	load_requested.emit()

func _on_launcher_pressed():
	await get_tree().create_timer(0.3).timeout
	launcher_requested.emit()

func _on_quit_pressed():
	await get_tree().create_timer(0.3).timeout
	quit_requested.emit()

func _on_resume_pressed():
	await get_tree().create_timer(0.2).timeout # Resume can be a bit faster
	resume_requested.emit()

func _on_reset_pressed():
	await get_tree().create_timer(0.3).timeout
	reset_requested.emit()

func _on_fullscreen_pressed():
	# Fullscreen doesn't need much delay as it stays on screen
	fullscreen_requested.emit()
