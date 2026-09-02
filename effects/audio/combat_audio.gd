class_name CombatAudio
extends Node

const CONTACT := &"contact"
const LAUNCH := &"launch"
const LOW_AMMO := &"low_ammo"
const DAMAGE := &"damage"
const PRESSURE := &"pressure"
const EXPLOSION := &"explosion"
const MIX_RATE := 16000

var streams: Dictionary[StringName, AudioStreamWAV] = {}
var cooldowns: Dictionary[StringName, float] = {}
var event_counts: Dictionary[StringName, int] = {}
var players: Array[AudioStreamPlayer] = []
var next_player_index: int = 0
@export var enabled: bool = false

func _ready() -> void:
	if not enabled:
		return
	_build_streams()
	for index: int in 8:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % index
		add_child(player)
		players.append(player)

func _process(delta: float) -> void:
	for event_id: StringName in cooldowns.keys():
		cooldowns[event_id] = maxf(0.0, cooldowns[event_id] - delta)

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	for player: AudioStreamPlayer in players:
		player.stop()
		player.stream = null
	streams.clear()

func play_event(event_id: StringName, intensity: float = 1.0) -> bool:
	if not enabled or not streams.has(event_id) or float(cooldowns.get(event_id, 0.0)) > 0.0 or players.is_empty():
		return false
	var player := _available_player()
	player.stream = streams[event_id]
	player.volume_db = linear_to_db(clampf(intensity, 0.15, 1.0))
	player.play()
	cooldowns[event_id] = _event_cooldown(event_id)
	event_counts[event_id] = event_counts.get(event_id, 0) + 1
	return true

func played_count(event_id: StringName) -> int:
	return int(event_counts.get(event_id, 0))

func _available_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in players:
		if not player.playing:
			return player
	var player := players[next_player_index]
	next_player_index = (next_player_index + 1) % players.size()
	return player

func _event_cooldown(event_id: StringName) -> float:
	match event_id:
		CONTACT:
			return 0.45
		LAUNCH:
			return 0.08
		LOW_AMMO:
			return 2.5
		DAMAGE:
			return 0.55
		PRESSURE:
			return 1.0
		EXPLOSION:
			return 0.12
	return 0.1

func _build_streams() -> void:
	streams[CONTACT] = _make_sound([880.0, 1170.0], 0.16, 0.0, 0.0)
	streams[LAUNCH] = _make_sound([155.0, 92.0], 0.24, 0.42, 0.0)
	streams[LOW_AMMO] = _make_sound([620.0, 390.0, 620.0], 0.32, 0.0, 7.0)
	streams[DAMAGE] = _make_sound([125.0, 68.0], 0.38, 0.68, 0.0)
	streams[PRESSURE] = _make_sound([440.0, 660.0, 880.0], 0.42, 0.05, 9.0)
	streams[EXPLOSION] = _make_sound([82.0, 46.0], 0.46, 0.82, 0.0)

func _make_sound(frequencies: Array[float], duration: float, noise_mix: float, pulse_rate: float) -> AudioStreamWAV:
	var sample_count := roundi(duration * float(MIX_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index: int in sample_count:
		var time := float(index) / float(MIX_RATE)
		var segment := mini(frequencies.size() - 1, int(time / duration * float(frequencies.size())))
		var frequency := frequencies[segment]
		var tone := sin(TAU * frequency * time) * 0.72 + sin(TAU * frequency * 2.02 * time) * 0.18
		var noise := sin(float(index * 173 + 19) * 12.9898) * 0.5 + sin(float(index * 71 + 7) * 4.1414) * 0.5
		var envelope := minf(1.0, time / 0.012) * minf(1.0, (duration - time) / 0.055)
		var pulse := 1.0 if pulse_rate <= 0.0 else 0.42 + 0.58 * maxf(0.0, sin(TAU * pulse_rate * time))
		var sample := clampi(roundi(lerpf(tone, noise, noise_mix) * envelope * pulse * 24500.0), -32768, 32767)
		data[index * 2] = sample & 0xff
		data[index * 2 + 1] = (sample >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
