class_name SettingsMenu
extends CanvasLayer

signal closed
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}
var fullscreen: CheckButton
var feedback: Label
var close_button: Button
var tabs: TabContainer
var previous_focus: Control

func _ready() -> void:
	layer = 110
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.88)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	dim.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.2
	panel.anchor_right = 0.8
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101f25")
	style.border_color = Color("527d79")
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	tabs = TabContainer.new()
	tabs.tab_changed.connect(func(_index: int) -> void: _trap_focus.call_deferred())
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var audio := _tab(tabs, "사운드")
	var labels := {"master": "전체", "missile": "미사일", "gun": "기관포", "explosion": "폭발", "alert": "경보 · 접촉", "ui": "UI"}
	for key: String in labels:
		_slider(audio, key, labels[key], true)
	var controls := _tab(tabs, "조작")
	_slider(controls, "pan", "카메라 이동", false)
	_slider(controls, "rotation", "카메라 회전", false)
	_slider(controls, "zoom", "카메라 줌", false)
	var display := _tab(tabs, "화면")
	fullscreen = CheckButton.new()
	fullscreen.text = "전체 화면"
	fullscreen.toggled.connect(func(enabled: bool) -> void: PlayerSettings.instance().set_value("fullscreen", enabled))
	display.add_child(fullscreen)
	feedback = Label.new()
	feedback.add_theme_color_override("font_color", Color("ffbd80"))
	column.add_child(feedback)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var reset := Button.new()
	reset.text = "기본값 복원"
	reset.custom_minimum_size.y = 44
	reset.pressed.connect(func() -> void: PlayerSettings.instance().reset_defaults(); refresh())
	actions.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	close_button = Button.new()
	close_button.text = "닫기"
	close_button.custom_minimum_size = Vector2(120, 44)
	close_button.pressed.connect(close)
	actions.add_child(close_button)
	for button: Button in [reset, close_button]:
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var button_style := StyleBoxFlat.new()
			button_style.bg_color = Color("294a4c") if state != "normal" else Color("1c333b")
			button_style.set_content_margin_all(12)
			button_style.border_color = Color("86bcb0")
			button_style.border_width_bottom = 1
			button.add_theme_stylebox_override(state, button_style)
	visible = false

func _tab(tabs: TabContainer, caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	return column

func _slider(parent: VBoxContainer, key: String, caption: String, audio: bool) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var heading := HBoxContainer.new()
	row.add_child(heading)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var readout := Label.new()
	heading.add_child(readout)
	readouts[key] = readout
	var slider := HSlider.new()
	slider.min_value = 0 if audio else 25
	slider.max_value = 100 if audio else 200
	slider.step = 1 if audio else 5
	slider.custom_minimum_size.y = 26
	var track := StyleBoxFlat.new()
	track.bg_color = Color("29434b")
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("83b7a9")
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(func(value: float) -> void:
		PlayerSettings.instance().set_value(key, value / 100.0)
		readout.text = "%d%%" % roundi(value))
	row.add_child(slider)
	sliders[key] = slider

func refresh() -> void:
	for key: String in sliders:
		var value := float(PlayerSettings.instance().values[key]) * 100.0
		sliders[key].set_value_no_signal(value)
		readouts[key].text = "%d%%" % roundi(value)
	fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])

func open() -> void:
	previous_focus = get_viewport().gui_get_focus_owner()
	refresh()
	feedback.text = ""
	visible = true
	tabs.current_tab = 0
	_trap_focus()
	sliders["master"].grab_focus()

func _trap_focus() -> void:
	var controls: Array[Control] = []
	for node: Node in find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL:
			controls.append(control)
	for index: int in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])

func close() -> void:
	if DisplayServer.get_name() != "headless":
		PlayerSettings.instance().values.fullscreen = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if PlayerSettings.instance().save_preferences() != OK:
		feedback.text = "설정을 저장하지 못했습니다"
		return
	visible = false
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()
	closed.emit()
