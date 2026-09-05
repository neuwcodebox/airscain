class_name GunAudio
extends AudioStreamPlayer

const START := 0
const LOOP := 1
const END := 2
const RELEASE_DELAY := 0.12
const CROSSFADE_BEATS := 0.06
const START_SOUND := preload("res://defense/close_in_gun/gun_start_1.ogg")
const LOOP_SOUND := preload("res://defense/close_in_gun/gun_loop_1.ogg")
const END_SOUND := preload("res://defense/close_in_gun/gun_end_1.ogg")

var context: CombatAudio
var firing: bool = false
var release_remaining: float = 0.0
var tail_remaining: float = 0.0
var starts: int = 0
var endings: int = 0
var shot_pending: bool = false

func _ready() -> void:
	# Transitions run in the audio mixer, not on a frame-delayed finished signal.
	var sequence := AudioStreamInteractive.new()
	sequence.clip_count = 3
	for index: int in 3:
		var clip := ([START_SOUND, LOOP_SOUND, END_SOUND][index] as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		clip.loop = index == LOOP
		clip.bpm = 60.0
		sequence.set_clip_stream(index, clip)
	sequence.set_clip_auto_advance(START, AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
	sequence.set_clip_auto_advance_next_clip(START, LOOP)
	sequence.add_transition(START, LOOP, AudioStreamInteractive.TRANSITION_FROM_TIME_END, AudioStreamInteractive.TRANSITION_TO_TIME_START, AudioStreamInteractive.FADE_CROSS, CROSSFADE_BEATS)
	for from_clip: int in [START, LOOP]:
		sequence.add_transition(from_clip, END, AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START, AudioStreamInteractive.FADE_CROSS, CROSSFADE_BEATS)
	sequence.add_transition(END, START, AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START, AudioStreamInteractive.FADE_CROSS, CROSSFADE_BEATS)
	stream = sequence
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	volume_db = -12.0

func notify_shot() -> void:
	if context == null or not context.enabled or context.simulation_paused:
		return
	release_remaining = RELEASE_DELAY
	shot_pending = true
	if firing:
		return
	firing = true
	tail_remaining = 0.0
	starts += 1
	if playing:
		(get_stream_playback() as AudioStreamPlaybackInteractive).switch_to_clip(START)
	else:
		play()

func _process(delta: float) -> void:
	if context == null or not context.enabled:
		stop()
		firing = false
		release_remaining = 0.0
		tail_remaining = 0.0
		shot_pending = false
		return
	stream_paused = context.simulation_paused
	if stream_paused:
		return
	if firing:
		# A long render frame must not expire a shot received in that same frame.
		if shot_pending:
			shot_pending = false
			return
		release_remaining -= delta
		if release_remaining <= 0.0:
			firing = false
			endings += 1
			tail_remaining = END_SOUND.get_length() + 0.1
			if playing:
				(get_stream_playback() as AudioStreamPlaybackInteractive).switch_to_clip(END)
	elif tail_remaining > 0.0:
		tail_remaining -= delta
		if tail_remaining <= 0.0:
			stop()
