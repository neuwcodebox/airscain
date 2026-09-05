class_name GunAirburstAudio
extends AudioStreamPlayer
## One shared layer for timed shell detonations from every gun in an operation.

const SOUND := preload("res://defense/close_in_gun/gun_self_destruction_1.ogg")
const QUIET_GRACE := 0.25
const FADE_IN := 0.06
const FADE_OUT := 0.3
const LEVEL := 0.25
static var _loop_stream: AudioStreamOggVorbis

static func loop_stream() -> AudioStreamOggVorbis:
	if _loop_stream == null:
		_loop_stream = SOUND.duplicate() as AudioStreamOggVorbis
		_loop_stream.loop = true
	return _loop_stream

var context: CombatAudio
var quiet_remaining: float = 0.0
var event_pending: bool = false
var gain: float = 0.0
var starts: int = 0

func _ready() -> void:
	bus = &"Guns"
	stream = loop_stream()
	playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if CombatAudio.uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
	volume_linear = 0.0

func notify_detonation(_position: Vector3, reason: StringName) -> void:
	if reason != &"timeout" or context == null or not context.enabled or context.simulation_paused:
		return
	quiet_remaining = QUIET_GRACE
	event_pending = true
	if not playing:
		starts += 1
		play()

func reset() -> void:
	stop()
	quiet_remaining = 0.0
	event_pending = false
	gain = 0.0
	volume_linear = 0.0

func _process(delta: float) -> void:
	if context == null or not context.enabled:
		reset()
		return
	if stream_paused != context.simulation_paused:
		stream_paused = context.simulation_paused
	if context.simulation_paused:
		return
	if event_pending:
		event_pending = false
	else:
		quiet_remaining = maxf(0.0, quiet_remaining - delta)
	var sustaining := quiet_remaining > 0.0
	gain = move_toward(gain, LEVEL if sustaining else 0.0, LEVEL * delta / (FADE_IN if sustaining else FADE_OUT))
	volume_linear = gain
	if not sustaining and gain <= 0.0:
		stop()
