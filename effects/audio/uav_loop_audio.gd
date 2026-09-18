class_name UavLoopAudio
extends Node
## One non-spatial loop per UAV sound family; source count never amplifies it.

const LIGHT := &"uav_light"
const MEDIUM := &"uav_medium"
const HEAVY := &"uav_heavy"
const MAX_VOICES := 3
const MIX_BUDGET := 0.24
const FADE_SECONDS := 0.2
const DEPARTURE_SECONDS := 2.0
const STREAMS: Dictionary = {
	LIGHT: preload("res://enemy/attack_uav/audio/plane_loop_light_1.ogg"),
	MEDIUM: preload("res://enemy/attack_uav/audio/plane_loop_medium_1.ogg"),
	HEAVY: preload("res://enemy/attack_uav/audio/plane_loop_heavy_1.ogg"),
}
# Measured -13.71/-9.69/-9.16 LUFS. Light peaks at -30, others at -26 LUFS.
const GAINS_DB: Dictionary = {LIGHT: -16.29, MEDIUM: -16.31, HEAVY: -16.84}
const LEAD_SECONDS: Dictionary = {LIGHT: 10.0, MEDIUM: 16.0, HEAVY: 16.0}

class Source:
	var threat: ThreatUnit
	var event: StringName
	var envelope: float = 0.0
	var departing: bool = false
	var departure_remaining: float = DEPARTURE_SECONDS
	var departure_gain: float = 0.0

class Voice:
	var player: AudioStreamPlayer
	var envelope: float = 0.0
	var event: StringName

var sources: Dictionary[int, Source] = {}
var voices: Array[Voice] = []
var simulation_clock: float = 0.0
var playback_clock: float = 0.0

static func all_streams() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for stream: AudioStreamOggVorbis in STREAMS.values():
		stream.loop = true
		result.append(stream)
	return result

func _ready() -> void:
	all_streams()
	var index := 0
	for event: StringName in STREAMS:
		var voice := Voice.new()
		voice.event = event
		voice.player = AudioPlayback.create_player()
		voice.player.name = "UavLoop%d" % index
		add_child(voice.player)
		voices.append(voice)
		index += 1

func register(threat: ThreatUnit) -> void:
	var event := threat.definition.loop_audio_event
	var id := threat.get_instance_id()
	if not STREAMS.has(event) or sources.has(id) or not threat.is_targetable() or threat.presentation_action_completed():
		return
	var source := Source.new()
	source.threat = threat
	source.event = event
	sources[id] = source
	var ended := _on_resolved.bind(id)
	if not threat.resolved.is_connected(ended):
		threat.resolved.connect(ended)
	var exiting := _remove_source.bind(id)
	if not threat.tree_exiting.is_connected(exiting):
		threat.tree_exiting.connect(exiting)

func _on_resolved(_threat: ThreatUnit, _neutralized: bool, _reward: int, id: int) -> void:
	_remove_source(id)

func _remove_source(id: int) -> void:
	sources.erase(id)

func update_audio(delta: float, paused: bool, rate: float, enabled: bool) -> void:
	if not enabled:
		reset()
		return
	for voice: Voice in voices:
		AudioPlayback.sync(voice.player, paused)
	if paused:
		return
	var simulation_delta := delta * rate
	simulation_clock += simulation_delta
	playback_clock += delta
	var event_envelopes := _refresh_sources(simulation_delta)
	for voice: Voice in voices:
		var target := float(event_envelopes.get(voice.event, 0.0))
		voice.envelope = move_toward(voice.envelope, target, simulation_delta / FADE_SECONDS)
		if voice.envelope > 0.0 and not voice.player.playing:
			voice.player.stream = STREAMS[voice.event]
			AudioPlayback.play(voice.player, fposmod(playback_clock, voice.player.stream.get_length()))
		elif target == 0.0 and voice.envelope <= 0.0 and voice.player.playing:
			voice.player.stop()
			voice.player.stream = null
	_apply_mix_budget()

func _refresh_sources(delta: float) -> Dictionary[StringName, float]:
	var event_envelopes: Dictionary[StringName, float] = {}
	for event: StringName in STREAMS:
		event_envelopes[event] = 0.0
	for id: int in sources.keys():
		var source := sources[id]
		var threat := source.threat
		if not is_instance_valid(threat) or not threat.is_targetable():
			sources.erase(id)
			continue
		var seconds := INF
		if threat.presentation_action_completed():
			if not source.departing:
				source.departing = true
				source.departure_gain = source.envelope
			source.departure_remaining = maxf(0.0, source.departure_remaining - delta)
			source.envelope = source.departure_gain * source.departure_remaining / DEPARTURE_SECONDS
		elif threat.exits_without_impact():
			source.envelope = 0.0
		else:
			seconds = threat.presentation_action_seconds()
			var progress := clampf(1.0 - seconds / float(LEAD_SECONDS[source.event]), 0.0, 1.0) if is_finite(seconds) and seconds >= 0.0 else 0.0
			source.envelope = smoothstep(0.0, 1.0, progress)
		event_envelopes[source.event] = maxf(float(event_envelopes[source.event]), source.envelope)
	return event_envelopes

func _apply_mix_budget() -> void:
	var requested_total := 0.0
	for voice: Voice in voices:
		requested_total += voice.envelope * db_to_linear(float(GAINS_DB[voice.event]))
	var scale := minf(1.0, MIX_BUDGET / maxf(requested_total, 0.0001))
	for voice: Voice in voices:
		voice.player.volume_linear = voice.envelope * db_to_linear(float(GAINS_DB[voice.event])) * scale

func reset() -> void:
	for voice: Voice in voices:
		voice.player.stop()
		voice.player.stream = null
		voice.player.stream_paused = false
		voice.envelope = 0.0
	sources.clear()
	simulation_clock = 0.0
	playback_clock = 0.0
