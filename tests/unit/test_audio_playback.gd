extends GutTest

func test_shared_player_clock_applies_rate_and_preserves_pause() -> void:
	var player := AudioPlayback.create_player()
	add_child_autofree(player)
	assert_eq(player.playback_type, AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM)
	player.stream = preload("res://enemy/attack_uav/audio/plane_loop_medium_1.ogg")
	player.play(1.0)
	AudioPlayback.sync(player, true, 4.0)
	assert_true(player.stream_paused)
	assert_eq(player.pitch_scale, 4.0)
	var position := player.get_playback_position()
	for frame: int in 10:
		AudioPlayback.sync(player, true, 2.0)
	await wait_seconds(0.1)
	assert_almost_eq(player.get_playback_position(), position, 0.01)
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
