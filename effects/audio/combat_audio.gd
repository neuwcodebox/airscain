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
const MAX_AUDIBLE_MISSILE_GROUPS := 4
const MISSILE_GROUP_WINDOW := 0.1
const MISSILE_MIX_BUDGET := 1.0
const MISSILE_VOICE_GAIN := 0.75

class MissileGroup:
	var event_id: StringName
	var opened_at: float
	var members: Array[int] = []

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
var missile_players: Array[AudioStreamPlayer] = []
var missile_gains: Dictionary[int, float] = {}
var source_players: Dictionary[int, AudioStreamPlayer] = {}
var missile_groups: Dictionary[int, MissileGroup] = {}
var missile_clock: float = 0.0
var fade_tweens: Dictionary[int, Tween] = {}
var fade_generations: Dictionary[int, int] = {}
var next_fade_generation: int = 1
var next_player_index: int = 0
var rng := RandomNumberGenerator.new()
var prepared_stream_count: int = 0
@export var enabled: bool = true
var simulation_paused: bool = false
var simulation_rate: float = 1.0
var cruise_approaches: ThreatApproachAudio
var approaches: ThreatApproachAudio
var gun_airbursts: GunAirburstAudio
var gun_voices: Dictionary[int, GunAudio] = {}
const GUN_MIX_BUDGET := 1.8
const GUN_VOICE_GAIN := 0.75
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
	var gain := minf(GUN_VOICE_GAIN, GUN_MIX_BUDGET / maxf(1.0, selected.size()))
	for voice: GunAudio in gun_voices.values():
		voice.set_mix_gain(gain)
		voice.set_audible(selected.has(voice))

func _ready() -> void:
	if not enabled:
		return
	prepared_stream_count = prepare_samples()
	approaches = ThreatApproachAudio.new()
	approaches.name = "ThreatApproaches"
	add_child(approaches)
	cruise_approaches = ThreatApproachAudio.new()
	cruise_approaches.configure_cruise()
	cruise_approaches.name = "CruiseApproaches"
	add_child(cruise_approaches)
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
	# Launches cannot steal alert/explosion voices or cut off another missile.
	for index: int in MAX_AUDIBLE_MISSILE_GROUPS:
		var player := AudioStreamPlayer.new()
		player.name = "MissileVoice%d" % index
		player.bus = &"Missiles"
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		missile_players.append(player)
		player.finished.connect(_on_missile_voice_finished.bind(player))

static func all_streams() -> Array[AudioStream]:
	var streams: Array[AudioStream] = GunAudio.all_streams()
	streams.append(GunAirburstAudio.loop_stream())
	streams.append_array(ThreatApproachAudio.all_streams())
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
	if is_instance_valid(cruise_approaches):
		cruise_approaches.update_audio(delta, simulation_paused, simulation_rate, enabled)
	if is_instance_valid(approaches):
		approaches.update_audio(delta, simulation_paused, simulation_rate, enabled)
	if not simulation_paused:
		missile_clock += delta
	for event_id: StringName in cooldowns.keys():
		cooldowns[event_id] = maxf(0.0, cooldowns[event_id] - delta)
	_refresh_missile_mix(delta)

func _refresh_missile_mix(delta: float = 0.0) -> void:
	var fading_gain := 0.0
	var requested_gain := 0.0
	for player: AudioStreamPlayer in missile_players:
		if fade_tweens.has(player.get_instance_id()):
			fading_gain += player.volume_linear
		elif player.playing:
			requested_gain += float(missile_gains.get(player.get_instance_id(), 0.0))
	var scale := minf(1.0, maxf(0.0, MISSILE_MIX_BUDGET - fading_gain) / maxf(0.0001, requested_gain))
	for player: AudioStreamPlayer in missile_players:
		if not player.playing or fade_tweens.has(player.get_instance_id()):
			continue
		var target := float(missile_gains.get(player.get_instance_id(), 0.0)) * scale
		# Reduce immediately to preserve the budget; recover gently as voices retire.
		player.volume_linear = minf(target, player.volume_linear + delta * 0.8)

func _on_missile_voice_finished(player: AudioStreamPlayer) -> void:
	_cancel_player_fade(player)
	_release_missile_group(player)
	missile_gains.erase(player.get_instance_id())
	player.stream = null

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	if is_instance_valid(cruise_approaches):
		cruise_approaches.reset()
	if is_instance_valid(approaches):
		approaches.reset()
	if is_instance_valid(gun_airbursts):
		gun_airbursts.reset()
	for player: AudioStreamPlayer in players + missile_players:
		_cancel_player_fade(player)
		player.stop()
		player.stream = null
	source_players.clear()
	missile_groups.clear()
	missile_gains.clear()

func register_threat(threat: ThreatUnit) -> void:
	if is_instance_valid(cruise_approaches):
		cruise_approaches.register(threat)
	if is_instance_valid(approaches):
		approaches.register(threat)

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
	if not enabled or not is_instance_valid(source) or event_id not in MISSILE_EVENTS:
		return false
	var source_id := source.get_instance_id()
	var exiting := _on_source_tree_exiting.bind(source_id)
	if source.tree_exiting.is_connected(exiting):
		return false
	# Suppressed launches still produce their own eventual impact event.
	var ended := _on_source_flight_ended.bind(source_id)
	if source.has_signal("flight_ended") and not source.is_connected("flight_ended", ended):
		source.connect("flight_ended", ended, CONNECT_ONE_SHOT)
	source.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)
	# Join only within the fixed window from the first launch, without restarting.
	for candidate: AudioStreamPlayer in missile_players:
		var group := missile_groups.get(candidate.get_instance_id()) as MissileGroup
		if group != null and candidate.playing and group.event_id == event_id and missile_clock - group.opened_at < MISSILE_GROUP_WINDOW:
			group.members.append(source_id)
			source_players[source_id] = candidate
			return true
	var player: AudioStreamPlayer
	for candidate: AudioStreamPlayer in missile_players:
		if not candidate.playing and not fade_tweens.has(candidate.get_instance_id()):
			player = candidate
			break
	if player == null:
		return false
	_release_missile_group(player)
	var choices: Array = STREAM_GROUPS[event_id]
	player.stream = choices[rng.randi_range(0, choices.size() - 1)] as AudioStream
	var gain := MISSILE_VOICE_GAIN * clampf(intensity, 0.15, 1.0)
	missile_gains[player.get_instance_id()] = gain
	player.volume_linear = gain
	player.play()
	_refresh_missile_mix()
	event_counts[event_id] = event_counts.get(event_id, 0) + 1
	last_stream_paths[event_id] = player.stream.resource_path
	source_players[source_id] = player
	var group := MissileGroup.new()
	group.event_id = event_id
	group.opened_at = missile_clock
	group.members.append(source_id)
	missile_groups[player.get_instance_id()] = group
	return true

func _play_stream(event_id: StringName, intensity: float) -> AudioStreamPlayer:
	if event_id in MISSILE_EVENTS or not enabled or not STREAM_GROUPS.has(event_id) or players.is_empty():
		return null
	var choices: Array = STREAM_GROUPS[event_id]
	var stream := choices[rng.randi_range(0, choices.size() - 1)] as AudioStream
	var player := _available_player()
	_cancel_player_fade(player)
	player.stream = stream
	player.bus = &"Alerts" if event_id in [CONTACT, PRESSURE, LOW_AMMO] else &"Explosions"
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

func _release_missile_group(player: AudioStreamPlayer) -> void:
	var player_id := player.get_instance_id()
	var group := missile_groups.get(player_id) as MissileGroup
	if group == null:
		return
	for source_id: int in group.members:
		source_players.erase(source_id)
	missile_groups.erase(player_id)

func _on_source_flight_ended(detonated: bool, source_id: int) -> void:
	_retire_missile_source(source_id, DETONATION_FADE_SECONDS if detonated else RETIRE_FADE_SECONDS)
	if detonated:
		play_event(EXPLOSION)

func _on_source_tree_exiting(source_id: int) -> void:
	_retire_missile_source(source_id, RETIRE_FADE_SECONDS)

func _retire_missile_source(source_id: int, duration: float) -> void:
	var player := source_players.get(source_id) as AudioStreamPlayer
	if player == null:
		return
	var player_id := player.get_instance_id()
	source_players.erase(source_id)
	var group := missile_groups.get(player_id) as MissileGroup
	if group == null:
		return
	group.members.erase(source_id)
	if not group.members.is_empty():
		return
	missile_groups.erase(player_id)
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
	missile_gains.erase(player_id)
	fade_tweens.erase(player_id)
	fade_generations.erase(player_id)

func _cancel_player_fade(player: AudioStreamPlayer) -> void:
	var player_id := player.get_instance_id()
	var tween := fade_tweens.get(player_id) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	fade_tweens.erase(player_id)
	fade_generations.erase(player_id)

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
