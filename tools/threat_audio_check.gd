extends Node
## Run with --scene res://tools/threat_audio_check.tscn -- --event=missile_approach --variant=0.
## Web exports must include tools; inspect AudioBufferSourceNode starts and output.

class Source:
	extends ThreatUnit
	var seconds: float = 0.0
	func presentation_action_seconds() -> float:
		return seconds

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var event: StringName = UavLoopAudio.MEDIUM
	var variant := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--event="):
			event = StringName(argument.trim_prefix("--event="))
		elif argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=").to_int()
	if event not in [UavLoopAudio.LIGHT, UavLoopAudio.MEDIUM, UavLoopAudio.HEAVY, ThreatApproachAudio.EVENT, ThreatApproachAudio.CRUISE_EVENT]:
		push_error("Unknown threat audio event: %s" % event)
		get_tree().quit(1)
		return
	var context := CombatAudio.new()
	add_child(context)
	context.set_process(false)
	var source := Source.new()
	source.definition = ThreatDefinition.new()
	if UavLoopAudio.STREAMS.has(event):
		source.definition.loop_audio_event = event
	else:
		source.definition.approach_audio_event = event
		var approach := context.cruise_approaches if event == ThreatApproachAudio.CRUISE_EVENT else context.approaches
		approach.next_variant = posmod(variant, approach.streams.size())
		source.seconds = approach.lead_seconds
	add_child(source)
	context.register_threat(source)
	print("THREAT_AUDIO_CHECK start event=%s variant=%d sample=%s" % [event, variant, CombatAudio.uses_sample_playback()])
	var elapsed := 0.0
	var phase := -1
	while elapsed < 4.0:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		var next_phase := 0 if elapsed < 1.0 else (1 if elapsed < 1.5 else (2 if elapsed < 2.5 else (3 if elapsed < 3.5 else 4)))
		if next_phase != phase:
			phase = next_phase
			print("THREAT_AUDIO_CHECK phase=%d elapsed=%.3f" % [phase, elapsed])
			if phase == 4:
				source.resolve_once(true)
		context.simulation_paused = phase == 1
		context.simulation_rate = 2.0 if phase == 3 else 1.0
		context._process(delta)
	context.stop_all()
	source.queue_free()
	context.queue_free()
	await get_tree().process_frame
	print("THREAT_AUDIO_CHECK complete event=%s" % event)
	get_tree().quit()
