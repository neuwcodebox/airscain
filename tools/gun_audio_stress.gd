extends Node

signal completed(result: Dictionary)

func _ready() -> void:
	var context := CombatAudio.new()
	add_child(context)
	var button := Button.new()
	button.text = "Start 24-gun audio stress test"
	button.position = Vector2(80, 80)
	button.size = Vector2(600, 100)
	add_child(button)
	if OS.has_feature("web"):
		await button.pressed
	button.queue_free()
	var voices: Array[GunAudio] = []
	for index: int in 24:
		var voice := GunAudio.new()
		voice.context = context
		add_child(voice)
		voices.append(voice)
	var started := Time.get_ticks_msec()
	var frame := 0
	while Time.get_ticks_msec() - started < 17000:
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		context.simulation_paused = elapsed >= 6.0 and elapsed < 7.0
		if elapsed < 10.0:
			for voice: GunAudio in voices:
				voice.notify_shot()
			context.on_gun_round_detonated(Vector3.ZERO, &"timeout")
		if frame % 40 == 0 and elapsed < 10.0:
			OS.delay_msec(180)
		frame += 1
		await get_tree().process_frame
	var starts := 0
	var endings := 0
	var stopped := true
	for voice: GunAudio in voices:
		starts += voice.starts
		endings += voice.endings
		stopped = stopped and not voice.playing and not voice.ending_player.playing
	var result := {"starts": starts, "endings": endings, "stopped": stopped, "sample": voices[0].playback_type == AudioServer.PLAYBACK_TYPE_SAMPLE, "registered": context.prepared_stream_count, "voices_left": context.gun_voices.size()}
	print("GUN_STRESS ", JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__gunStressResult = " + JSON.stringify(result))
	for voice: GunAudio in voices:
		voice.queue_free()
	await get_tree().process_frame
	context.queue_free()
	await get_tree().process_frame
	completed.emit(result)
