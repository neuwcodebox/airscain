class_name CityStatusIndicator
extends Label

enum Level { NORMAL, WARNING, CRITICAL }

const NORMAL_COLOR := Color(0.68, 0.8, 0.85)
const WARNING_COLOR := Color(1.0, 0.82, 0.36)
const CRITICAL_COLOR := Color(1.0, 0.36, 0.3)
const CRITICAL_DIM_COLOR := Color(0.62, 0.2, 0.18)
const HIT_COLOR := Color(1.0, 0.94, 0.9)
const DAMAGE_CHANGE_COLOR := Color(1.0, 0.36, 0.3)
const RESTORATION_CHANGE_COLOR := Color(0.45, 0.95, 0.6)
const WARNING_RATIO := 0.5
const CRITICAL_RATIO := 0.25
const HIT_DURATION := 0.45
const HIT_SCALE := 0.18
const CRITICAL_PULSE_PERIOD := 1.1
const CHANGE_DURATION := 1.2
const CHANGE_MERGE_WINDOW := 0.6
const CHANGE_TRAVEL := 8.0
const CHANGE_GAP := 8.0
const CHANGE_SLOT_WIDTH := 44.0
const CHANGE_FONT_SIZE := 15

var level: Level = Level.NORMAL
var hit_elapsed: float = HIT_DURATION
var pulse_time: float = 0.0
var change_amount: int = 0
var change_elapsed: float = CHANGE_DURATION
var change_label: Label
var value_width: float = 0.0

func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	change_label = Label.new()
	change_label.name = "ChangeLabel"
	change_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	change_label.add_theme_font_size_override("font_size", CHANGE_FONT_SIZE)
	change_label.hide()
	add_child(change_label)
	_apply_visuals()
	set_process(false)

func set_integrity(current: int, maximum: int) -> void:
	var format := tr("도시  %d / %d")
	text = format % [current, maximum]
	value_width = ceilf(get_theme_font("font").get_string_size(format % [maximum, maximum], HORIZONTAL_ALIGNMENT_LEFT, -1.0, get_theme_font_size("font_size")).x)
	custom_minimum_size.x = value_width + CHANGE_GAP + CHANGE_SLOT_WIDTH
	level = level_for(current, maximum)
	_update_processing()
	_apply_visuals()

func show_damage(amount: int) -> void:
	if amount <= 0:
		return
	hit_elapsed = 0.0
	_show_change(-amount)

func show_restoration(amount: int) -> void:
	if amount > 0:
		_show_change(amount)

func is_animating() -> bool:
	return hit_elapsed < HIT_DURATION or change_elapsed < CHANGE_DURATION or level == Level.CRITICAL

static func level_for(current: int, maximum: int) -> Level:
	var ratio := float(current) / float(maxi(1, maximum))
	if ratio <= CRITICAL_RATIO:
		return Level.CRITICAL
	if ratio <= WARNING_RATIO:
		return Level.WARNING
	return Level.NORMAL

func level_color() -> Color:
	match level:
		Level.WARNING:
			return WARNING_COLOR
		Level.CRITICAL:
			var pulse := 0.5 + 0.5 * cos(TAU * pulse_time / CRITICAL_PULSE_PERIOD)
			return CRITICAL_DIM_COLOR.lerp(CRITICAL_COLOR, pulse)
	return NORMAL_COLOR

func _process(delta: float) -> void:
	var step := maxf(0.0, delta)
	hit_elapsed = minf(HIT_DURATION, hit_elapsed + step)
	change_elapsed = minf(CHANGE_DURATION, change_elapsed + step)
	pulse_time = fmod(pulse_time + step, CRITICAL_PULSE_PERIOD) if level == Level.CRITICAL else 0.0
	_apply_visuals()
	_update_processing()

func _show_change(amount: int) -> void:
	var same_direction := signi(amount) == signi(change_amount)
	if change_elapsed < CHANGE_MERGE_WINDOW and same_direction:
		change_amount += amount
	else:
		change_amount = amount
	change_elapsed = 0.0
	change_label.text = "%+d" % change_amount
	change_label.add_theme_color_override("font_color", DAMAGE_CHANGE_COLOR if change_amount < 0 else RESTORATION_CHANGE_COLOR)
	change_label.show()
	_update_processing()
	_apply_visuals()

func _apply_visuals() -> void:
	var hit := 1.0 - smoothstep(0.0, 1.0, hit_elapsed / HIT_DURATION)
	var base_color := level_color()
	add_theme_color_override("font_color", base_color.lerp(HIT_COLOR if level == Level.CRITICAL else CRITICAL_COLOR, hit))
	pivot_offset = Vector2(value_width * 0.5, size.y * 0.5)
	scale = Vector2.ONE * (1.0 + HIT_SCALE * hit)
	if change_label == null:
		return
	if change_elapsed >= CHANGE_DURATION:
		change_label.hide()
		return
	var progress := change_elapsed / CHANGE_DURATION
	change_label.reset_size()
	var rise := CHANGE_TRAVEL * smoothstep(0.0, 1.0, progress)
	change_label.position = Vector2(value_width + CHANGE_GAP, (size.y - change_label.size.y) * 0.5 + CHANGE_TRAVEL * 0.5 - rise)
	change_label.modulate.a = 1.0 - smoothstep(0.55, 1.0, progress)

func _update_processing() -> void:
	set_process(is_animating())
