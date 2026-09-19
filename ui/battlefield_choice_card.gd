class_name BattlefieldChoiceCard
extends Button
## Large selectable battlefield card: a top-down terrain preview above the name, summary and key facts.
## Pointer hover and keyboard focus share one selection state, like MenuListButton.

const CARD_SIZE := Vector2(268.0, 488.0)
const PADDING := 14.0
const SELECTED_SCALE := 1.035
const TRANSITION_SECONDS := 0.16
const BRACKET_LENGTH := 18.0

## Empty for the random choice; otherwise the BattlefieldLayoutDefinition id this card starts.
var layout_id: StringName = &""
var title: String = ""
var summary: String = ""
var preview: Texture2D
## Pairs of [label, value] listed at the bottom of the card.
var facts: Array[PackedStringArray] = []

var selection: float = 0.0:
	set(value):
		selection = value
		_apply_selection()

var _frame: StyleBoxFlat
var _content: VBoxContainer
var _preview_rect: TextureRect
var _title_label: Label
var _tween: Tween

static func for_layout(layout: BattlefieldLayoutDefinition) -> BattlefieldChoiceCard:
	var card := BattlefieldChoiceCard.new()
	card.name = "Layout_%s" % String(layout.id)
	card.layout_id = layout.id
	card.title = layout.display_name
	card.summary = layout.summary
	card.preview = layout.preview
	card.facts = [
		PackedStringArray(["도시 지구", "%d곳" % layout.city_districts.size()]),
		PackedStringArray(["최고층 건물", "%dm" % roundi(layout.maximum_building_height)]),
		PackedStringArray(["추가 예산", "+%d" % layout.starting_budget_bonus if layout.starting_budget_bonus > 0 else "없음"]),
	]
	return card

static func random_choice(preview_texture: Texture2D, layout_count: int) -> BattlefieldChoiceCard:
	var card := BattlefieldChoiceCard.new()
	card.name = "RandomLayoutButton"
	card.title = "랜덤"
	card.summary = "%d가지 전장 중 하나를 무작위로 고르고 방향과 세부 지형도 새로 만듭니다." % layout_count
	card.preview = preview_texture
	card.facts = [
		PackedStringArray(["전장 종류", "%d종 중 하나" % layout_count]),
		PackedStringArray(["지형 변형", "매번 새로"]),
		PackedStringArray(["추가 예산", "전장별 적용"]),
	]
	return card

func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	tooltip_text = ""
	_frame = StyleBoxFlat.new()
	_frame.set_border_width_all(1)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _frame if state != "focus" else StyleBoxEmpty.new())
	_build_content()
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_animate_selection.bind(1.0))
	focus_exited.connect(_animate_selection.bind(0.0))
	_apply_selection()

func _build_content() -> void:
	var content := VBoxContainer.new()
	_content = content
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(PADDING))
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	_preview_rect = TextureRect.new()
	_preview_rect.texture = preview
	_preview_rect.custom_minimum_size = Vector2(0.0, CARD_SIZE.x - PADDING * 2.0)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_preview_rect)
	_title_label = _label(title, 23, MenuStyle.TEXT)
	content.add_child(_title_label)
	var summary_label := _label(summary, 14, MenuStyle.TEXT_MUTED)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_constant_override("line_spacing", 3)
	summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(summary_label)
	var fact_grid := GridContainer.new()
	fact_grid.columns = 2
	fact_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fact_grid.add_theme_constant_override("v_separation", 4)
	for fact: PackedStringArray in facts:
		var name_label := _label(fact[0], 13, Color(MenuStyle.TEXT_MUTED, 0.8))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fact_grid.add_child(name_label)
		var value_label := _label(fact[1], 14, MenuStyle.ACCENT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fact_grid.add_child(value_label)
	content.add_child(fact_grid)

func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()

func _animate_selection(target: float) -> void:
	if _tween != null:
		_tween.kill()
	if not is_inside_tree() or not is_visible_in_tree():
		selection = target
		return
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "selection", target, TRANSITION_SECONDS)

func _apply_selection() -> void:
	if _frame == null:
		return
	_frame.bg_color = Color(0.02, 0.04, 0.05, 0.9).lerp(Color(0.04, 0.1, 0.11, 0.96), selection)
	_frame.border_color = Color(MenuStyle.ACCENT, lerpf(0.16, 0.9, selection))
	_frame.border_width_top = 1 + roundi(selection * 2.0)
	_frame.shadow_color = Color(MenuStyle.ACCENT, 0.18 * selection)
	_frame.shadow_size = roundi(18.0 * selection)
	_preview_rect.modulate = Color(1, 1, 1, 1).lerp(Color(0.62, 0.7, 0.72, 1), 1.0 - selection)
	_title_label.add_theme_color_override("font_color", MenuStyle.TEXT.lerp(Color.WHITE, selection))
	scale = Vector2.ONE * lerpf(1.0, SELECTED_SCALE, selection)
	queue_redraw()

func _draw() -> void:
	if selection <= 0.001:
		return
	# Targeting brackets around the preview mark the chosen battlefield.
	var color := Color(MenuStyle.ACCENT, selection)
	var rect := Rect2(_content.position + _preview_rect.position, _preview_rect.size).grow(5.0)
	var length := BRACKET_LENGTH * selection
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var horizontal := signf(rect.get_center().x - corner.x)
		var vertical := signf(rect.get_center().y - corner.y)
		draw_polyline(PackedVector2Array([corner + Vector2(horizontal * length, 0), corner, corner + Vector2(0, vertical * length)]), color, 2.0)
