class_name SettingsMenu
extends CanvasLayer

signal closed
var sliders: Dictionary[String, HSlider] = {}
var readouts: Dictionary[String, Label] = {}
var fullscreen: CheckButton
var options: Dictionary[String, OptionButton] = {}
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
	panel.anchor_left = 0.24
	panel.anchor_right = 0.76
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
	var body_style := StyleBoxEmpty.new()
	body_style.content_margin_top = 24
	body_style.content_margin_left = 8
	body_style.content_margin_right = 8
	tabs.add_theme_stylebox_override("panel", body_style)
	for state: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tab_style := StyleBoxFlat.new()
		tab_style.bg_color = Color("294a4c") if state == "tab_selected" else Color("152b32")
		tab_style.content_margin_left = 22
		tab_style.content_margin_right = 22
		tab_style.content_margin_top = 10
		tab_style.content_margin_bottom = 10
		tab_style.border_width_bottom = 2 if state == "tab_selected" else 0
		tab_style.border_color = Color("83b7a9")
		tabs.add_theme_stylebox_override(state, tab_style)
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
	fullscreen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fullscreen.custom_minimum_size.y = 40
	fullscreen.add_theme_constant_override("h_separation", 20)
	fullscreen.toggled.connect(func(enabled: bool) -> void:
		PlayerSettings.instance().set_value("fullscreen", enabled)
		_refresh_display_options())
	display.add_child(fullscreen)
	var resolutions: Array[String] = []
	for size: Vector2i in PlayerSettings.RESOLUTIONS:
		resolutions.append("%d × %d" % [size.x, size.y])
	_option(display, "resolution", "창 해상도", resolutions)
	_option(display, "antialiasing", "안티앨리어싱", ["끄기", "MSAA 2×", "MSAA 4×", "MSAA 8×"])
	_option(display, "frame_limit", "최대 프레임", ["제한 없음", "30 FPS", "60 FPS", "120 FPS", "144 FPS"])
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

func _option(parent: VBoxContainer, key: String, caption: String, items: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 160
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(230, 44)
	for item: String in items:
		option.add_item(item)
	option.item_selected.connect(func(index: int) -> void: PlayerSettings.instance().set_value(key, index))
	row.add_child(option)
	options[key] = option

func _refresh_display_options() -> void:
	for key: String in options:
		options[key].select(int(PlayerSettings.instance().values[key]))
	var resolution := options["resolution"]
	resolution.disabled = OS.has_feature("web") or fullscreen.button_pressed
	resolution.tooltip_text = "브라우저 창 크기에 맞춤" if OS.has_feature("web") else "전체 화면에서는 모니터 해상도를 사용합니다" if fullscreen.button_pressed else ""
	if OS.has_feature("web"):
		resolution.set_item_text(resolution.selected, "브라우저 크기에 맞춤")

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
	_refresh_display_options()

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
