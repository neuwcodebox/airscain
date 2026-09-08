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

func source(audio: ThreatApproachAudio, seconds: float = 6.5) -> ApproachingThreat:
	var threat := add_child_autofree(ApproachingThreat.new()) as ApproachingThreat
	threat.definition = ThreatDefinition.new()
	threat.definition.approach_audio_event = ThreatApproachAudio.EVENT
	threat.seconds = seconds
	audio.register(threat)
	return threat

func test_approach_window_and_late_spawn_seek() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := source(audio, 10.0)
	audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	threat.seconds = 2.0
	audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 1)
	assert_almost_eq(audio.voices[0].player.get_playback_position(), 4.5, 0.1)
	for index: int in 10:
		audio.update_audio(0.1, false, 1.0, true)
	assert_eq(audio.played_count, 1, "한 기체의 접근음은 반복하지 않습니다")

func test_crowding_drops_cues_without_replay_or_stealing() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var first := source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	var simultaneous := source(audio)
	audio.update_audio(0.01, false, 1.0, true)
	assert_eq(audio.played_count, 1)
	var second := source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	var crowded := source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 2)
	assert_ne(audio.voices[0].player.stream, audio.voices[1].player.stream)
	assert_eq(audio.voices[0].source_id, first.get_instance_id())
	assert_eq(audio.voices[1].source_id, second.get_instance_id())
	var gain_sum := 0.0
	for voice: ThreatApproachAudio.Voice in audio.voices:
		gain_sum += voice.player.volume_linear
	assert_lt(gain_sum, 0.75, "두 음성을 합쳐도 보수적 gain 예산 안에 있습니다")
	audio.voices[0].player.stop()
	audio.voices[1].player.stop()
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 2, "생략 및 자연 종료한 음원은 재시작하지 않습니다")
	assert_true(audio.attempted.has(simultaneous.get_instance_id()))
	assert_true(audio.attempted.has(crowded.get_instance_id()))

func test_pause_speed_kill_and_departure_tail() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := source(audio)
	audio.update_audio(1.0, true, 1.0, true)
	assert_eq(audio.played_count, 0)
	audio.update_audio(0.01, false, 2.0, true)
	assert_eq(audio.voices[0].player.pitch_scale, 2.0)
	threat.completed = true
	threat.seconds = INF
	audio.update_audio(0.01, false, 1.0, true)
	assert_true(audio.voices[0].player.playing, "투발 후 이탈 부분은 유지합니다")
	threat.resolve_once(true)
	audio.update_audio(1.0, true, 1.0, true)
	assert_true(audio.voices[0].player.stream_paused)
	assert_eq(audio.voices[0].fade_remaining, ThreatApproachAudio.RETIRE_SECONDS)
	audio.update_audio(0.3, false, 1.0, true)
	assert_false(audio.voices[0].player.playing, "이탈 중 격추도 음원을 끝냅니다")

func test_abort_fades_and_reset_clears_old_operation() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := source(audio)
	audio.update_audio(0.1, false, 1.0, true)
	threat.seconds = INF
	threat.aborting = true
	audio.update_audio(0.1, false, 1.0, true)
	audio.update_audio(0.3, false, 1.0, true)
	assert_false(audio.voices[0].player.playing)
	audio.reset()
	assert_true(audio.threats.is_empty())
	assert_true(audio.attempted.is_empty())
	var restored := source(audio, 3.0)
	audio.update_audio(0.1, false, 1.0, true)
	assert_true(audio.voices[0].player.playing)
	threat.resolved.emit(threat, true, 0)
	assert_false(audio.voices[0].retiring, "이전 작전 신호는 새 음성에 영향을 주지 않습니다")
	audio.update_audio(0.1, false, 1.0, false)
	assert_false(audio.voices[0].player.playing)
	assert_false(audio.threats.has(restored.get_instance_id()))

func test_departed_source_preserves_tail_and_does_not_retire_reused_slot() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := source(audio)
	audio.update_audio(0.1, false, 1.0, true)
	threat.completed = true
	threat.free()
	assert_true(audio.voices[0].player.playing)
	assert_false(audio.voices[0].retiring)
	assert_true(audio.threats.is_empty())
	audio.voices[0].player.stop()
	source(audio)
	audio.update_audio(1.0, false, 1.0, true)
	assert_true(audio.voices[0].player.playing)
	assert_false(audio.voices[0].retiring)

func test_unconfigured_threats_and_egress_are_silent_and_samples_prepared() -> void:
	var audio := add_child_autofree(ThreatApproachAudio.new()) as ThreatApproachAudio
	var threat := source(audio, INF)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	audio.reset()
	threat.definition.approach_audio_event = &""
	threat.seconds = 0.0
	audio.register(threat)
	audio.update_audio(1.0, false, 1.0, true)
	assert_eq(audio.played_count, 0)
	for stream: AudioStream in ThreatApproachAudio.all_streams():
		assert_has(CombatAudio.all_streams(), stream)
		assert_false((stream as AudioStreamOggVorbis).loop)
