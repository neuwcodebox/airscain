extends GutTest

class FlightSource:
	extends Node
	signal flight_ended(detonated: bool)

func test_shared_player_applies_rate_without_changing_requested_pause() -> void:
	var player := AudioPlayback.create_player()
	add_child_autofree(player)
	assert_eq(player.playback_type, AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM)
	player.stream = preload("res://enemy/attack_uav/audio/plane_loop_medium_1.ogg")
	AudioPlayback.play(player, 1.0)
	AudioPlayback.sync(player, true, 4.0)
	assert_true(player.stream_paused)
	assert_eq(player.pitch_scale, 4.0)
	AudioPlayback.sync(player, true, 2.0)
	assert_true(player.stream_paused)
	assert_eq(player.pitch_scale, 2.0)
	AudioPlayback.sync(player, false, 2.0)
	assert_false(player.stream_paused)
	assert_true(player.playing)
	assert_eq(player.pitch_scale, 2.0)
	player.stop()

func test_shared_tween_stays_frozen_while_paused_and_completes_after_resume() -> void:
	var player := add_child_autofree(AudioPlayback.create_player()) as AudioStreamPlayer
	player.volume_linear = 1.0
	var tween := create_tween()
	tween.tween_property(player, "volume_linear", 0.0, 0.1)
	AudioPlayback.sync_tween(tween, true)
	assert_false(tween.is_running())
	assert_almost_eq(player.volume_linear, 1.0, 0.001)
	await get_tree().process_frame
	assert_almost_eq(player.volume_linear, 1.0, 0.001, "정지된 tween은 다음 engine frame에도 변하지 않습니다")
	AudioPlayback.sync_tween(tween, true)
	assert_false(tween.is_running())
	AudioPlayback.sync_tween(tween, false)
	assert_true(tween.is_running())
	tween.custom_step(0.2)
	assert_almost_eq(player.volume_linear, 0.0, 0.001)
	assert_false(tween.is_running())
	await get_tree().process_frame
	AudioPlayback.sync_tween(tween, false)
	assert_almost_eq(player.volume_linear, 0.0, 0.001, "완료한 tween을 다시 동기화해도 최종값을 유지합니다")
	assert_false(tween.is_running(), "완료한 tween은 재개되지 않습니다")

func test_combat_pause_pauses_active_voices_and_new_retirement_fades() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	var source := add_child_autofree(FlightSource.new()) as FlightSource
	assert_true(context.play_missile_event(CombatAudio.LONG_MISSILE, source))
	assert_true(context.play_event(CombatAudio.EXPLOSION))
	var event_path := context.last_stream_path(CombatAudio.EXPLOSION)
	context.simulation_paused = true
	_advance_combat_audio(context, 0.1)
	var missile := context.source_players[source.get_instance_id()] as AudioStreamPlayer
	var event_voice := _player_with_stream_path(context.players, event_path)
	assert_not_null(event_voice)
	assert_true(missile.stream_paused)
	assert_true(event_voice.stream_paused)
	source.flight_ended.emit(false)
	var gain := missile.volume_linear
	var fade := context.fade_tweens[missile.get_instance_id()] as Tween
	assert_false(fade.is_running(), "정지 중 시작된 비행 종료 감쇠는 즉시 정지합니다")
	await get_tree().process_frame
	assert_not_null(missile.stream, "정지 중에는 비행 종료 voice를 해제하지 않습니다")
	assert_true(context.fade_tweens.has(missile.get_instance_id()))
	assert_almost_eq(missile.volume_linear, gain, 0.001)
	context.simulation_paused = false
	_advance_combat_audio(context, 0.1)
	assert_false(missile.stream_paused)
	assert_true(fade.is_running())
	fade.custom_step(CombatAudio.RETIRE_FADE_SECONDS + 0.1)
	assert_false(missile.playing)
	assert_true(context.fade_tweens.is_empty())

func test_signal_less_source_tree_exit_retires_missile_voice() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	var source := Node.new()
	add_child(source)
	var source_id := source.get_instance_id()
	assert_true(context.play_missile_event(CombatAudio.LONG_MISSILE, source))
	var missile := context.source_players[source_id] as AudioStreamPlayer
	context.simulation_paused = true
	_advance_combat_audio(context, 0.0)
	source.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(source), "signal 없는 source가 scene tree에서 제거됩니다")
	assert_false(context.source_players.has(source_id), "tree_exiting이 source 소유권을 해제합니다")
	var fade := context.fade_tweens.get(missile.get_instance_id()) as Tween
	assert_not_null(fade, "마지막 source 제거는 미사일 voice 퇴역 감쇠를 시작합니다")
	if fade == null:
		return
	assert_false(fade.is_running(), "정지 중 생성된 퇴역 감쇠는 진행하지 않습니다")
	context.simulation_paused = false
	_advance_combat_audio(context, 0.0)
	assert_true(fade.is_running())
	fade.custom_step(CombatAudio.RETIRE_FADE_SECONDS + 0.1)
	assert_false(missile.playing)
	assert_true(context.fade_tweens.is_empty())

func test_operation_cleanup_stops_gun_loops_and_releases_owners() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var gun := add_child_autofree(GunAudio.new()) as GunAudio
	gun.context = context
	gun.notify_shot()
	_advance_gun_audio(gun, 0.02)
	assert_true(gun.playing)
	context.stop_all()
	assert_false(gun.playing)
	assert_false(gun.ending_player.playing)
	assert_false(gun.firing)
	assert_true(context.gun_voices.is_empty())

func _player_with_stream_path(players: Array[AudioStreamPlayer], stream_path: String) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in players:
		if player.stream != null and player.stream.resource_path == stream_path:
			return player
	return null


func test_loop_region_preserves_resource_time_precision() -> void:
	var gun := AudioPlayback.loop_region(GunAudio.sustain_stream())
	assert_eq(gun["begin"], GunAudio.LOOP_START_SECONDS)
	assert_eq(gun["end"], GunAudio.sustain_stream().get_length())
	var one_shot := AudioPlayback.loop_region(ThreatApproachAudio.STREAMS[0])
	assert_lt(one_shot["begin"], 0.0)

func _advance_combat_audio(context: CombatAudio, delta: float) -> void:
	# Drive the engine callback deterministically without waiting on wall-clock audio.
	context._process(delta)

func _advance_gun_audio(gun: GunAudio, delta: float) -> void:
	# Gun envelopes use gameplay delta, so direct advancement is the stable boundary.
	gun._process(delta)
