class_name MenuStyle
extends RefCounted
## Shared palette and style factories for full-screen menus and modal panels.

const ACCENT := Color("6fd6c8")
const DANGER := Color("ff6a4d")
const WARNING := Color("ffbd80")
const TEXT := Color("e6eeec")
const TEXT_MUTED := Color("93a8ab")
const TEXT_DISABLED := Color(0.62, 0.7, 0.72, 0.32)
const SURFACE := Color(0.02, 0.035, 0.045, 0.94)
const FONT_PATH := "res://ui/fonts/NanumSquareB.ttf"

static var _tracked_fonts: Dictionary[int, FontVariation] = {}

## Letter-spaced variant of the UI font for small captions and headings.
static func tracked_font(spacing: int = 2) -> FontVariation:
	if not _tracked_fonts.has(spacing):
		var font := FontVariation.new()
		font.base_font = load(FONT_PATH) as Font
		font.spacing_glyph = spacing
		_tracked_fonts[spacing] = font
	return _tracked_fonts[spacing]

## Outlined status pill; the caller recolors it as the state changes.
static func badge(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	recolor_badge(style, color)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

static func recolor_badge(style: StyleBoxFlat, color: Color) -> void:
	style.bg_color = Color(color, 0.14)
	style.border_color = Color(color, 0.6)

## One-pixel accent rule for HSeparator.
static func rule(accent: Color = ACCENT, alpha: float = 0.25) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = Color(accent, alpha)
	line.thickness = 1
	return line

## Flat rectangular panel with a strong accent edge on top, as used by modal screens.
static func panel(accent: Color = ACCENT, margin: float = 32.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = Color(accent, 0.5)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 24
	return style

## Compact rectangular command button; primary buttons are filled with the accent color.
static func apply_action_button(button: Button, primary: bool = false, accent: Color = ACCENT, compact: bool = false) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_content_margin_all(6 if compact else 12)
		style.content_margin_left = 12 if compact else 22
		style.content_margin_right = 12 if compact else 22
		style.set_border_width_all(1)
		style.bg_color = Color(accent, 0.2) if primary else Color(0.06, 0.1, 0.12, 0.9)
		style.border_color = Color(accent, 0.75) if primary else Color(accent, 0.22)
		match state:
			"hover", "focus":
				style.bg_color = Color(accent, 0.34) if primary else Color(accent, 0.14)
				style.border_color = accent
			"pressed":
				style.bg_color = Color(accent, 0.48)
				style.border_color = accent
			"disabled":
				style.bg_color = Color(0.04, 0.06, 0.07, 0.7)
				style.border_color = Color(accent, 0.08)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)

## Dropdown field matching the action button frame.
static func apply_option(option: OptionButton) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.1, 0.12, 0.9)
		style.border_color = Color(ACCENT, 0.22)
		style.set_border_width_all(1)
		style.set_content_margin_all(10)
		style.content_margin_left = 14
		match state:
			"hover", "focus":
				style.border_color = ACCENT
			"pressed":
				style.bg_color = Color(ACCENT, 0.16)
				style.border_color = ACCENT
			"disabled":
				style.bg_color = Color(0.04, 0.06, 0.07, 0.6)
				style.border_color = Color(ACCENT, 0.08)
		option.add_theme_stylebox_override(state, style)
	option.add_theme_color_override("font_color", TEXT)
	option.add_theme_color_override("font_disabled_color", TEXT_DISABLED)

## Game-style tab strip: text tabs with an accent underline on the active tab.
static func apply_tabs(tabs: TabContainer) -> void:
	for state: String in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(ACCENT, 0.1) if state == "tab_selected" else Color(0, 0, 0, 0)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		style.border_color = ACCENT if state == "tab_selected" else Color(ACCENT, 0.4)
		style.border_width_bottom = 2 if state in ["tab_selected", "tab_hovered"] else 0
		if state == "tab_focus":
			style.draw_center = false
			style.border_width_bottom = 2
		tabs.add_theme_stylebox_override(state, style)
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(0, 0, 0, 0)
	bar.border_color = Color(ACCENT, 0.18)
	bar.border_width_bottom = 1
	tabs.add_theme_stylebox_override("tabbar_background", bar)
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", TEXT_MUTED)
	tabs.add_theme_color_override("font_hovered_color", TEXT)
	tabs.add_theme_font_size_override("font_size", 17)

## Horizontal slider with a thin track, accent fill and a narrow rectangular grabber.
static func apply_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.24, 0.27)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(ACCENT, 0.8)
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_highlight := fill.duplicate() as StyleBoxFlat
	fill_highlight.bg_color = ACCENT
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_highlight)
	slider.add_theme_icon_override("grabber", _grabber_texture(Color(0.86, 0.95, 0.93)))
	slider.add_theme_icon_override("grabber_highlight", _grabber_texture(Color.WHITE))
	slider.add_theme_icon_override("grabber_disabled", _grabber_texture(Color(0.4, 0.46, 0.48)))

static func _grabber_texture(color: Color) -> ImageTexture:
	var image := Image.create(8, 20, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
