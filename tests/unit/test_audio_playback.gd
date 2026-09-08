extends GutTest

func test_shared_player_clock_applies_rate_and_preserves_pause() -> void:
	var player := AudioPlayback.create_player()
	add_child_autofree(player)
	assert_eq(player.playback_type, AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM)
	player.stream = preload("res://enemy/attack_uav/audio/plane_loop_medium_1.ogg")
	AudioPlayback.play(player, 1.0)
	AudioPlayback.sync(player, true, 4.0)
	assert_true(player.stream_paused)
	assert_eq(player.pitch_scale, 4.0)
	for frame: int in 10:
		AudioPlayback.sync(player, true, 2.0)
	await wait_seconds(0.1) # Allow the native mixer to consume pending commands.
	var position := player.get_playback_position()
	await wait_seconds(0.1)
	assert_almost_eq(player.get_playback_position(), position, 0.04) # Native pause may finish one mixer block at 2x.
	AudioPlayback.sync(player, false, 2.0)
	assert_false(player.stream_paused)
	assert_true(player.playing)
	assert_eq(player.pitch_scale, 2.0)
	player.stop()

func test_paused_fade_stays_frozen_then_completes_once() -> void:
	var player := add_child_autofree(AudioPlayback.create_player()) as AudioStreamPlayer
	player.volume_linear = 1.0
	var tween := create_tween()
	tween.tween_property(player, "volume_linear", 0.0, 0.1)
	AudioPlayback.sync_tween(tween, true)
	await wait_seconds(0.15)
	assert_almost_eq(player.volume_linear, 1.0, 0.001)
	AudioPlayback.sync_tween(tween, false)
	await wait_seconds(0.15)
	assert_almost_eq(player.volume_linear, 0.0, 0.001)
	AudioPlayback.sync_tween(tween, false)
	assert_almost_eq(player.volume_linear, 0.0, 0.001)

func test_combat_pause_freezes_launches_effects_and_retirement_fades() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	var source := add_child_autofree(Node.new()) as Node
	assert_true(context.play_missile_event(CombatAudio.LONG_MISSILE, source))
	assert_true(context.play_event(CombatAudio.EXPLOSION))
	context.simulation_paused = true
	context._process(0.1)
	var missile := context.missile_players[0]
	assert_true(missile.stream_paused)
	assert_true(context.players[0].stream_paused)
	await wait_seconds(0.05) # Let the native mixer consume the pause command.
	var position := missile.get_playback_position()
	context._on_source_tree_exiting(source.get_instance_id())
	var gain := missile.volume_linear
	await wait_seconds(0.35)
	assert_true(missile.stream_paused)
	assert_false(context.fade_tweens.is_empty(), "비행 종료 감쇠도 게임 정지 중에는 진행하지 않음")
	assert_almost_eq(missile.get_playback_position(), position, 0.02) # One native mixer block.
	assert_almost_eq(missile.volume_linear, gain, 0.001)
	context.simulation_paused = false
	context._process(0.1)
	await wait_seconds(0.35)
	assert_false(missile.playing)
	assert_true(context.fade_tweens.is_empty())
	context.stop_all()

func test_operation_cleanup_stops_gun_loops_and_releases_owners() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var gun := add_child_autofree(GunAudio.new()) as GunAudio
	gun.context = context
	gun.notify_shot()
	gun._process(0.02)
	assert_true(gun.playing)
	context.stop_all()
	assert_false(gun.playing)
	assert_false(gun.ending_player.playing)
	assert_false(gun.firing)
	assert_true(context.gun_voices.is_empty())


func test_loop_region_preserves_resource_time_precision() -> void:
	var gun := AudioPlayback.loop_region(GunAudio.sustain_stream())
	assert_almost_eq(gun["begin"], GunAudio.LOOP_START_SECONDS, 0.000000000001)
	assert_almost_eq(gun["end"], GunAudio.sustain_stream().get_length(), 0.000000000001)
	var one_shot := AudioPlayback.loop_region(ThreatApproachAudio.STREAMS[0])
	assert_lt(one_shot["begin"], 0.0)
