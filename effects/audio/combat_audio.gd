class_name CombatAudio
extends Node

const BIG_EXPLOSION := &"big_explosion"
const EXPLOSION := &"explosion"
const LONG_MISSILE := &"long_missile"
const MISSILE := &"missile"
const SHORT_MISSILE := &"short_missile"
const MISSILE_EVENTS: Array[StringName] = [LONG_MISSILE, MISSILE, SHORT_MISSILE]

const STREAM_GROUPS: Dictionary = {
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
var next_player_index: int = 0
var rng := RandomNumberGenerator.new()
@export var enabled: bool = true

func _ready() -> void:
	if not enabled:
		return
	rng.randomize()
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
	source_players.clear()
	player_source_ids.clear()

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
	_release_player_source(player)
	player.stream = stream
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
	_stop_source(source_id)
	if detonated:
		play_event(EXPLOSION)

func _on_source_tree_exiting(source_id: int) -> void:
	_stop_source(source_id)

func _stop_source(source_id: int) -> void:
	var player := source_players.get(source_id) as AudioStreamPlayer
	if player == null:
		return
	var player_id := player.get_instance_id()
	if int(player_source_ids.get(player_id, 0)) == source_id:
		player.stop()
		player.stream = null
		player_source_ids.erase(player_id)
	source_players.erase(source_id)

func _event_cooldown(event_id: StringName) -> float:
	match event_id:
		BIG_EXPLOSION:
			return 0.5
		EXPLOSION:
			return 0.12
	return 0.1
