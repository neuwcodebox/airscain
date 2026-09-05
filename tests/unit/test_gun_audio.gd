extends GutTest

func test_all_guns_share_one_timed_airburst_voice() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var definition := preload("res://defense/close_in_gun/close_in_gun.tres")
	for index: int in 3:
		var gun := add_child_autofree(definition.scene.instantiate()) as CloseInGun
		gun.setup(index + 1, definition)
		gun.configure_audio(context)
		gun.configure_audio(context)
		for shell: int in 12:
			gun.gunfire.round_detonated.emit(Vector3.ZERO, &"timeout")
	assert_eq(context.gun_airbursts.starts, 1)
	assert_eq(context.find_children("GunAirbursts", "AudioStreamPlayer", false, false).size(), 1)
	assert_true(context.gun_airbursts.playing)
	var sound := context.gun_airbursts.stream as AudioStreamOggVorbis
	assert_true(sound.loop)
	assert_eq(sound.loop_offset, 0.0)
	assert_eq(sound.get_length(), GunAirburstAudio.SOUND.get_length(), "원본 앞뒤 무음과 길이를 보존합니다")

func test_airburst_layer_ignores_impacts_and_proximity_detonations() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	for reason: StringName in [&"surface", &"proximity", &""]:
		context.on_gun_round_detonated(Vector3.ZERO, reason)
	assert_eq(context.gun_airbursts.starts, 0)
	assert_false(context.gun_airbursts.playing)

func test_airburst_layer_bridges_gaps_and_recovers_fade_without_restarting() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := context.gun_airbursts
	voice.set_process(false)
	for index: int in 30:
		voice.notify_detonation(Vector3.ZERO, &"timeout")
		voice._process(0.1)
	assert_eq(voice.starts, 1)
	assert_gt(voice.gain, 0.0)
	voice._process(GunAirburstAudio.QUIET_GRACE - 0.01)
	assert_eq(voice.gain, GunAirburstAudio.LEVEL)
	voice._process(0.1)
	var fading_gain := voice.gain
	assert_gt(fading_gain, 0.0)
	assert_lt(fading_gain, GunAirburstAudio.LEVEL)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	voice._process(0.06)
	assert_gt(voice.gain, fading_gain)
	assert_eq(voice.starts, 1)
	voice._process(1.0)
	assert_false(voice.playing)
	assert_eq(voice.gain, 0.0)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	assert_eq(voice.starts, 2)

func test_airburst_pause_mute_reset_and_slow_frames() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := context.gun_airbursts
	voice.set_process(false)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	voice._process(0.4)
	assert_true(voice.playing, "새 자폭은 같은 프레임 지연만으로 종료되지 않습니다")
	context.simulation_paused = true
	voice._process(10.0)
	assert_true(voice.stream_paused)
	assert_eq(voice.quiet_remaining, GunAirburstAudio.QUIET_GRACE)
	context.simulation_paused = false
	voice._process(0.01)
	assert_false(voice.stream_paused)
	context.stop_all()
	assert_false(voice.playing)
	assert_eq(voice.quiet_remaining, 0.0)
	context.enabled = false
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	assert_false(voice.playing)
	var disabled := CombatAudio.new()
	disabled.enabled = false
	add_child_autofree(disabled)
	disabled.on_gun_round_detonated(Vector3.ZERO, &"timeout")
	assert_null(disabled.gun_airbursts, "메뉴처럼 비활성 상태로 시작하면 재생기를 만들지 않습니다")

func test_sequence_uses_mixer_transitions_and_a_native_loop() -> void:
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	var sequence := voice.stream as AudioStreamInteractive
	assert_eq(sequence.get_clip_auto_advance_next_clip(GunAudio.START), GunAudio.LOOP)
	assert_eq(sequence.get_clip_auto_advance(GunAudio.START), AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
	assert_true((sequence.get_clip_stream(GunAudio.LOOP) as AudioStreamOggVorbis).loop)
	assert_false((sequence.get_clip_stream(GunAudio.START) as AudioStreamOggVorbis).loop)
	assert_false((sequence.get_clip_stream(GunAudio.END) as AudioStreamOggVorbis).loop)
	assert_eq(sequence.get_transition_from_time(GunAudio.START, GunAudio.LOOP), AudioStreamInteractive.TRANSITION_FROM_TIME_END)
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 0)]:
		assert_eq(sequence.get_transition_fade_mode(pair.x, pair.y), AudioStreamInteractive.FADE_CROSS)

func test_shots_bridge_burst_gaps_and_resume_during_the_end_tail() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	voice.context = context
	voice.set_process(false)
	for shot: int in 100:
		voice.notify_shot()
		voice._process(0.04)
	assert_eq(voice.starts, 1)
	assert_eq(voice.endings, 0)
	assert_true(voice.firing)
	voice._process(0.2)
	assert_eq(voice.endings, 1)
	assert_false(voice.firing)
	assert_gt(voice.tail_remaining, 5.0)
	voice.notify_shot()
	assert_eq(voice.starts, 2)
	assert_true(voice.firing)
	assert_eq(voice.tail_remaining, 0.0)
	voice._process(0.0)
	voice._process(0.2)
	voice._process(6.0)
	assert_false(voice.playing)

func test_pause_mute_and_independent_guns() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var first := add_child_autofree(GunAudio.new()) as GunAudio
	var second := add_child_autofree(GunAudio.new()) as GunAudio
	for voice: GunAudio in [first, second]:
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
	context.simulation_paused = true
	first._process(2.0)
	assert_true(first.stream_paused)
	assert_eq(first.endings, 0)
	context.simulation_paused = false
	first._process(0.02)
	assert_false(first.stream_paused)
	first._process(0.2)
	assert_eq(first.endings, 1)
	assert_true(second.firing)
	context.enabled = false
	second._process(0.01)
	second.notify_shot()
	assert_false(second.playing)
	assert_false(second.firing)
	assert_eq(second.starts, 1)

func test_a_slow_frame_does_not_end_a_freshly_received_shot() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	voice.context = context
	voice.set_process(false)
	for frame: int in 5:
		voice.notify_shot()
		voice._process(0.25)
	assert_true(voice.firing)
	assert_eq(voice.starts, 1)
	assert_eq(voice.endings, 0)

func test_actual_round_signal_drives_audio_not_target_or_burst_assignment() -> void:
	var definition := preload("res://defense/close_in_gun/close_in_gun.tres")
	var gun := add_child_autofree(definition.scene.instantiate()) as CloseInGun
	gun.setup(1, definition)
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	gun.configure_audio(context)
	gun.set_priority_track(42)
	assert_eq(gun.firing_audio.starts, 0)
	gun.gunfire.round_fired.emit(gun.muzzle.global_position)
	gun.set_priority_track(43)
	gun.gunfire.round_fired.emit(gun.muzzle.global_position)
	assert_eq(gun.firing_audio.starts, 1)
