class_name OperationBriefingPanel
extends Control
## Modal intelligence card for sustained-operation phases, also used as the briefing archive.

signal closed(archive: bool)
signal deploy_requested(defense_ids: Array[StringName])

const CARD_WIDTH := 880.0
const THREAT_COLOR := Color(1.0, 0.56, 0.36)
const ASSET_COLOR := Color(0.52, 0.92, 0.64)
const ICON_SIZE := 30.0
## Tall enough for five two-line rows, so paging through the archive keeps the card still.
const COLUMN_MIN_HEIGHT := 330.0

var scenario: ScenarioDefinition
var briefings: Array[OperationBriefingDefinition] = []
var page_index: int = 0
var live: bool = false

var card: PanelContainer
var caption_label: Label
var title_label: Label
var level_label: Label
var intel_label: Label
var threat_list: VBoxContainer
var asset_list: VBoxContainer
var threat_timing_label: Label
var recommendation_label: Label
var previous_button: Button
var next_button: Button
var page_label: Label
var deploy_button: Button
var acknowledge_button: Button

func _ready() -> void:
	name = "OperationBriefingPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 95
	visible = false
	_build()

func configure(scenario_value: ScenarioDefinition) -> void:
	scenario = scenario_value

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_render_page()

## Opens on a newly delivered briefing with acknowledge and deploy actions.
func present_delivered(delivered: Array[OperationBriefingDefinition], briefing: OperationBriefingDefinition) -> void:
	live = true
	_open(delivered, maxi(0, delivered.find(briefing)))

## Opens the archive of delivered briefings on the latest one.
func present_archive(delivered: Array[OperationBriefingDefinition]) -> void:
	live = false
	_open(delivered, delivered.size() - 1)

func current_briefing() -> OperationBriefingDefinition:
	return briefings[page_index] if page_index >= 0 and page_index < briefings.size() else null

func close() -> void:
	if not visible:
		return
	visible = false
	var was_archive := not live
	live = false
	closed.emit(was_archive)

func show_page(index: int) -> void:
	page_index = clampi(index, 0, maxi(0, briefings.size() - 1))
	_render_page()

func _open(delivered: Array[OperationBriefingDefinition], index: int) -> void:
	briefings = delivered.duplicate()
	if briefings.is_empty():
		return
	visible = true
	show_page(index)
	modulate.a = 0.0
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.97, 0.97)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.28)
	tween.tween_property(card, "scale", Vector2.ONE, 0.32)
	acknowledge_button.grab_focus()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_left"):
		show_page(page_index - 1)
	elif event.is_action_pressed("ui_right"):
		show_page(page_index + 1)
	else:
		return
	get_viewport().set_input_as_handled()

func _render_page() -> void:
	var briefing := current_briefing()
	if briefing == null:
		return
	caption_label.text = tr("작전 첩보 · 국면 %d / %d") % [scenario.operation_briefings.find(briefing) + 1, scenario.operation_briefings.size()]
	title_label.text = tr(briefing.title)
	level_label.text = tr("위협 단계 %d") % briefing.unlock_level
	intel_label.text = KoreanLineBreak.keep_words(tr(briefing.intel))
	recommendation_label.text = KoreanLineBreak.keep_words(tr(briefing.recommendation))
	threat_timing_label.text = _threat_timing_text(briefing)
	_clear(threat_list)
	for definition: ThreatDefinition in scenario.briefing_threats(briefing):
		threat_list.add_child(_content_row(threat_icon(definition), tr(definition.display_name), KoreanLineBreak.keep_words(tr(definition.briefing_note)), "", THREAT_COLOR))
	_clear(asset_list)
	var assets := scenario.briefing_defenses(briefing)
	for definition: DefenseDefinition in assets:
		asset_list.add_child(_content_row(definition.identity_icon, tr(definition.display_name), KoreanLineBreak.keep_words(purchase_role(definition)), "$%d" % definition.price, Color.WHITE))
	if assets.is_empty():
		var empty := _muted_label(KoreanLineBreak.keep_words(tr("새 방공 자산은 없습니다. 기존 방공망의 배치와 교전 설정으로 대응하세요.")), 14)
		asset_list.add_child(empty)
	previous_button.disabled = page_index <= 0
	next_button.disabled = page_index >= briefings.size() - 1
	page_label.text = "%d / %d" % [page_index + 1, briefings.size()]
	for control: Control in [previous_button, next_button, page_label]:
		control.visible = briefings.size() > 1
	deploy_button.visible = live and not assets.is_empty()
	acknowledge_button.text = tr("확인", &"briefing") if live else tr("닫기")

## States when the phase's threats start flying so players know how long they have to prepare.
func _threat_timing_text(briefing: OperationBriefingDefinition) -> String:
	var first_flight := -1
	var phase_threats := scenario.briefing_threats(briefing)
	for entry: ThreatSpawnEntry in scenario.threat_entries:
		if phase_threats.has(entry.threat_definition):
			var flight := scenario.threat_flight_level(entry)
			first_flight = flight if first_flight < 0 else mini(first_flight, flight)
	if first_flight <= briefing.unlock_level:
		return tr("즉시 출격")
	return tr("%d단계부터 출격") % first_flight

static func threat_icon(definition: ThreatDefinition) -> Texture2D:
	var index := EngagementDoctrine.TARGET_KINDS.find(EngagementDoctrine.target_kind(definition.signature_class))
	return Hud.TARGET_ICONS[index if index >= 0 else 1]

## The first purchase-tooltip line is the asset's tactical role.
static func purchase_role(definition: DefenseDefinition) -> String:
	return TranslationServer.translate(definition.purchase_tooltip).get_slice("\n", 0)

func _on_deploy_pressed() -> void:
	var ids: Array[StringName] = []
	for definition: DefenseDefinition in scenario.briefing_defenses(current_briefing()):
		ids.append(definition.id)
	close()
	deploy_requested.emit(ids)

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.01, 0.015, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var style := MenuStyle.panel(MenuStyle.WARNING, 0.0)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	card.add_child(body)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	body.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	caption_label = Label.new()
	caption_label.name = "Caption"
	caption_label.add_theme_font_override("font", MenuStyle.tracked_font(2))
	caption_label.add_theme_font_size_override("font_size", 14)
	caption_label.add_theme_color_override("font_color", Color(MenuStyle.WARNING, 0.9))
	heading.add_child(caption_label)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", MenuStyle.TEXT)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	heading.add_child(title_label)
	level_label = Label.new()
	level_label.name = "Level"
	level_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", MenuStyle.WARNING)
	level_label.add_theme_stylebox_override("normal", MenuStyle.badge(MenuStyle.WARNING))
	header.add_child(level_label)

	intel_label = Label.new()
	intel_label.name = "Intel"
	intel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intel_label.custom_minimum_size = Vector2(CARD_WIDTH - 72.0, 0.0)
	intel_label.add_theme_font_size_override("font_size", 17)
	intel_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.88))
	intel_label.add_theme_constant_override("line_spacing", 5)
	intel_label.custom_minimum_size.y = 52.0
	body.add_child(intel_label)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.color = Color(MenuStyle.WARNING, 0.22)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	body.add_child(columns)
	threat_list = _column(columns, "ThreatColumn", "예상 위협", THREAT_COLOR)
	asset_list = _column(columns, "AssetColumn", "신규 방공 자산", ASSET_COLOR)
	threat_timing_label = _muted_label("", 13)
	threat_timing_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	threat_timing_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	threat_list.get_parent().get_node("Header").add_child(threat_timing_label)

	var advice := PanelContainer.new()
	advice.name = "Recommendation"
	var advice_style := StyleBoxFlat.new()
	advice_style.bg_color = Color(MenuStyle.ACCENT, 0.07)
	advice_style.border_color = Color(MenuStyle.ACCENT, 0.8)
	advice_style.border_width_left = 3
	advice_style.content_margin_left = 16
	advice_style.content_margin_right = 16
	advice_style.content_margin_top = 12
	advice_style.content_margin_bottom = 12
	advice.add_theme_stylebox_override("panel", advice_style)
	body.add_child(advice)
	var advice_body := VBoxContainer.new()
	advice_body.add_theme_constant_override("separation", 6)
	advice.add_child(advice_body)
	advice_body.add_child(_caption("권장 대응", MenuStyle.ACCENT))
	recommendation_label = Label.new()
	recommendation_label.name = "RecommendationText"
	recommendation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recommendation_label.custom_minimum_size = Vector2(CARD_WIDTH - 104.0, 0.0)
	recommendation_label.add_theme_font_size_override("font_size", 15)
	recommendation_label.add_theme_color_override("font_color", MenuStyle.TEXT)
	recommendation_label.add_theme_constant_override("line_spacing", 4)
	recommendation_label.custom_minimum_size.y = 46.0
	advice_body.add_child(recommendation_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	body.add_child(footer)
	previous_button = _footer_button("PreviousButton", "◀", false, true)
	previous_button.pressed.connect(func() -> void: show_page(page_index - 1))
	footer.add_child(previous_button)
	page_label = _muted_label("", 14)
	page_label.custom_minimum_size = Vector2(56.0, 0.0)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(page_label)
	next_button = _footer_button("NextButton", "▶", false, true)
	next_button.pressed.connect(func() -> void: show_page(page_index + 1))
	footer.add_child(next_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	deploy_button = _footer_button("DeployButton", "방공 자산 열기", false)
	deploy_button.pressed.connect(_on_deploy_pressed)
	footer.add_child(deploy_button)
	acknowledge_button = _footer_button("AcknowledgeButton", "", true)
	acknowledge_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	acknowledge_button.custom_minimum_size = Vector2(150.0, 0.0)
	acknowledge_button.pressed.connect(close)
	footer.add_child(acknowledge_button)

func _column(parent: HBoxContainer, node_name: String, heading: String, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2((CARD_WIDTH - 72.0 - 14.0) * 0.5, COLUMN_MIN_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.03)
	style.border_color = Color(color, 0.7)
	style.border_width_top = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.name = "Header"
	body.add_child(header)
	var caption := _caption(heading, color)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 12)
	body.add_child(list)
	return list

func _content_row(icon: Texture2D, title: String, note: String, meta: String, icon_tint: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var image := TextureRect.new()
	image.texture = icon
	image.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	image.modulate = icon_tint
	row.add_child(image)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_row := HBoxContainer.new()
	text.add_child(name_row)
	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", MenuStyle.TEXT)
	name_row.add_child(name_label)
	if not meta.is_empty():
		var meta_label := Label.new()
		meta_label.text = meta
		meta_label.add_theme_font_size_override("font_size", 14)
		meta_label.add_theme_color_override("font_color", ASSET_COLOR)
		name_row.add_child(meta_label)
	var note_label := _muted_label(note, 13)
	note_label.custom_minimum_size = Vector2(300.0, 0.0)
	text.add_child(note_label)
	return row

func _caption(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MenuStyle.tracked_font(1))
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label

func _muted_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MenuStyle.TEXT_MUTED)
	label.add_theme_constant_override("line_spacing", 3)
	return label

func _footer_button(node_name: String, text: String, primary: bool, compact: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	MenuStyle.apply_action_button(button, primary, MenuStyle.ACCENT, compact)
	button.add_theme_font_size_override("font_size", 15)
	return button

func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
