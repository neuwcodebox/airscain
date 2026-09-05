extends GutTest

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
