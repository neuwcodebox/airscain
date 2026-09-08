class_name ThreatApproachAudio
extends Node
## Bounded approach cues; audio never controls flight or weapon release.

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

const CRUISE_EVENT := &"missile_approach"
const CRUISE_STREAMS: Array[AudioStream] = [
	preload("res://enemy/cruise_missile/audio/missile_approach_1.ogg"),
	preload("res://enemy/cruise_missile/audio/missile_approach_2.ogg"),
]

var event: StringName = EVENT
var lead_seconds: float = PEAK_SECONDS
var start_interval: float = START_INTERVAL
var retire_seconds: float = RETIRE_SECONDS
var grouped: bool = false
var streams: Array[AudioStream] = STREAMS
var gains_db: Array[float] = GAINS_DB
var clock: float = 0.0

func configure_cruise() -> void:
	event = CRUISE_EVENT
	lead_seconds = 5.0
	start_interval = CombatAudio.MISSILE_GROUP_WINDOW
	retire_seconds = CombatAudio.DETONATION_FADE_SECONDS
	grouped = true
	streams = CRUISE_STREAMS
	# Originals measure -18.06/-17.68 LUFS; preserve envelopes at -26 LUFS.
	gains_db = [-7.94, -8.32]

class Voice:
	var player: AudioStreamPlayer
	var source_id: int = 0
	var members: Array[int] = []
	var opened_at: float = 0.0
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
	var result := STREAMS.duplicate()
	result.append_array(CRUISE_STREAMS)
	return result

func _ready() -> void:
	for index: int in MAX_VOICES:
		var voice := Voice.new()
		voice.player = AudioPlayback.create_player()
		voice.player.name = "Flyover%d" % index
		add_child(voice.player)
		voices.append(voice)

func register(threat: ThreatUnit) -> void:
	if threat.definition.approach_audio_event != event:
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
		AudioPlayback.sync(voice.player, paused)
	if paused:
		return
	clock += delta
	cooldown = maxf(0.0, cooldown - delta)
	for voice: Voice in voices:
		if voice.retiring:
			voice.fade_remaining = maxf(0.0, voice.fade_remaining - delta * rate)
			voice.player.volume_linear = voice.gain * voice.fade_remaining / retire_seconds
			if voice.fade_remaining <= 0.0:
				voice.player.stop()
				voice.retiring = false
		if not voice.player.playing:
			voice.source_id = 0
			voice.members.clear()
			voice.player.stream = null
	for id: int in threats:
		var threat := threats[id]
		var seconds := threat.presentation_action_seconds()
		if attempted.has(id):
			if threat.exits_without_impact() and not threat.presentation_action_completed():
				retire(id)
			continue
		if not is_finite(seconds) or seconds < 0.0 or seconds > lead_seconds:
			continue
		# Crowded cues are dropped once, never queued for a late replay.
		attempted[id] = true
		var joined := false
		if grouped:
			for voice: Voice in voices:
				if voice.player.playing and not voice.retiring and clock - voice.opened_at < start_interval:
					voice.members.append(id)
					joined = true
					break
		if joined or cooldown > 0.0:
			continue
		for voice: Voice in voices:
			if voice.player.playing or voice.retiring:
				continue
			voice.source_id = id
			voice.members.assign([id])
			voice.opened_at = clock
			voice.gain = db_to_linear(gains_db[next_variant])
			voice.player.volume_linear = voice.gain
			voice.player.stream = streams[next_variant]
			# Late spawns/restores enter at the corresponding approach position.
			AudioPlayback.play(voice.player, lead_seconds - seconds)
			next_variant = (next_variant + 1) % streams.size()
			cooldown = start_interval
			played_count += 1
			break

func retire(id: int) -> void:
	for voice: Voice in voices:
		if grouped:
			if not voice.members.has(id):
				continue
			voice.members.erase(id)
			if not voice.members.is_empty():
				continue
		if (grouped or voice.source_id == id) and voice.player.playing and not voice.retiring:
			voice.retiring = true
			voice.fade_remaining = retire_seconds

func _on_resolved(_threat: ThreatUnit, neutralized: bool, _reward: int, id: int) -> void:
	if grouped or neutralized:
		retire(id)

func _on_exiting(id: int) -> void:
	var threat := threats.get(id) as ThreatUnit
	if grouped or is_instance_valid(threat) and not threat.presentation_action_completed():
		retire(id)
	threats.erase(id)
	attempted.erase(id)

func reset() -> void:
	for voice: Voice in voices:
		voice.player.stop()
		voice.player.stream = null
		voice.player.stream_paused = false
		voice.source_id = 0
		voice.members.clear()
		voice.retiring = false
	threats.clear()
	attempted.clear()
	cooldown = 0.0
