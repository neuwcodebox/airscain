extends Node
## Transport contract probe: --clip=uav_light|uav_medium|uav_heavy|gun|jet|missile.
## Starts at 4x, pauses twice, changes rate while paused, then checks two full loops
## or natural one-shot completion. Web builds must include tools and use this scene.

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var clip := "uav_medium"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--clip="):
			clip = argument.trim_prefix("--clip=")
	UavLoopAudio.all_streams()
	var clips: Dictionary[String, AudioStream] = {
		"uav_light": UavLoopAudio.STREAMS[UavLoopAudio.LIGHT],
		"uav_medium": UavLoopAudio.STREAMS[UavLoopAudio.MEDIUM],
		"uav_heavy": UavLoopAudio.STREAMS[UavLoopAudio.HEAVY],
		"gun": GunAudio.sustain_stream(),
		"jet": ThreatApproachAudio.STREAMS[0],
		"missile": CombatAudio.STREAM_GROUPS[CombatAudio.LONG_MISSILE][0],
	}
	if not clips.has(clip):
		push_error("Unknown audio probe clip: %s" % clip)
		get_tree().quit(1)
		return
	var stream := clips[clip] as AudioStreamOggVorbis
	AudioPlayback.prepare_streams([stream])
	var player := AudioPlayback.create_player()
	add_child(player)
	player.stream = stream
	player.bus = &"Guns" if clip == "gun" else (&"Missiles" if clip == "missile" else &"Master")
	var ended: Array[int] = [0]
	player.finished.connect(func() -> void:
		ended[0] += 1
		print("AUDIO_TRANSPORT finished=%d" % ended[0]))
	AudioPlayback.sync(player, false, 4.0)
	var offset := 0.0 if clip == "gun" else maxf(0.0, stream.get_length() - (0.15 if stream.loop else 5.0))
	AudioPlayback.play(player, offset)
	print("AUDIO_TRANSPORT start clip=%s length=%.6f loop=%s begin=%.6f offset=%.6f" % [clip, stream.get_length(), stream.loop, stream.loop_offset, offset])
	if OS.has_feature("web"):
		print("AUDIO_TRANSPORT samples=" + str(JavaScriptBridge.eval("JSON.stringify(Array.from(GodotAudio.samples.values()).map(s => ({duration:s.getAudioBuffer().duration, begin:s.loopBegin, end:s.loopEnd, rate:s.sampleRate,region:s.airscainRegion})))", false)))
	var elapsed := 0.0
	var phase := -1
	var duration := 2.9 + stream.get_length() * 0.5 if stream.loop else 3.5
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var next_phase := 0 if elapsed < 0.7 else (1 if elapsed < 1.2 else (2 if elapsed < 1.9 else (3 if elapsed < 2.4 else 4)))
		var paused := next_phase == 1 or next_phase == 3
		var rate := 2.0 if next_phase == 1 or next_phase == 2 else 4.0
		AudioPlayback.sync(player, paused, rate)
		if phase != next_phase:
			phase = next_phase
			print("AUDIO_TRANSPORT phase=%d position=%.6f" % [phase, player.get_playback_position()])
	var ok := ended[0] == (0 if stream.loop else 1)
	player.stop()
	print("AUDIO_TRANSPORT stopped")
	await get_tree().create_timer(0.3).timeout
	player.queue_free()
	print("AUDIO_TRANSPORT complete ok=%s" % ok)
	get_tree().quit(0 if ok else 1)
