class_name CombatAudio
extends Node

const CONTACT := &"contact"
const PRESSURE := &"pressure"
const LOW_AMMO := &"low_ammo"
const DAMAGE := &"damage"
const BIG_EXPLOSION := &"big_explosion"
const EXPLOSION := &"explosion"
const LONG_MISSILE := &"long_missile"
const MISSILE := &"missile"
const SHORT_MISSILE := &"short_missile"
const MISSILE_EVENTS: Array[StringName] = [LONG_MISSILE, MISSILE, SHORT_MISSILE]
const DETONATION_FADE_SECONDS := 0.12
const RETIRE_FADE_SECONDS := 0.25
const FADE_FLOOR_DB := -40.0

const STREAM_GROUPS: Dictionary = {
	CONTACT: [
		preload("res://effects/audio/combat/contact.ogg"),
	],
	PRESSURE: [
		preload("res://effects/audio/combat/pressure.ogg"),
	],
	LOW_AMMO: [
		preload("res://effects/audio/combat/low_ammo.ogg"),
	],
	DAMAGE: [
		preload("res://effects/audio/combat/small_explosion_1.ogg"),
		preload("res://effects/audio/combat/small_explosion_2.ogg"),
		preload("res://effects/audio/combat/small_explosion_3.ogg"),
	],
	BIG_EXPLOSION: [
		preload("res://effects/audio/combat/big_explosion_1.ogg"),
		preload("res://effects/audio/combat/big_explosion_2.ogg"),
		preload("res://effects/audio/combat/big_explosion_3.ogg"),
		preload("res://effects/audio/combat/big_explosion_4.ogg"),
	],
	EXPLOSION: [
		preload("res://effects/audio/combat/explosion_1.ogg"),
		preload("res://effects/audio/combat/explosion_2.ogg"),
		preload("res://effects/audio/combat/explosion_3.ogg"),
		preload("res://effects/audio/combat/explosion_4.ogg"),
		preload("res://effects/audio/combat/explosion_5.ogg"),
	],
	LONG_MISSILE: [
		preload("res://effects/audio/combat/long_missile_1.ogg"),
		preload("res://effects/audio/combat/long_missile_2.ogg"),
		preload("res://effects/audio/combat/long_missile_3.ogg"),
	],
	MISSILE: [
		preload("res://effects/audio/combat/missile_1.ogg"),
		preload("res://effects/audio/combat/missile_2.ogg"),
	],
	SHORT_MISSILE: [
		preload("res://effects/audio/combat/short_missile_1.ogg"),
	],
}

var cooldowns: Dictionary[StringName, float] = {}
var event_counts: Dictionary[StringName, int] = {}
var last_stream_paths: Dictionary[StringName, String] = {}
var players: Array[AudioStreamPlayer] = []
var source_players: Dictionary[int, AudioStreamPlayer] = {}
var player_source_ids: Dictionary[int, int] = {}
var fade_tweens: Dictionary[int, Tween] = {}
var fade_generations: Dictionary[int, int] = {}
var next_fade_generation: int = 1
var next_player_index: int = 0
var rng := RandomNumberGenerator.new()
var prepared_stream_count: int = 0
@export var enabled: bool = true
var simulation_paused: bool = false
var gun_airbursts: GunAirburstAudio
var gun_voices: Dictionary[int, GunAudio] = {}
const GUN_MIX_BUDGET := 0.65
const MAX_AUDIBLE_GUNS := 4

func register_gun_voice(voice: GunAudio) -> void:
	gun_voices[voice.get_instance_id()] = voice
	refresh_gun_mix()

func unregister_gun_voice(voice: GunAudio) -> void:
	if gun_voices.erase(voice.get_instance_id()):
		refresh_gun_mix()

func refresh_gun_mix() -> void:
	var selected: Array[GunAudio] = []
	# Keep ongoing representatives stable; only fill vacancies or replace tails.
	for voice: GunAudio in gun_voices.values():
		if voice.audible and voice.firing and selected.size() < MAX_AUDIBLE_GUNS:
			selected.append(voice)
	for voice: GunAudio in gun_voices.values():
		if voice.firing and not selected.has(voice) and selected.size() < MAX_AUDIBLE_GUNS:
			selected.append(voice)
	for voice: GunAudio in gun_voices.values():
		if not selected.has(voice) and selected.size() < MAX_AUDIBLE_GUNS:
			selected.append(voice)
	var gain := minf(0.25, GUN_MIX_BUDGET / maxf(1.0, selected.size()))
	for voice: GunAudio in gun_voices.values():
		voice.set_mix_gain(gain)
		voice.set_audible(selected.has(voice))

func _ready() -> void:
	if not enabled:
		return
	prepared_stream_count = prepare_samples()
	gun_airbursts = GunAirburstAudio.new()
	gun_airbursts.name = "GunAirbursts"
	gun_airbursts.context = self
	add_child(gun_airbursts)
	rng.randomize()
	for index: int in 8:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % index
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		players.append(player)

static func all_streams() -> Array[AudioStream]:
	var streams: Array[AudioStream] = GunAudio.all_streams()
	streams.append(GunAirburstAudio.loop_stream())
	for group: Array in STREAM_GROUPS.values():
		for candidate: Variant in group:
			var stream := candidate as AudioStream
			if stream != null and stream not in streams:
				streams.append(stream)
	return streams

static func prepare_samples() -> int:
	if not uses_sample_playback():
		return 0
	var streams := all_streams()
	for stream: AudioStream in streams:
		if not AudioServer.is_stream_registered_as_sample(stream):
			AudioServer.register_stream_as_sample(stream)
	return streams.size()

static func uses_sample_playback() -> bool:
	return OS.has_feature("web")

func _process(delta: float) -> void:
	for event_id: StringName in cooldowns.keys():
		cooldowns[event_id] = maxf(0.0, cooldowns[event_id] - delta)

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	if is_instance_valid(gun_airbursts):
		gun_airbursts.reset()
	for player: AudioStreamPlayer in players:
		_cancel_player_fade(player)
		player.stop()
		player.stream = null
	source_players.clear()
	player_source_ids.clear()

func on_gun_round_detonated(position: Vector3, reason: StringName) -> void:
	if is_instance_valid(gun_airbursts):
		gun_airbursts.notify_detonation(position, reason)

func play_event(event_id: StringName, intensity: float = 1.0) -> bool:
	if event_id in MISSILE_EVENTS or not enabled or not STREAM_GROUPS.has(event_id) or float(cooldowns.get(event_id, 0.0)) > 0.0 or players.is_empty():
		return false
	var player := _play_stream(event_id, intensity)
	if player == null:
		return false
	cooldowns[event_id] = _event_cooldown(event_id)
	return true

func play_missile_event(event_id: StringName, source: Node, intensity: float = 1.0) -> bool:
	if source == null or event_id not in MISSILE_EVENTS:
		return false
	var source_id := source.get_instance_id()
	if source_players.has(source_id):
		_stop_source(source_id)
	var player := _play_stream(event_id, intensity)
	if player == null:
		return false
	source_players[source_id] = player
	player_source_ids[player.get_instance_id()] = source_id
	if source.has_signal("flight_ended"):
		source.connect("flight_ended", _on_source_flight_ended.bind(source_id), CONNECT_ONE_SHOT)
	source.tree_exiting.connect(_on_source_tree_exiting.bind(source_id), CONNECT_ONE_SHOT)
	return true

func _play_stream(event_id: StringName, intensity: float) -> AudioStreamPlayer:
	if not enabled or not STREAM_GROUPS.has(event_id) or players.is_empty():
		return null
	var choices: Array = STREAM_GROUPS[event_id]
	var stream := choices[rng.randi_range(0, choices.size() - 1)] as AudioStream
	var player := _available_player()
	_cancel_player_fade(player)
	_release_player_source(player)
	player.stream = stream
	player.bus = &"Missiles" if event_id in MISSILE_EVENTS else &"Alerts" if event_id in [CONTACT, PRESSURE, LOW_AMMO] else &"Explosions"
	player.volume_db = linear_to_db(clampf(intensity, 0.15, 1.0))
	player.play()
	event_counts[event_id] = event_counts.get(event_id, 0) + 1
	last_stream_paths[event_id] = stream.resource_path
	return player

func played_count(event_id: StringName) -> int:
	return event_counts.get(event_id, 0)

func last_stream_path(event_id: StringName) -> String:
	return last_stream_paths.get(event_id, "")

func stream_count(event_id: StringName) -> int:
	if not STREAM_GROUPS.has(event_id):
		return 0
	return (STREAM_GROUPS[event_id] as Array).size()

func _available_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in players:
		if not player.playing:
			return player
	var player := players[next_player_index]
	next_player_index = (next_player_index + 1) % players.size()
	return player

func _release_player_source(player: AudioStreamPlayer) -> void:
	var player_id := player.get_instance_id()
	if not player_source_ids.has(player_id):
		return
	var source_id := player_source_ids[player_id]
	player_source_ids.erase(player_id)
	source_players.erase(source_id)

func _on_source_flight_ended(detonated: bool, source_id: int) -> void:
	_fade_source(source_id, DETONATION_FADE_SECONDS if detonated else RETIRE_FADE_SECONDS)
	if detonated:
		play_event(EXPLOSION)

func _on_source_tree_exiting(source_id: int) -> void:
	_fade_source(source_id, RETIRE_FADE_SECONDS)

func _fade_source(source_id: int, duration: float) -> void:
	var player := source_players.get(source_id) as AudioStreamPlayer
	if player == null:
		return
	var player_id := player.get_instance_id()
	if int(player_source_ids.get(player_id, 0)) != source_id:
		source_players.erase(source_id)
		return
	player_source_ids.erase(player_id)
	source_players.erase(source_id)
	_cancel_player_fade(player)
	var generation := next_fade_generation
	next_fade_generation += 1
	fade_generations[player_id] = generation
	var tween := create_tween()
	fade_tweens[player_id] = tween
	tween.tween_property(player, "volume_db", FADE_FLOOR_DB, duration)
	tween.tween_callback(_finish_player_fade.bind(player, generation))

func _finish_player_fade(player: AudioStreamPlayer, generation: int) -> void:
	if not is_instance_valid(player):
		return
	var player_id := player.get_instance_id()
	if int(fade_generations.get(player_id, 0)) != generation:
		return
	player.stop()
	player.stream = null
	fade_tweens.erase(player_id)
	fade_generations.erase(player_id)

func _cancel_player_fade(player: AudioStreamPlayer) -> void:
	var player_id := player.get_instance_id()
	var tween := fade_tweens.get(player_id) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	fade_tweens.erase(player_id)
	fade_generations.erase(player_id)

func _stop_source(source_id: int) -> void:
	var player := source_players.get(source_id) as AudioStreamPlayer
	if player == null:
		return
	var player_id := player.get_instance_id()
	if int(player_source_ids.get(player_id, 0)) == source_id:
		_cancel_player_fade(player)
		player.stop()
		player.stream = null
		player_source_ids.erase(player_id)
	source_players.erase(source_id)

func _event_cooldown(event_id: StringName) -> float:
	match event_id:
		CONTACT:
			return 0.45
		PRESSURE:
			return 1.0
		LOW_AMMO:
			return 2.5
		DAMAGE:
			return 0.55
		BIG_EXPLOSION:
			return 0.5
		EXPLOSION:
			return 0.12
	return 0.1
