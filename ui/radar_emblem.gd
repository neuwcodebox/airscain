class_name RadarEmblem
extends Control
## Small animated radar scope used as the title mark on menu screens.

const SWEEP_SECONDS := 3.2
const TRAIL_RADIANS := 1.1
const TRAIL_STEPS := 18

var _angle: float = -PI * 0.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	_angle = wrapf(_angle + TAU * delta / SWEEP_SECONDS, -PI, PI)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.0
	var accent := MenuStyle.ACCENT
	draw_circle(center, radius, Color(0.02, 0.06, 0.07, 0.75))
	var trail := PackedVector2Array([center])
	var colors := PackedColorArray([Color(accent, 0.45)])
	for step: int in TRAIL_STEPS + 1:
		var fraction := float(step) / TRAIL_STEPS
		var angle := _angle - fraction * TRAIL_RADIANS
		trail.append(center + Vector2.from_angle(angle) * radius)
		colors.append(Color(accent, 0.4 * (1.0 - fraction)))
	draw_polygon(trail, colors)
	draw_arc(center, radius, 0, TAU, 64, Color(accent, 0.9), 1.5, true)
	draw_arc(center, radius * 0.62, 0, TAU, 48, Color(accent, 0.3), 1.0, true)
	draw_arc(center, radius * 0.26, 0, TAU, 32, Color(accent, 0.3), 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(accent, 0.18), 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(accent, 0.18), 1.0)
	draw_line(center, center + Vector2.from_angle(_angle) * radius, accent, 1.5, true)
	var contact_angle := -0.55
	var since_swept := wrapf(_angle - contact_angle, 0.0, TAU)
	var glow := clampf(1.0 - since_swept / (TAU * 0.8), 0.0, 1.0)
	draw_circle(center + Vector2.from_angle(contact_angle) * radius * 0.7, 2.5, Color(MenuStyle.WARNING, 0.15 + glow * 0.85))
