extends GutTest

class MissileSource:
	extends Node
	signal flight_ended(detonated: bool)

func test_single_missile_voice_uses_category_gain_before_crowding() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var source := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, source))
	assert_almost_eq(context.source_players[source.get_instance_id()].volume_linear, CombatAudio.MISSILE_VOICE_GAIN, 0.0001)
	assert_lte(context.source_players[source.get_instance_id()].volume_linear, CombatAudio.MISSILE_MIX_BUDGET)

func test_single_gun_voice_uses_category_gain_before_crowding() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := add_child_autofree(GunAudio.new()) as GunAudio
	voice.context = context
	voice.notify_shot()
	_advance_gun_voice(voice, GunAudio.CROSSFADE_SECONDS)
	assert_almost_eq(voice.volume_linear, CombatAudio.GUN_VOICE_GAIN, 0.0001)
	assert_lte(voice.volume_linear, CombatAudio.GUN_MIX_BUDGET)

func test_missile_groups_keep_four_slots_and_shared_gain_budget() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources: Array[MissileSource] = []
	for index: int in 40:
		_advance_combat_audio(context, CombatAudio.MISSILE_GROUP_WINDOW + 0.01)
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		sources.append(source)
		var event := CombatAudio.MISSILE_EVENTS[index % CombatAudio.MISSILE_EVENTS.size()]
		var accepted := context.play_missile_event(event, source)
		assert_eq(accepted, index < CombatAudio.MAX_AUDIBLE_MISSILE_GROUPS, "launch %d event %s" % [index, event])
	assert_eq(context.source_players.size(), CombatAudio.MAX_AUDIBLE_MISSILE_GROUPS)
	assert_false(context.play_missile_event(CombatAudio.MISSILE, sources[0]), "같은 발사음을 재시작하지 않습니다")
	var total := 0.0
	for slot: int in context.missile_players.size():
		var player := context.missile_players[slot]
		total += player.volume_linear
		assert_true(player.playing, "missile slot %d" % slot)
	assert_lte(total, CombatAudio.MISSILE_MIX_BUDGET + 0.0001)

func test_suppressed_missile_still_reports_impact_without_stealing_other_events() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources := _fill_missile_voice_slots(context)
	var first := context.source_players[sources[0].get_instance_id()]
	for event: StringName in [CombatAudio.CONTACT, CombatAudio.DAMAGE, CombatAudio.EXPLOSION]:
		context.play_event(event)
	assert_same(first, context.source_players[sources[0].get_instance_id()])
	_advance_combat_audio(context, CombatAudio.MISSILE_GROUP_WINDOW + 0.01)
	var suppressed := add_child_autofree(MissileSource.new()) as MissileSource
	assert_false(context.play_missile_event(CombatAudio.MISSILE, suppressed))
	context.cooldowns[CombatAudio.EXPLOSION] = 0.0
	var explosions := context.played_count(CombatAudio.EXPLOSION)
	suppressed.flight_ended.emit(true)
	assert_eq(context.played_count(CombatAudio.EXPLOSION), explosions + 1, "Suppressed launch still reports impact")

func test_retiring_missile_voice_releases_its_slot_without_starting_suppressed_launches_late() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources := _fill_missile_voice_slots(context)
	var retiring_player := context.source_players[sources[0].get_instance_id()] as AudioStreamPlayer
	sources[0].flight_ended.emit(false)
	var suppressed := add_child_autofree(MissileSource.new()) as MissileSource
	assert_false(context.play_missile_event(CombatAudio.MISSILE, suppressed), "Fading voice still occupies its slot")
	_complete_missile_fade(context, retiring_player, CombatAudio.RETIRE_FADE_SECONDS)
	assert_false(context.play_missile_event(CombatAudio.MISSILE, suppressed), "Suppressed launches never start late")
	var replacement := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, replacement))
	var total := 0.0
	for frame: int in 24:
		_advance_combat_audio(context, CombatAudio.RETIRE_FADE_SECONDS / 24.0)
		total = 0.0
		for player: AudioStreamPlayer in context.missile_players:
			if player.playing:
				total += player.volume_linear
		assert_lte(total, CombatAudio.MISSILE_MIX_BUDGET + 0.0001, "retirement frame %d obeys the mix budget" % frame)

func test_stop_all_clears_missile_ownership_and_players() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	_fill_missile_voice_slots(context)
	context.stop_all()
	assert_true(context.source_players.is_empty())
	assert_true(context.missile_groups.is_empty())
	for slot: int in context.missile_players.size():
		assert_false(context.missile_players[slot].playing, "missile slot %d stopped" % slot)

func _fill_missile_voice_slots(context: CombatAudio) -> Array[MissileSource]:
	var sources: Array[MissileSource] = []
	for index: int in CombatAudio.MAX_AUDIBLE_MISSILE_GROUPS:
		_advance_combat_audio(context, CombatAudio.MISSILE_GROUP_WINDOW + 0.01)
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		sources.append(source)
		var event := CombatAudio.MISSILE_EVENTS[index % CombatAudio.MISSILE_EVENTS.size()]
		assert_true(
			context.play_missile_event(event, source),
			"slot %d event %s should accept its fixture launch" % [index, event]
		)
	return sources

func _advance_combat_audio(context: CombatAudio, delta: float) -> void:
	context._process(delta)

func _advance_gun_voice(voice: GunAudio, delta: float) -> void:
	voice._process(delta)

func _advance_airburst_voice(voice: GunAirburstAudio, delta: float) -> void:
	voice._process(delta)

func _complete_missile_fade(context: CombatAudio, player: AudioStreamPlayer, duration: float) -> void:
	var tween := context.fade_tweens.get(player.get_instance_id()) as Tween
	assert_not_null(tween, "retiring missile voice should own a fade tween")
	if tween != null:
		tween.custom_step(duration + 0.001)

func test_simultaneous_missiles_share_sound_until_last_member_exits() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var sources: Array[MissileSource] = []
	for index: int in 40:
		var source := add_child_autofree(MissileSource.new()) as MissileSource
		sources.append(source)
		assert_true(context.play_missile_event(CombatAudio.MISSILE, source), "member %d event %s" % [index, CombatAudio.MISSILE])
	assert_eq(context.played_count(CombatAudio.MISSILE), 1)
	var player := context.source_players[sources[0].get_instance_id()]
	for index: int in 39:
		var case_label := "member %d" % index
		assert_same(context.source_players[sources[index].get_instance_id()], player, "%s shared player" % case_label)
		sources[index].flight_ended.emit(true)
		assert_false(context.fade_tweens.has(player.get_instance_id()), "%s keeps group alive" % case_label)
		assert_true(player.playing, "%s shared player remains audible" % case_label)
	# Scene removal is also an end; no flight_ended signal is required.
	remove_child(sources.back())
	assert_true(context.fade_tweens.has(player.get_instance_id()))
	assert_true(context.source_players.is_empty())
	_complete_missile_fade(context, player, CombatAudio.RETIRE_FADE_SECONDS)
	assert_false(player.playing)

func test_missile_group_window_is_fixed_and_separates_families() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	var first := add_child_autofree(MissileSource.new()) as MissileSource
	var second := add_child_autofree(MissileSource.new()) as MissileSource
	var third := add_child_autofree(MissileSource.new()) as MissileSource
	assert_true(context.play_missile_event(CombatAudio.MISSILE, first))
	_advance_combat_audio(context, CombatAudio.MISSILE_GROUP_WINDOW * 0.75)
	assert_true(context.play_missile_event(CombatAudio.MISSILE, second))
	assert_eq(context.played_count(CombatAudio.MISSILE), 1)
	_advance_combat_audio(context, CombatAudio.MISSILE_GROUP_WINDOW * 0.5)
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

func test_missile_group_clock_stops_while_simulation_is_paused() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	context.set_process(false)
	_advance_combat_audio(context, 0.5)
	context.simulation_paused = true
	var clock_before := context.missile_clock
	_advance_combat_audio(context, 1.0)
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

func test_airburst_sample_is_looped_without_trimming() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
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
		_advance_airburst_voice(voice, 0.1)
	assert_eq(voice.starts, 1)
	assert_gt(voice.gain, 0.0)
	_advance_airburst_voice(voice, GunAirburstAudio.QUIET_GRACE - 0.01)
	assert_eq(voice.gain, GunAirburstAudio.LEVEL)
	_advance_airburst_voice(voice, 0.1)
	var fading_gain := voice.gain
	assert_gt(fading_gain, 0.0)
	assert_lt(fading_gain, GunAirburstAudio.LEVEL)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	_advance_airburst_voice(voice, 0.06)
	assert_gt(voice.gain, fading_gain)
	assert_eq(voice.starts, 1)
	_advance_airburst_voice(voice, 1.0)
	assert_false(voice.playing)
	assert_eq(voice.gain, 0.0)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	assert_eq(voice.starts, 2)

func test_airburst_pause_and_slow_frames_preserve_a_new_detonation() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := context.gun_airbursts
	voice.set_process(false)
	voice.notify_detonation(Vector3.ZERO, &"timeout")
	_advance_airburst_voice(voice, 0.4)
	assert_true(voice.playing, "새 자폭은 같은 프레임 지연만으로 종료되지 않습니다")
	context.simulation_paused = true
	_advance_airburst_voice(voice, 10.0)
	assert_true(voice.stream_paused)
	assert_eq(voice.quiet_remaining, GunAirburstAudio.QUIET_GRACE)
	context.simulation_paused = false
	_advance_airburst_voice(voice, 0.01)
	assert_false(voice.stream_paused)

func test_airburst_reset_and_disabled_context_stay_silent() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voice := context.gun_airbursts
	voice.notify_detonation(Vector3.ZERO, &"timeout")
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
		_advance_gun_voice(voice, 0.06)
		voices.append(voice)
	var total := 0.0
	var audible_count := 0
	for index: int in voices.size():
		var voice := voices[index]
		total += voice.volume_linear
		audible_count += int(voice.audible)
		assert_eq(voice.starts, 1, "gun voice %d start count" % index)
	assert_eq(audible_count, CombatAudio.MAX_AUDIBLE_GUNS)
	assert_almost_eq(total, CombatAudio.GUN_MIX_BUDGET, 0.0001)
	for voice: GunAudio in voices:
		_advance_gun_voice(voice, 0.2)
		_advance_gun_voice(voice, 6.0)
	assert_true(context.gun_voices.is_empty())

func test_audible_guns_stay_stable_and_virtual_guns_take_over_a_finished_slot() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voices: Array[GunAudio] = []
	for index: int in 6:
		var voice := add_child_autofree(GunAudio.new()) as GunAudio
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
		_advance_gun_voice(voice, 0.06)
		voices.append(voice)
	assert_false(voices[4].playing)
	for frame: int in 10:
		for voice: GunAudio in voices:
			voice.notify_shot()
			_advance_gun_voice(voice, 0.06)
		context.refresh_gun_mix()
	assert_true(voices[0].audible)
	assert_false(voices[4].audible)
	_advance_gun_voice(voices[0], 0.2)
	_advance_gun_voice(voices[4], 0.06)
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
		_advance_gun_voice(voice, 0.04)
	assert_eq(voice.starts, 1)
	assert_eq(voice.endings, 0)
	assert_true(voice.firing)
	_advance_gun_voice(voice, 0.2)
	assert_eq(voice.endings, 1)
	assert_false(voice.firing)
	assert_gt(voice.tail_remaining, 5.0)
	voice.notify_shot()
	assert_eq(voice.starts, 2)
	assert_true(voice.firing)
	assert_eq(voice.tail_remaining, 0.0)
	_advance_gun_voice(voice, 0.0)
	_advance_gun_voice(voice, 0.2)
	_advance_gun_voice(voice, 6.0)
	assert_false(voice.playing)

func test_virtual_guns_preserve_firing_during_pause() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var voices: Array[GunAudio] = []
	for index: int in CombatAudio.MAX_AUDIBLE_GUNS + 1:
		var voice := add_child_autofree(GunAudio.new()) as GunAudio
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
		_advance_gun_voice(voice, 0.06)
		voices.append(voice)
	var virtual_voice := voices.back() as GunAudio
	assert_false(virtual_voice.playing)
	context.simulation_paused = true
	_advance_gun_voice(virtual_voice, 2.0)
	assert_true(virtual_voice.firing)
	assert_eq(virtual_voice.endings, 0)
	context.simulation_paused = false
	virtual_voice.notify_shot()
	assert_eq(virtual_voice.starts, 1)

func test_pausing_one_gun_preserves_independent_gun_state() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var first := add_child_autofree(GunAudio.new()) as GunAudio
	var second := add_child_autofree(GunAudio.new()) as GunAudio
	for voice: GunAudio in [first, second]:
		voice.context = context
		voice.set_process(false)
		voice.notify_shot()
	context.simulation_paused = true
	_advance_gun_voice(first, 2.0)
	assert_true(first.stream_paused)
	assert_eq(first.endings, 0)
	context.simulation_paused = false
	_advance_gun_voice(first, 0.02)
	assert_false(first.stream_paused)
	_advance_gun_voice(first, 0.2)
	assert_eq(first.endings, 1)
	assert_true(second.firing)

func test_disabling_combat_audio_stops_gun_and_ignores_new_shots() -> void:
	var context := add_child_autofree(CombatAudio.new()) as CombatAudio
	var second := add_child_autofree(GunAudio.new()) as GunAudio
	second.context = context
	second.set_process(false)
	second.notify_shot()
	context.enabled = false
	_advance_gun_voice(second, 0.01)
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
		_advance_gun_voice(voice, 0.25)
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
