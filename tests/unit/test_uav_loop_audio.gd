extends GutTest

class Uav:
	extends ThreatUnit
	var seconds: float = 8.0
	var completed: bool = false
	var aborting: bool = false
	func presentation_action_seconds() -> float:
		return seconds
	func presentation_action_completed() -> bool:
		return completed
	func exits_without_impact() -> bool:
		return aborting or completed

func _source(audio: UavLoopAudio, event: StringName, seconds: float) -> Uav:
	var threat := add_child_autofree(Uav.new()) as Uav
	threat.definition = ThreatDefinition.new()
	threat.definition.loop_audio_event = event
	threat.seconds = seconds
	audio.register(threat)
	return threat

func _tick(audio: UavLoopAudio, count: int = 10) -> void:
	for index: int in count:
		audio.update_audio(0.02, false, 1.0, true)

func _has_voice(audio: UavLoopAudio, threat: Uav) -> bool:
	var member := audio.sources.get(threat.get_instance_id()) as UavLoopAudio.Source
	if member == null:
		return false
	for voice: UavLoopAudio.Voice in audio.voices:
		if voice.event == member.event and voice.player.playing:
			return true
	return false

func _voice_count_for_event(audio: UavLoopAudio, event: StringName) -> int:
	var count := 0
	for voice: UavLoopAudio.Voice in audio.voices:
		count += int(voice.event == event and voice.player.playing)
	return count

func _voice_for_source(audio: UavLoopAudio, threat: Uav) -> UavLoopAudio.Voice:
	var member := audio.sources.get(threat.get_instance_id()) as UavLoopAudio.Source
	if member != null:
		for voice: UavLoopAudio.Voice in audio.voices:
			if voice.event == member.event:
				return voice
	fail_test("source %d has no UAV loop voice" % threat.get_instance_id())
	return null

func test_same_uav_family_shares_one_voice_and_survives_one_member_resolution() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var first := _source(audio, UavLoopAudio.MEDIUM, 18.0)
	_tick(audio)
	assert_false(_has_voice(audio, first))
	first.seconds = 8.0
	var companion := _source(audio, UavLoopAudio.MEDIUM, 8.4)
	_tick(audio)
	assert_true(_has_voice(audio, first))
	assert_eq(_voice_count_for_event(audio, UavLoopAudio.MEDIUM), 1)
	assert_almost_eq(_voice_for_source(audio, first).envelope, 0.5, 0.001)
	assert_same(_voice_for_source(audio, first), _voice_for_source(audio, companion))
	first.resolve_once(false)
	_tick(audio)
	assert_true(_has_voice(audio, companion), "묶음 일부가 사라져도 남은 기체는 유지")

func test_distinct_uav_families_share_a_bounded_mix_budget() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	_source(audio, UavLoopAudio.LIGHT, 0.0)
	_source(audio, UavLoopAudio.MEDIUM, 0.0)
	_source(audio, UavLoopAudio.HEAVY, 0.0)
	_tick(audio)
	var total := 0.0
	for voice: UavLoopAudio.Voice in audio.voices:
		total += voice.player.volume_linear
	assert_eq(audio.voices.size(), UavLoopAudio.MAX_VOICES)
	assert_lte(total, UavLoopAudio.MIX_BUDGET + 0.0001)

func test_all_uav_loop_samples_are_looped_and_prepared() -> void:
	var prepared_streams := UavLoopAudio.all_streams()
	for event: StringName in UavLoopAudio.STREAMS:
		var stream := UavLoopAudio.STREAMS[event] as AudioStreamOggVorbis
		assert_true(stream.loop, "event %s loop" % event)
		assert_has(prepared_streams, stream, "event %s UavLoopAudio preparation" % event)
		assert_has(CombatAudio.all_streams(), stream, "event %s global preparation" % event)

func test_same_family_uses_loudest_current_envelope_without_adding_gain() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var quiet := _source(audio, UavLoopAudio.MEDIUM, 12.0)
	var closer := _source(audio, UavLoopAudio.MEDIUM, 8.0)
	_tick(audio)
	assert_true(_has_voice(audio, quiet))
	var loud := _source(audio, UavLoopAudio.MEDIUM, 0.4)
	_tick(audio, 20)
	assert_true(_has_voice(audio, quiet))
	assert_true(_has_voice(audio, loud))
	assert_true(_has_voice(audio, closer))
	assert_eq(_voice_count_for_event(audio, UavLoopAudio.MEDIUM), 1)
	assert_lte(_voice_for_source(audio, loud).player.volume_linear, db_to_linear(float(UavLoopAudio.GAINS_DB[UavLoopAudio.MEDIUM])) + 0.0001)
	quiet.seconds = 0.2
	loud.resolve_once(true)
	_tick(audio, 20)
	assert_true(_has_voice(audio, quiet))
	assert_gt(_voice_for_source(audio, quiet).envelope, 0.95)

func test_many_sources_keep_one_voice_per_family() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var first := _source(audio, UavLoopAudio.HEAVY, 8.0)
	var second := _source(audio, UavLoopAudio.HEAVY, 2.0)
	_source(audio, UavLoopAudio.MEDIUM, 2.0)
	_source(audio, UavLoopAudio.LIGHT, 2.0)
	_tick(audio)
	var newcomer := _source(audio, UavLoopAudio.HEAVY, 12.0)
	_tick(audio)
	newcomer.seconds = 7.8
	_tick(audio)
	assert_true(_has_voice(audio, first))
	assert_true(_has_voice(audio, newcomer))
	newcomer.seconds = 0.0
	_tick(audio, 20)
	assert_true(_has_voice(audio, newcomer))
	assert_true(_has_voice(audio, second))
	var count := 0
	for voice: UavLoopAudio.Voice in audio.voices:
		if voice.player.playing:
			count += 1
	assert_lte(count, UavLoopAudio.MAX_VOICES)
	assert_eq(_voice_count_for_event(audio, UavLoopAudio.HEAVY), 1)

func test_pause_keeps_departure_state_and_rate_scales_only_simulation_time() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var threat := _source(audio, UavLoopAudio.HEAVY, 0.0)
	_tick(audio)
	var voice := _voice_for_source(audio, threat)
	threat.completed = true
	audio.update_audio(0.5, true, 2.0, true)
	assert_false(audio.sources[threat.get_instance_id()].departing)
	assert_true(voice.player.stream_paused)
	var playback_time := audio.playback_clock
	var simulation_time := audio.simulation_clock
	audio.update_audio(0.5, false, 2.0, true)
	assert_almost_eq(audio.playback_clock - playback_time, 0.5, 0.001)
	assert_almost_eq(audio.simulation_clock - simulation_time, 1.0, 0.001)
	assert_eq(voice.player.pitch_scale, 1.0, "게임 배속과 관계없이 원래 음높이와 재생 속도를 유지합니다")
	assert_almost_eq(audio.sources[threat.get_instance_id()].envelope, 0.5, 0.001)

func test_resolution_fades_voice() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var threat := _source(audio, UavLoopAudio.HEAVY, 0.0)
	_tick(audio)
	var voice := _voice_for_source(audio, threat)
	threat.resolve_once(true)
	_tick(audio, 11)
	assert_false(voice.player.playing)

func test_reset_clears_operation_state_and_disconnects_old_resolution_signal() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var fresh := _source(audio, UavLoopAudio.MEDIUM, 0.0)
	_tick(audio)
	var voice := _voice_for_source(audio, fresh)
	audio.reset()
	_tick(audio)
	assert_true(audio.sources.is_empty())
	fresh.resolved.emit(fresh, true, 0)
	assert_false(voice.player.playing)

func test_silent_and_completed_sources_are_not_registered() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var silent := _source(audio, &"", 0.0)
	assert_false(audio.sources.has(silent.get_instance_id()))
	var completed := _source(audio, UavLoopAudio.HEAVY, 2.0)
	audio.reset()
	completed.completed = true
	audio.register(completed)
	assert_false(audio.sources.has(completed.get_instance_id()), "투하 후 복원에는 루프를 다시 시작하지 않음")

func test_aborting_source_fades_out() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var aborted := _source(audio, UavLoopAudio.HEAVY, 2.0)
	_tick(audio)
	aborted.aborting = true
	_tick(audio, 11)
	assert_false(_has_voice(audio, aborted))
