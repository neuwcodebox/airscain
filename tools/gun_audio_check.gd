extends SceneTree

var samples := PackedVector2Array()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_cmdline_user_args().has("--airbursts"):
		await _check_airbursts()
		return
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, "GunCheck")
	AudioServer.add_bus_effect(bus_index, capture)
	var context := CombatAudio.new()
	root.add_child(context)
	var voice := GunAudio.new()
	root.add_child(voice)
	voice.context = context
	voice.bus = "GunCheck"
	var started := Time.get_ticks_msec()
	var seen_loop := false
	var seen_end := false
	while Time.get_ticks_msec() - started < 15300:
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if elapsed < 7.0 or (elapsed >= 7.35 and elapsed < 9.0):
			voice.notify_shot()
		if voice.playing:
			var clip := (voice.get_stream_playback() as AudioStreamPlaybackInteractive).get_current_clip_index()
			seen_loop = seen_loop or clip == GunAudio.LOOP
			seen_end = seen_end or clip == GunAudio.END
		await process_frame
		samples.append_array(capture.get_buffer(capture.get_frames_available()))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate())
	var data := PackedByteArray()
	data.resize(samples.size() * 4)
	for index: int in samples.size():
		data.encode_s16(index * 4, int(clampf(samples[index].x, -1.0, 1.0) * 32767))
		data.encode_s16(index * 4 + 2, int(clampf(samples[index].y, -1.0, 1.0) * 32767))
	wav.data = data
	var error := wav.save_to_wav("/tmp/airscain_gun_sequence.wav")
	var ok := seen_loop and seen_end and voice.starts == 2 and voice.endings == 2 and not voice.playing and error == OK
	print("GUN_AUDIO_CHECK ok=%s starts=%d endings=%d loop=%s end=%s frames=%d" % [ok, voice.starts, voice.endings, seen_loop, seen_end, samples.size()])
	voice.queue_free()
	context.queue_free()
	await process_frame
	AudioServer.remove_bus(bus_index)
	quit(0 if ok else 1)

func _check_airbursts() -> void:
	var context := CombatAudio.new()
	root.add_child(context)
	var voice := context.gun_airbursts
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, capture)
	var started := Time.get_ticks_msec()
	var prior_position := 0.0
	var wraps := 0
	var peak := 0.0
	while Time.get_ticks_msec() - started < 11000:
		if Time.get_ticks_msec() - started < 10000:
			for gun: int in 3:
				context.on_gun_round_detonated(Vector3.ZERO, &"timeout")
		var position := voice.get_playback_position()
		if voice.playing and position < prior_position - 1.0:
			wraps += 1
		prior_position = position
		await process_frame
		for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	var ok := wraps >= 2 and voice.starts == 1 and not voice.playing and peak > 0.01
	print("GUN_AIRBURST_CHECK ok=%s starts=%d wraps=%d peak=%.4f stopped=%s" % [ok, voice.starts, wraps, peak, not voice.playing])
	context.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	quit(0 if ok else 1)
