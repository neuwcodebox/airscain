class_name MenuListButton
extends Button
## Full-screen menu entry. Pointer hover and keyboard focus share one selection state,
## shown by an accent marker and a fading highlight that slides the label inward.

const MARKER_WIDTH := 3.0
const REST_MARGIN := 26.0
const SELECTED_MARGIN := 40.0
const TRANSITION_SECONDS := 0.14

## One-line explanation shown by the owning menu while this entry is selected.
@export_multiline var description: String = ""

var selection: float = 0.0:
	set(value):
		selection = value
		_apply_selection()

var _highlight: StyleBoxTexture
var _tween: Tween

func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	var gradient := Gradient.new()
	gradient.set_color(0, Color(MenuStyle.ACCENT, 0.26))
	gradient.set_color(1, Color(MenuStyle.ACCENT, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 1
	_highlight = StyleBoxTexture.new()
	_highlight.texture = texture
	_highlight.content_margin_top = 8
	_highlight.content_margin_bottom = 8
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, _highlight)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_color_override("font_color", MenuStyle.TEXT_MUTED)
	add_theme_color_override("font_hover_color", MenuStyle.TEXT_MUTED)
	add_theme_color_override("font_pressed_color", Color.WHITE)
	add_theme_color_override("font_focus_color", Color.WHITE)
	add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	add_theme_color_override("font_disabled_color", MenuStyle.TEXT_DISABLED)
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_animate_selection.bind(1.0))
	focus_exited.connect(_animate_selection.bind(0.0))
	_apply_selection()

## Enables or disables the entry and keeps unavailable entries out of keyboard navigation.
func set_available(available: bool) -> void:
	disabled = not available
	focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	if not available and has_focus():
		release_focus()
	_apply_selection()

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
	if _highlight == null:
		return
	var shown := selection * (0.45 if disabled else 1.0)
	_highlight.modulate_color = Color(1, 1, 1, shown)
	_highlight.content_margin_left = lerpf(REST_MARGIN, SELECTED_MARGIN, selection)
	add_theme_color_override("font_focus_color", MenuStyle.TEXT_DISABLED if disabled else Color.WHITE)
	queue_redraw()

func _draw() -> void:
	if selection <= 0.001:
		return
	var alpha := selection * (0.4 if disabled else 1.0)
	var bar_height := size.y * lerpf(0.3, 1.0, selection)
	draw_rect(Rect2(0, (size.y - bar_height) * 0.5, MARKER_WIDTH, bar_height), Color(MenuStyle.ACCENT, alpha))
	var tip := Vector2(lerpf(12.0, 22.0, selection), size.y * 0.5)
	var arrow := PackedVector2Array([tip + Vector2(-6, -6), tip, tip + Vector2(-6, 6)])
	draw_polyline(arrow, Color(MenuStyle.ACCENT, alpha), 2.0, true)
