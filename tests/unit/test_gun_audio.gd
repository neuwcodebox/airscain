extends GutTest

class MissileSource:
	extends Node
	signal flight_ended(detonated: bool)

func test_single_weapon_voice_uses_category_gain_before_crowding() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var source := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, source))
	assert_almost_eq(context.source_players[source.get_instance_id()].volume_linear, CombatAudio.MISSILE_VOICE_GAIN, 0.0001)
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	voice.context = context
	voice.notify_shot()
	voice._process(GunAudio.CROSSFADE_SECONDS)
	assert_almost_eq(voice.volume_linear, CombatAudio.GUN_VOICE_GAIN, 0.0001)
	assert_lte(voice.volume_linear, CombatAudio.GUN_MIX_BUDGET)
	assert_lte(context.source_players[source.get_instance_id()].volume_linear, CombatAudio.MISSILE_MIX_BUDGET)

func test_missile_groups_keep_four_slots_and_shared_gain_budget() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources: Array[MissileSource] = []
	for index: int in 40:
		context._process(CombatAudio.MISSILE_GROUP_WINDOW + 0.01)
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		sources.append(source)
		var accepted := context.play_missile_event(CombatAudio.MISSILE_EVENTS[index % 3], source)
		assert_eq(accepted, index < CombatAudio.MAX_AUDIBLE_MISSILE_GROUPS)
	assert_eq(context.source_players.size(), CombatAudio.MAX_AUDIBLE_MISSILE_GROUPS)
	var first := context.source_players[sources[0].get_instance_id()]
	assert_false(context.play_missile_event(CombatAudio.MISSILE, sources[0]), "같은 발사음을 재시작하지 않습니다")
	for event: StringName in [CombatAudio.CONTACT, CombatAudio.DAMAGE, CombatAudio.EXPLOSION]:
		context.play_event(event)
	assert_same(first, context.source_players[sources[0].get_instance_id()])
	var total := 0.0
	for player: AudioStreamPlayer in context.missile_players:
		total += player.volume_linear
		assert_true(player.playing)
	assert_lte(total, CombatAudio.MISSILE_MIX_BUDGET + 0.0001)
	context.cooldowns[CombatAudio.EXPLOSION] = 0.0
	var explosions := context.played_count(CombatAudio.EXPLOSION)
	sources.back().flight_ended.emit(true)
	assert_eq(context.played_count(CombatAudio.EXPLOSION), explosions + 1, "Suppressed launch still reports impact")
	sources[0].flight_ended.emit(false)
	var suppressed := add_child_autofree(MissileSource.new()) as MissileSource
	assert_false(context.play_missile_event(CombatAudio.MISSILE, suppressed), "Fading voice still occupies its slot")
	await get_tree().create_timer(CombatAudio.RETIRE_FADE_SECONDS + 0.05).timeout
	assert_false(context.play_missile_event(CombatAudio.MISSILE, suppressed), "Suppressed launches never start late")
	var replacement := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, replacement))
	for frame: int in 24:
		await get_tree().process_frame
		total = 0.0
		for player: AudioStreamPlayer in context.missile_players:
			if player.playing:
				total += player.volume_linear
		assert_lte(total, CombatAudio.MISSILE_MIX_BUDGET + 0.0001, "Retirement/replacement also obeys the mix budget")
	context.stop_all()
	assert_true(context.source_players.is_empty())
	assert_true(context.missile_groups.is_empty())
	for player: AudioStreamPlayer in context.missile_players:
		assert_false(player.playing)

func test_simultaneous_missiles_share_sound_until_last_member_exits() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources: Array[MissileSource] = []
	for index: int in 40:
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		sources.append(source)
		assert_true(context.play_missile_event(CombatAudio.MISSILE, source))
	assert_eq(context.played_count(CombatAudio.MISSILE), 1)
	var player := context.source_players[sources[0].get_instance_id()]
	for index: int in 39:
		assert_same(context.source_players[sources[index].get_instance_id()], player)
		sources[index].flight_ended.emit(true)
		assert_false(context.fade_tweens.has(player.get_instance_id()))
		assert_true(player.playing)
	# Scene removal is also an end; no flight_ended signal is required.
	remove_child(sources.back())
	assert_true(context.fade_tweens.has(player.get_instance_id()))
	assert_true(context.source_players.is_empty())
	await get_tree().create_timer(CombatAudio.RETIRE_FADE_SECONDS + 0.05).timeout
	assert_false(player.playing)

func test_missile_group_window_is_fixed_and_separates_families() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	var first := add_child_autofree(MissileSource.new()) as MissileSource
	var second := add_child_autofree(MissileSource.new()) as MissileSource
	var third := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, first))
	context._process(CombatAudio.MISSILE_GROUP_WINDOW * 0.75)
	assert_true(context.play_missile_event(CombatAudio.MISSILE, second))
	assert_eq(context.played_count(CombatAudio.MISSILE), 1)
	context._process(CombatAudio.MISSILE_GROUP_WINDOW * 0.5)
	assert_true(context.play_missile_event(CombatAudio.MISSILE, third))
	assert_eq(context.played_count(CombatAudio.MISSILE), 2, "Joining never extends the first launch's window")
	for event: StringName in [CombatAudio.LONG_MISSILE, CombatAudio.SHORT_MISSILE]:
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		assert_true(context.play_missile_event(event, source))
		assert_eq(context.played_count(event), 1)
	assert_eq(context.missile_groups.size(), 4)
	var last := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, last), "Existing group can accept members even when all slots are occupied")
	assert_same(context.source_players[third.get_instance_id()], context.source_players[last.get_instance_id()])
	context.simulation_paused = true
	var clock_before := context.missile_clock
	context._process(1.0)
	assert_eq(context.missile_clock, clock_before)

func test_natural_missile_completion_releases_ownership_before_reuse() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var source := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, source))
	var companion := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, companion))
	var player := context.source_players[source.get_instance_id()]
	player.stop()
	player.finished.emit()
	assert_false(context.source_players.has(source.get_instance_id()))
	assert_false(context.source_players.has(companion.get_instance_id()))
	var next := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, next))
	source.flight_ended.emit(false)
	companion.flight_ended.emit(true)
	assert_true(player.playing, "Retired missile cannot fade a reused voice")
	assert_false(context.fade_tweens.has(player.get_instance_id()))

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

func test_sequence_uses_one_shared_ogg_sample_with_a_native_loop_region() -> void:
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	var sound := voice.stream as AudioStreamOggVorbis
	assert_true(sound.loop)
	assert_almost_eq(sound.loop_offset, GunAudio.LOOP_START_SECONDS, 0.00001)
	assert_gt(sound.get_length(), sound.loop_offset)
	assert_same(sound, GunAudio.sustain_stream())
	assert_same(voice.ending_player.stream, GunAudio.END_SOUND)
	assert_has(CombatAudio.all_streams(), sound)
	assert_has(CombatAudio.all_streams(), GunAirburstAudio.loop_stream())

func test_many_guns_share_a_bounded_mix_budget_without_restarting() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voices: Array[GunAudio] = []
	for index: int in 24:
		var voice := add_child_autofree(GunAudio.new()) as GunAudio
		voice.context = context
		voice.notify_shot()
		voice._process(0.06)
		voices.append(voice)
	var total := 0.0
	var audible_count := 0
	for voice: GunAudio in voices:
		total += voice.volume_linear
		audible_count += int(voice.audible)
		assert_eq(voice.starts, 1)
	assert_eq(audible_count, CombatAudio.MAX_AUDIBLE_GUNS)
	assert_almost_eq(total, CombatAudio.GUN_MIX_BUDGET, 0.0001)
	for voice: GunAudio in voices:
		voice._process(0.2)
		voice._process(6.0)
	assert_true(context.gun_voices.is_empty())

func test_audible_guns_stay_stable_and_virtual_guns_take_over_a_finished_slot() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voices: Array[GunAudio] = []
	for index: int in 6:
		var voice := add_child_autofree(GunAudio.new()) as GunAudio
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
		voice._process(0.06)
		voices.append(voice)
	assert_false(voices[4].playing)
	for frame: int in 10:
		for voice: GunAudio in voices:
			voice.notify_shot()
			voice._process(0.06)
		context.refresh_gun_mix()
	assert_true(voices[0].audible)
	assert_false(voices[4].audible)
	voices[0]._process(0.2)
	voices[4]._process(0.06)
	assert_false(voices[0].audible)
	assert_true(voices[4].audible)
	assert_true(voices[4].playing)
	assert_eq(voices[4].starts, 1, "대표 교체는 새로운 사격 사건이 아닙니다")

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

func test_virtual_guns_preserve_firing_during_pause() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voices: Array[GunAudio] = []
	for index: int in CombatAudio.MAX_AUDIBLE_GUNS + 1:
		var voice := add_child_autofree(GunAudio.new()) as GunAudio
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
		voice._process(0.06)
		voices.append(voice)
	var virtual_voice := voices.back() as GunAudio
	assert_false(virtual_voice.playing)
	context.simulation_paused = true
	virtual_voice._process(2.0)
	assert_true(virtual_voice.firing)
	assert_eq(virtual_voice.endings, 0)
	context.simulation_paused = false
	virtual_voice.notify_shot()
	assert_eq(virtual_voice.starts, 1)

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
	gun.set_target_kind_allowed(&"uav", false)
	assert_eq(gun.firing_audio.starts, 0)
	gun.gunfire.round_fired.emit(gun.muzzle.global_position)
	gun.set_target_kind_allowed(&"uav", true)
	gun.gunfire.round_fired.emit(gun.muzzle.global_position)
	assert_eq(gun.firing_audio.starts, 1)
