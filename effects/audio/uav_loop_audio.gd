class_name UavLoopAudio
extends Node
## Live volume arbitration; suppressed sources remain eligible until they leave.

const LIGHT := &"uav_light"
const MEDIUM := &"uav_medium"
const HEAVY := &"uav_heavy"
const MAX_VOICES := 4
const MAX_PER_EVENT := 2
const GROUP_WINDOW := 1.0
const FADE_SECONDS := 0.2
const DEPARTURE_SECONDS := 2.0
const HOLD_BONUS := 1.12
const STREAMS: Dictionary = {
	LIGHT: preload("res://enemy/attack_uav/audio/plane_loop_light_1.ogg"),
	MEDIUM: preload("res://enemy/attack_uav/audio/plane_loop_medium_1.ogg"),
	HEAVY: preload("res://enemy/attack_uav/audio/plane_loop_heavy_1.ogg"),
}
# Measured -13.71/-9.69/-9.16 LUFS. Light peaks at -30, others at -26 LUFS.
const GAINS_DB: Dictionary = {LIGHT: -16.29, MEDIUM: -16.31, HEAVY: -16.84}
const LEAD_SECONDS: Dictionary = {LIGHT: 10.0, MEDIUM: 16.0, HEAVY: 16.0}
static var _entry_streams: Dictionary[StringName, AudioStreamOggVorbis] = {}

class Source:
	var threat: ThreatUnit
	var event: StringName
	var group_id: int = 0
	var envelope: float = 0.0
	var departing: bool = false
	var departure_remaining: float = DEPARTURE_SECONDS
	var departure_gain: float = 0.0

class Group:
	var id: int
	var event: StringName
	var arrival: float
	var envelope: float = 0.0
	var priority: float = 0.0
	var member_count: int = 0

class Voice:
	var player: AudioStreamPlayer
	var group_id: int = 0
	var envelope: float = 0.0
	var event: StringName

var sources: Dictionary[int, Source] = {}
var groups: Dictionary[int, Group] = {}
var voices: Array[Voice] = []
var next_group_id: int = 1
var simulation_clock: float = 0.0

static func all_streams() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for stream: AudioStreamOggVorbis in STREAMS.values():
		stream.loop = true
		result.append(stream)
	for event: StringName in STREAMS:
		result.append(entry_stream(event))
	return result

static func entry_stream(event: StringName) -> AudioStreamOggVorbis:
	if not _entry_streams.has(event):
		var stream := (STREAMS[event] as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		stream.loop = false
		_entry_streams[event] = stream
	return _entry_streams[event]

func _ready() -> void:
	all_streams()
	for index: int in MAX_VOICES:
		var voice := Voice.new()
		voice.player = AudioStreamPlayer.new()
		voice.player.name = "UavLoop%d" % index
		voice.player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if CombatAudio.uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(voice.player)
		voice.player.finished.connect(_finish_entry.bind(voice))
		voices.append(voice)

func _finish_entry(voice: Voice) -> void:
	if voice.group_id == 0 or voice.player.stream != entry_stream(voice.event):
		return
	# Web Sample loops reuse play()'s offset. Only the first pass may seek.
	voice.player.stream = STREAMS[voice.event]
	voice.player.play(0.0)

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
		# Reapplying resume recreates the WebAudio Sample at its start offset.
		if voice.player.stream_paused != paused:
			voice.player.stream_paused = paused
		voice.player.pitch_scale = maxf(0.01, rate)
	if paused:
		return
	var simulation_delta := delta * rate
	simulation_clock += simulation_delta
	_refresh_groups(simulation_delta)
	var selected := _select_groups()
	# Fade old owners out before reusing their physical slot; never exceed the cap.
	for voice: Voice in voices:
		if voice.group_id == 0:
			continue
		var group := groups.get(voice.group_id) as Group
		var target := group.envelope if group != null and selected.has(group.id) else 0.0
		voice.envelope = move_toward(voice.envelope, target, delta / FADE_SECONDS)
		voice.player.volume_linear = voice.envelope * db_to_linear(float(GAINS_DB[voice.event]))
		if target == 0.0 and voice.envelope <= 0.0:
			voice.player.stop()
			voice.player.stream = null
			voice.group_id = 0
	for id: int in selected:
		if _has_voice(id):
			continue
		var group := groups[id]
		if _event_voice_count(group.event) >= MAX_PER_EVENT:
			continue
		for voice: Voice in voices:
			if voice.group_id != 0:
				continue
			voice.group_id = id
			voice.event = group.event
			voice.envelope = minf(group.envelope, delta / FADE_SECONDS)
			voice.player.stream = entry_stream(group.event) if CombatAudio.uses_sample_playback() else STREAMS[group.event]
			voice.player.volume_linear = voice.envelope * db_to_linear(float(GAINS_DB[group.event]))
			# Re-entry follows the running loop phase, not a replay of an approach cue.
			voice.player.play(fposmod(simulation_clock, voice.player.stream.get_length()))
			break

func _refresh_groups(delta: float) -> void:
	for group: Group in groups.values():
		group.envelope = 0.0
		group.member_count = 0
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
		if source.group_id == 0 and source.envelope > 0.0:
			source.group_id = _join_group(source.event, simulation_clock + seconds)
		var group := groups.get(source.group_id) as Group
		if group != null:
			group.member_count += 1
			group.envelope = maxf(group.envelope, source.envelope)
	for id: int in groups.keys():
		var group := groups[id]
		if group.member_count == 0:
			groups.erase(id)
		else:
			# Compare calibrated loudness, not raw file gain or a voice's fade-in.
			group.priority = group.envelope * (db_to_linear(-4.0) if group.event == LIGHT else 1.0)

func _join_group(event: StringName, arrival: float) -> int:
	for group: Group in groups.values():
		if group.event == event and absf(group.arrival - arrival) <= GROUP_WINDOW:
			return group.id
	var group := Group.new()
	group.id = next_group_id
	next_group_id += 1
	group.event = event
	group.arrival = arrival
	groups[group.id] = group
	return group.id

func _select_groups() -> Array[int]:
	var candidates: Array[Group] = []
	for group: Group in groups.values():
		if group.priority > 0.0:
			candidates.append(group)
	candidates.sort_custom(func(a: Group, b: Group) -> bool:
		var left := a.priority * (HOLD_BONUS if _has_voice(a.id) else 1.0)
		var right := b.priority * (HOLD_BONUS if _has_voice(b.id) else 1.0)
		return left > right if not is_equal_approx(left, right) else a.id < b.id)
	var selected: Array[int] = []
	var counts: Dictionary[StringName, int] = {}
	for group: Group in candidates:
		if selected.size() >= MAX_VOICES:
			break
		if counts.get(group.event, 0) >= MAX_PER_EVENT:
			continue
		selected.append(group.id)
		counts[group.event] = counts.get(group.event, 0) + 1
	return selected

func _has_voice(id: int) -> bool:
	for voice: Voice in voices:
		if voice.group_id == id:
			return true
	return false

func _event_voice_count(event: StringName) -> int:
	var count := 0
	for voice: Voice in voices:
		if voice.group_id != 0 and voice.event == event:
			count += 1
	return count

func reset() -> void:
	for voice: Voice in voices:
		voice.player.stop()
		voice.player.stream = null
		voice.player.stream_paused = false
		voice.group_id = 0
		voice.envelope = 0.0
	sources.clear()
	groups.clear()
	simulation_clock = 0.0
