class_name ThreatApproachAudio
extends Node
## One approach cue per threat; audio never controls flight or weapon release.

const EVENT := &"jet_flyover"
const PEAK_SECONDS := 6.5
const MAX_VOICES := 2
const START_INTERVAL := 0.75
const RETIRE_SECONDS := 0.25
# Static offsets preserve the recordings' approach/departure envelopes.
# Measured originals: -16.5/-17.4/-6.1 LUFS; each plays at about -26 LUFS.
const GAINS_DB: Array[float] = [-9.5, -8.6, -19.9]
const STREAMS: Array[AudioStream] = [
	preload("res://enemy/strike_aircraft/audio/jet_flyover_1.ogg"),
	preload("res://enemy/strike_aircraft/audio/jet_flyover_2.ogg"),
	preload("res://enemy/strike_aircraft/audio/jet_flyover_3.ogg"),
]

class Voice:
	var player: AudioStreamPlayer
	var source_id: int = 0
	var retiring: bool = false
	var fade_remaining: float = 0.0
	var gain: float = 0.0

var voices: Array[Voice] = []
var threats: Dictionary[int, ThreatUnit] = {}
var attempted: Dictionary[int, bool] = {}
var cooldown: float = 0.0
var next_variant: int = 0
var played_count: int = 0

static func all_streams() -> Array[AudioStream]:
	return STREAMS.duplicate()

func _ready() -> void:
	for index: int in MAX_VOICES:
		var voice := Voice.new()
		voice.player = AudioStreamPlayer.new()
		voice.player.name = "Flyover%d" % index
		voice.player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if CombatAudio.uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(voice.player)
		voices.append(voice)

func register(threat: ThreatUnit) -> void:
	if threat.definition.approach_audio_event != EVENT:
		return
	var id := threat.get_instance_id()
	if threats.has(id):
		return
	threats[id] = threat
	var resolved_callback := _on_resolved.bind(id)
	if not threat.resolved.is_connected(resolved_callback):
		threat.resolved.connect(resolved_callback)
	var exit_callback := _on_exiting.bind(id)
	if not threat.tree_exiting.is_connected(exit_callback):
		threat.tree_exiting.connect(exit_callback)

func update_audio(delta: float, paused: bool, rate: float, enabled: bool) -> void:
	if not enabled:
		reset()
		return
	for voice: Voice in voices:
		voice.player.stream_paused = paused
		voice.player.pitch_scale = maxf(0.01, rate)
	if paused:
		return
	cooldown = maxf(0.0, cooldown - delta)
	for voice: Voice in voices:
		if voice.retiring:
			voice.fade_remaining = maxf(0.0, voice.fade_remaining - delta)
			voice.player.volume_linear = voice.gain * voice.fade_remaining / RETIRE_SECONDS
			if voice.fade_remaining <= 0.0:
				voice.player.stop()
				voice.retiring = false
		if not voice.player.playing:
			voice.source_id = 0
			voice.player.stream = null
	for id: int in threats:
		var threat := threats[id]
		var seconds := threat.presentation_action_seconds()
		if attempted.has(id):
			if threat.exits_without_impact() and not threat.presentation_action_completed():
				retire(id)
			continue
		if not is_finite(seconds) or seconds < 0.0 or seconds > PEAK_SECONDS:
			continue
		# Crowded cues are dropped once, never queued for a late replay.
		attempted[id] = true
		if cooldown > 0.0:
			continue
		for voice: Voice in voices:
			if voice.player.playing or voice.retiring:
				continue
			voice.source_id = id
			voice.gain = db_to_linear(GAINS_DB[next_variant])
			voice.player.volume_linear = voice.gain
			voice.player.stream = STREAMS[next_variant]
			# Late spawns/restores enter at the corresponding approach position.
			voice.player.play(PEAK_SECONDS - seconds)
			next_variant = (next_variant + 1) % STREAMS.size()
			cooldown = START_INTERVAL
			played_count += 1
			break

func retire(id: int) -> void:
	for voice: Voice in voices:
		if voice.source_id == id and voice.player.playing and not voice.retiring:
			voice.retiring = true
			voice.fade_remaining = RETIRE_SECONDS

func _on_resolved(_threat: ThreatUnit, neutralized: bool, _reward: int, id: int) -> void:
	if neutralized:
		retire(id)

func _on_exiting(id: int) -> void:
	var threat := threats.get(id) as ThreatUnit
	if is_instance_valid(threat) and not threat.presentation_action_completed():
		retire(id)
	threats.erase(id)
	attempted.erase(id)

func reset() -> void:
	for voice: Voice in voices:
		voice.player.stop()
		voice.player.stream = null
		voice.player.stream_paused = false
		voice.source_id = 0
		voice.retiring = false
	threats.clear()
	attempted.clear()
	cooldown = 0.0
