extends GutTest

class ApproachingThreat:
	extends ThreatUnit
	var seconds: float = 10.0
	var completed: bool = false
	var aborting: bool = false
	func exits_without_impact() -> bool:
		return aborting or completed
	func presentation_action_seconds() -> float:
		return seconds
	func presentation_action_completed() -> bool:
		return completed

func _source(audio: ThreatApproachAudio, seconds: float = 6.5) -> ApproachingThreat:
	var threat := add_child_autofree(ApproachingThreat.new()) as ApproachingThreat
	threat.definition = ThreatDefinition.new()
	threat.definition.approach_audio_event = ThreatApproachAudio.EVENT
	threat.seconds = seconds
	audio.register(threat)
	return threat

func test_approach_window_and_late_spawn_seek() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio, 10.0)
	audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	threat.seconds = 2.0
	audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 1)
	var voice := _voice_for_source(audio, threat)
	assert_almost_eq(voice.player.get_playback_position(), ThreatApproachAudio.PEAK_SECONDS - threat.seconds, 0.1)
	for index: int in 10:
		audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 1, "한 기체의 접근음은 반복하지 않습니다")

func test_crowding_drops_cues_without_replay_or_stealing() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var first := _source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	var simultaneous := _source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	assert_eq(audio.played_count, 1)
	var second := _source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	var crowded := _source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 2)
	var first_voice := _voice_for_source(audio, first)
	var second_voice := _voice_for_source(audio, second)
	assert_ne(first_voice.player.stream, second_voice.player.stream)
	assert_eq(first_voice.source_id, first.get_instance_id())
	assert_eq(second_voice.source_id, second.get_instance_id())
	var gain_sum := 0.0
	for voice: ThreatApproachAudio.Voice in audio.voices:
		gain_sum += voice.player.volume_linear
	assert_lt(gain_sum, 0.75, "두 음성을 합쳐도 보수적 gain 예산 안에 있습니다")
	first_voice.player.stop()
	second_voice.player.stop()
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 2, "생략 및 자연 종료한 음원은 재시작하지 않습니다")
	assert_true(audio.attempted.has(simultaneous.get_instance_id()))
	assert_true(audio.attempted.has(crowded.get_instance_id()))

func test_pause_blocks_start_and_rate_keeps_the_original_pitch() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio)
	audio.update_audio(1.0, true, 1.0, true)
	assert_eq(audio.played_count, 0)
	audio.update_audio(0.01, false, 2.0, true)
	assert_eq(_voice_for_source(audio, threat).player.pitch_scale, 1.0, "게임 배속과 관계없이 원래 음높이와 재생 속도를 유지합니다")

func test_completed_departure_tail_survives_release_but_retires_on_kill() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	var voice := _voice_for_source(audio, threat)
	threat.completed = true
	threat.seconds = INF
	audio.update_audio(0.01, false, 1.0, true)
	assert_true(voice.player.playing, "투발 후 이탈 부분은 유지합니다")
	threat.resolve_once(true)
	audio.update_audio(1.0, true, 1.0, true)
	assert_true(voice.player.stream_paused)
	assert_eq(voice.fade_remaining, ThreatApproachAudio.RETIRE_SECONDS)
	audio.update_audio(0.3, false, 1.0, true)
	assert_false(voice.player.playing, "이탈 중 격추도 음원을 끝냅니다")

func test_abort_fades_approach_voice() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio)
	audio.update_audio(0.1, false, 1.0, true)
	var voice := _voice_for_source(audio, threat)
	threat.seconds = INF
	threat.aborting = true
	audio.update_audio(0.1, false, 1.0, true)
	audio.update_audio(0.3, false, 1.0, true)
	assert_false(voice.player.playing)

func test_reset_clears_operation_and_disconnects_old_source_signals() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio)
	audio.update_audio(0.1, false, 1.0, true)
	audio.reset()
	assert_true(audio.threats.is_empty())
	assert_true(audio.attempted.is_empty())
	var restored := _source(audio, 3.0)
	audio.update_audio(0.1, false, 1.0, true)
	var restored_voice := _voice_for_source(audio, restored)
	assert_true(restored_voice.player.playing)
	threat.resolved.emit(threat, true, 0)
	assert_false(restored_voice.retiring, "이전 작전 신호는 새 음성에 영향을 주지 않습니다")
	audio.update_audio(0.1, false, 1.0, false)
	assert_false(restored_voice.player.playing)
	assert_false(audio.threats.has(restored.get_instance_id()))

func test_departed_source_preserves_tail_and_does_not_retire_reused_slot() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio)
	audio.update_audio(0.1, false, 1.0, true)
	var departing_voice := _voice_for_source(audio, threat)
	threat.completed = true
	threat.free()
	assert_true(departing_voice.player.playing)
	assert_false(departing_voice.retiring)
	assert_true(audio.threats.is_empty())
	departing_voice.player.stop()
	var replacement := _source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	var replacement_voice := _voice_for_source(audio, replacement)
	assert_true(replacement_voice.player.playing)
	assert_false(replacement_voice.retiring)

func test_nonfinite_approach_and_unconfigured_sources_are_silent() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := _source(audio, INF)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	audio.reset()
	threat.definition.approach_audio_event = &""
	threat.seconds = 0.0
	audio.register(threat)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 0)

func test_approach_samples_are_prepared_as_nonlooping_streams() -> void:
	for stream: AudioStream in ThreatApproachAudio.all_streams():
		assert_has(CombatAudio.all_streams(), stream)
		assert_false((stream as AudioStreamOggVorbis).loop)

func _cruise_source(audio: ThreatApproachAudio, seconds: float = 5.0) -> ApproachingThreat:
	var threat := add_child_autofree(ApproachingThreat.new()) as ApproachingThreat
	threat.definition = ThreatDefinition.new()
	threat.definition.approach_audio_event = ThreatApproachAudio.CRUISE_EVENT
	threat.seconds = seconds
	audio.register(threat)
	return threat

func test_cruise_groups_wait_for_last_impact_and_do_not_restart() -> void:
	var audio := ThreatApproachAudio.new()
	audio.configure_cruise()
	add_child_autofree(audio)
	var first := _cruise_source(audio, 5.1)
	audio.update_audio(0.01, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	first.seconds = 5.0
	audio.update_audio(0.01, false, 1.0, true)
	var second := _cruise_source(audio)
	audio.update_audio(0.05, false, 1.0, true)
	assert_eq(audio.played_count, 1, "동시 접근은 한 번만 재생합니다")
	var group_voice := _voice_for_source(audio, first)
	assert_same(_voice_for_source(audio, second), group_voice)
	first.resolve_once(false)
	assert_false(group_voice.retiring, "다른 미사일이 남으면 유지합니다")
	second.resolve_once(true)
	assert_true(group_voice.retiring, "마지막 미사일 격추도 묶음을 종료합니다")
	audio.update_audio(0.13, false, 1.0, true)
	assert_false(group_voice.player.playing)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 1)

func test_cruise_separate_groups_cap_and_deleted_members() -> void:
	var audio := ThreatApproachAudio.new()
	audio.configure_cruise()
	add_child_autofree(audio)
	var first := _cruise_source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	var first_voice := _voice_for_source(audio, first)
	var second := _cruise_source(audio)
	audio.update_audio(0.2, false, 1.0, true)
	var second_voice := _voice_for_source(audio, second)
	_cruise_source(audio)
	audio.update_audio(0.2, false, 1.0, true)
	assert_eq(audio.played_count, 2, "재생 상한에 도달하면 새 묶음은 생략합니다")
	first.free()
	assert_true(first_voice.retiring)
	assert_false(second_voice.retiring)
	second.resolve_once(false)
	assert_true(second_voice.retiring)
	audio.update_audio(0.2, false, 1.0, true)
	assert_eq(audio.played_count, 2, "생략된 미사일은 나중에 재생하지 않습니다")

func _voice_for_source(audio: ThreatApproachAudio, threat: ThreatUnit) -> ThreatApproachAudio.Voice:
	var source_id := threat.get_instance_id()
	for voice: ThreatApproachAudio.Voice in audio.voices:
		if voice.source_id == source_id or voice.members.has(source_id):
			return voice
	fail_test("source %d has no approach-audio voice" % source_id)
	return null
