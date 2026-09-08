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

func source(audio: UavLoopAudio, event: StringName, seconds: float) -> Uav:
	var threat := add_child_autofree(Uav.new()) as Uav
	threat.definition = ThreatDefinition.new()
	threat.definition.loop_audio_event = event
	threat.seconds = seconds * 2.0
	audio.register(threat)
	return threat

func tick(audio: UavLoopAudio, count: int = 10) -> void:
	for index: int in count:
		audio.update_audio(0.02, false, 1.0, true)

func audible(audio: UavLoopAudio, threat: Uav) -> bool:
	var member := audio.sources.get(threat.get_instance_id()) as UavLoopAudio.Source
	return member != null and member.group_id != 0 and audio._has_voice(member.group_id)

func test_loop_ramp_grouping_and_light_loudness() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var first := source(audio, UavLoopAudio.MEDIUM, 9.0)
	tick(audio)
	assert_false(audible(audio, first))
	first.seconds = 8.0
	var companion := source(audio, UavLoopAudio.MEDIUM, 4.2)
	tick(audio)
	assert_true(audible(audio, first))
	assert_eq(audio.groups.size(), 1)
	assert_eq(audio.groups.values()[0].member_count, 2)
	assert_almost_eq(audio.groups.values()[0].envelope, 0.5, 0.001)
	var light := source(audio, UavLoopAudio.LIGHT, 2.5)
	tick(audio)
	var light_group := audio.groups[audio.sources[light.get_instance_id()].group_id]
	assert_lt(light_group.priority, audio.groups[audio.sources[first.get_instance_id()].group_id].priority)
	first.resolve_once(false)
	tick(audio)
	assert_true(audible(audio, companion), "묶음 일부가 사라져도 남은 기체는 유지")
	for stream: AudioStreamOggVorbis in UavLoopAudio.all_streams():
		assert_true(stream.loop)
		assert_has(CombatAudio.all_streams(), stream)

func test_louder_candidate_preempts_and_suppressed_source_returns_at_current_volume() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var quiet := source(audio, UavLoopAudio.MEDIUM, 6.0)
	var closer := source(audio, UavLoopAudio.MEDIUM, 4.0)
	tick(audio)
	assert_true(audible(audio, quiet))
	var loud := source(audio, UavLoopAudio.MEDIUM, 0.2)
	tick(audio, 20)
	assert_false(audible(audio, quiet))
	assert_true(audible(audio, loud))
	assert_true(audible(audio, closer))
	quiet.seconds = 0.2
	loud.resolve_once(true)
	tick(audio, 20)
	assert_true(audible(audio, quiet), "미재생 후보도 현재 볼륨으로 재점유")
	var group_id := audio.sources[quiet.get_instance_id()].group_id
	for voice: UavLoopAudio.Voice in audio.voices:
		if voice.group_id == group_id:
			assert_gt(voice.envelope, 0.95)

func test_total_cap_and_small_priority_changes_keep_owner() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var first := source(audio, UavLoopAudio.HEAVY, 4.0)
	var second := source(audio, UavLoopAudio.HEAVY, 1.0)
	source(audio, UavLoopAudio.MEDIUM, 1.0)
	source(audio, UavLoopAudio.LIGHT, 1.0)
	tick(audio)
	var newcomer := source(audio, UavLoopAudio.HEAVY, 6.0)
	tick(audio)
	newcomer.seconds = 7.8
	tick(audio)
	assert_true(audible(audio, first), "미세한 목표 볼륨 차이에는 기존 슬롯 유지")
	assert_false(audible(audio, newcomer))
	newcomer.seconds = 0.0
	tick(audio, 20)
	assert_true(audible(audio, newcomer))
	assert_true(audible(audio, second))
	var count := 0
	for voice: UavLoopAudio.Voice in audio.voices:
		if voice.player.playing:
			count += 1
	assert_lte(count, 4)
	assert_lte(audio._event_voice_count(UavLoopAudio.HEAVY), 2)

func test_departure_pause_rate_resolution_and_reset() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var threat := source(audio, UavLoopAudio.HEAVY, 0.0)
	tick(audio)
	threat.completed = true
	audio.update_audio(0.5, true, 2.0, true)
	assert_false(audio.sources[threat.get_instance_id()].departing)
	assert_true(audio.voices[0].player.stream_paused)
	audio.update_audio(0.5, false, 2.0, true)
	assert_eq(audio.voices[0].player.pitch_scale, 2.0)
	assert_almost_eq(audio.sources[threat.get_instance_id()].envelope, 0.5, 0.001)
	threat.resolve_once(true)
	tick(audio, 11)
	assert_false(audio.voices[0].player.playing)
	var fresh := source(audio, UavLoopAudio.MEDIUM, 0.0)
	tick(audio)
	audio.reset()
	tick(audio)
	assert_true(audio.sources.is_empty())
	assert_true(audio.groups.is_empty())
	fresh.resolved.emit(fresh, true, 0)
	assert_false(audio.voices[0].player.playing)

func test_silent_roles_aborts_and_completed_restore() -> void:
	var audio := add_child_autofree(UavLoopAudio.new()) as UavLoopAudio
	var silent := source(audio, &"", 0.0)
	assert_false(audio.sources.has(silent.get_instance_id()))
	var aborted := source(audio, UavLoopAudio.HEAVY, 1.0)
	tick(audio)
	aborted.aborting = true
	tick(audio, 11)
	assert_false(audible(audio, aborted))
	audio.reset()
	aborted.completed = true
	audio.register(aborted)
	assert_false(audio.sources.has(aborted.get_instance_id()), "투하 후 복원에는 루프를 다시 시작하지 않음")
