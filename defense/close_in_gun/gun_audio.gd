class_name GunAudio
extends AudioStreamPlayer

const RELEASE_DELAY := 0.12
const CROSSFADE_SECONDS := 0.06
const LOOP_START_SECONDS := 25216.0 / 44100.0
const SUSTAIN_SOUND := preload("res://defense/close_in_gun/gun_sustain.ogg")
const END_SOUND := preload("res://defense/close_in_gun/gun_end_1.ogg")
static var _sustain_stream: AudioStreamOggVorbis

var context: CombatAudio
var ending_player: AudioStreamPlayer
var firing: bool = false
var release_remaining: float = 0.0
var tail_remaining: float = 0.0
var starts: int = 0
var endings: int = 0
var shot_pending: bool = false
var sustain_gain: float = 0.0
var ending_gain: float = 0.0
var mix_gain: float = 0.25
var audible: bool = false
var firing_elapsed: float = 0.0

static func sustain_stream() -> AudioStreamOggVorbis:
	if _sustain_stream == null:
		_sustain_stream = SUSTAIN_SOUND.duplicate() as AudioStreamOggVorbis
		_sustain_stream.loop = true
		_sustain_stream.loop_offset = LOOP_START_SECONDS
	return _sustain_stream

static func all_streams() -> Array[AudioStream]:
	return [sustain_stream(), END_SOUND]

func _ready() -> void:
	# WebAudio decodes the shared Ogg before combat and schedules its loop
	# independently of game frames. Do not route this through a WASM stream.
	stream = sustain_stream()
	playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if CombatAudio.uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
	volume_linear = 0.0
	ending_player = AudioStreamPlayer.new()
	ending_player.name = "Ending"
	ending_player.stream = END_SOUND
	ending_player.playback_type = playback_type
	ending_player.volume_linear = 0.0
	add_child(ending_player)

func notify_shot() -> void:
	if context == null or not context.enabled or context.simulation_paused:
		return
	release_remaining = RELEASE_DELAY
	shot_pending = true
	if firing:
		return
	firing = true
	firing_elapsed = 0.0
	tail_remaining = 0.0
	starts += 1
	context.register_gun_voice(self)
	if audible and not playing:
		play()

func set_audible(value: bool) -> void:
	if audible == value:
		return
	audible = value
	if not audible:
		return
	if firing and not playing:
		var offset := firing_elapsed
		if offset >= LOOP_START_SECONDS:
			offset = LOOP_START_SECONDS + fmod(offset - LOOP_START_SECONDS, stream.get_length() - LOOP_START_SECONDS)
		play(offset)
	elif not firing and tail_remaining > 0.0 and not ending_player.playing:
		ending_player.bus = bus
		ending_player.play(maxf(0.0, END_SOUND.get_length() + 0.1 - tail_remaining))

func set_mix_gain(value: float) -> void:
	mix_gain = value
	_apply_gain()

func _apply_gain() -> void:
	volume_linear = mix_gain * sustain_gain
	ending_player.volume_linear = mix_gain * ending_gain

func _exit_tree() -> void:
	if is_instance_valid(context):
		context.unregister_gun_voice(self)

func _process(delta: float) -> void:
	if context == null or not context.enabled:
		stop()
		ending_player.stop()
		firing = false
		audible = false
		release_remaining = 0.0
		tail_remaining = 0.0
		shot_pending = false
		sustain_gain = 0.0
		ending_gain = 0.0
		if is_instance_valid(context):
			context.unregister_gun_voice(self)
		_apply_gain()
		return
	# Reapplying false can recreate WebAudio Sample sources every frame.
	if stream_paused != context.simulation_paused:
		stream_paused = context.simulation_paused
	if ending_player.stream_paused != context.simulation_paused:
		ending_player.stream_paused = context.simulation_paused
	if context.simulation_paused:
		return
	if firing:
		firing_elapsed += delta
		if shot_pending:
			shot_pending = false
		else:
			release_remaining -= delta
			if release_remaining <= 0.0:
				firing = false
				endings += 1
				tail_remaining = END_SOUND.get_length() + 0.1
				context.refresh_gun_mix()
				if audible and not ending_player.playing:
					ending_player.bus = bus
					ending_player.play()
	elif tail_remaining > 0.0:
		tail_remaining -= delta
		if tail_remaining <= 0.0:
			ending_player.stop()
			context.unregister_gun_voice(self)
	sustain_gain = move_toward(sustain_gain, 1.0 if firing and audible else 0.0, delta / CROSSFADE_SECONDS)
	ending_gain = move_toward(ending_gain, 1.0 if not firing and tail_remaining > 0.0 and audible else 0.0, delta / CROSSFADE_SECONDS)
	_apply_gain()
	if (not firing or not audible) and sustain_gain <= 0.0:
		stop()
	if (firing or not audible) and ending_gain <= 0.0:
		ending_player.stop()
