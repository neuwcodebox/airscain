class_name AudioPlayback
extends RefCounted
## Shared transport. Callers own event selection, voice budgets and envelopes.

const WEB_ADAPTER_PATH := "res://effects/audio/web_sample_playback.js"
static var _web_ready: bool = false

static func uses_samples() -> bool:
	return OS.has_feature("web")

static func ensure_backend() -> bool:
	if not uses_samples() or _web_ready:
		return true
	var source := FileAccess.get_file_as_string(WEB_ADAPTER_PATH)
	_web_ready = not source.is_empty() and bool(JavaScriptBridge.eval(source, false))
	if not _web_ready:
		push_error("Web audio transport could not be initialized; check the export and Godot adapter compatibility.")
		(Engine.get_main_loop() as SceneTree).quit(1)
	return _web_ready

static func configure(player: AudioStreamPlayer) -> void:
	if ensure_backend():
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if uses_samples() else AudioServer.PLAYBACK_TYPE_STREAM

static func create_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	configure(player)
	return player

static func prepare_streams(streams: Array[AudioStream]) -> int:
	if not uses_samples() or not ensure_backend():
		return 0
	var prepared: Array[AudioStream] = []
	for stream: AudioStream in streams:
		if stream in prepared:
			continue
		if not AudioServer.is_stream_registered_as_sample(stream):
			AudioServer.register_stream_as_sample(stream)
		# Godot's Ogg Sample registration omits loop_offset. Carry the resource
		# contract explicitly instead of trusting the driver's loop metadata.
		var region := loop_region(stream)
		JavaScriptBridge.eval("GodotAudio.airscainSetLoopRegion(%s, %s, %s, %s)" % [
			JSON.stringify(str(stream.get_instance_id())), "true" if region["begin"] >= 0.0 else "false",
			JSON.stringify(maxf(0.0, region["begin"])), JSON.stringify(region["end"])], false)
		prepared.append(stream)
	return prepared.size()

static func loop_region(stream: AudioStream) -> Dictionary[String, float]:
	var end := stream.get_length()
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		return {"begin": ogg.loop_offset if ogg.loop else -1.0, "end": end}
	if stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		return {"begin": mp3.loop_offset if mp3.loop else -1.0, "end": end}
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			return {"begin": float(wav.loop_begin) / wav.mix_rate, "end": float(wav.loop_end) / wav.mix_rate}
	return {"begin": -1.0, "end": end}

static func play(player: AudioStreamPlayer, from_position: float = 0.0) -> void:
	if player.stream == null:
		return
	if uses_samples():
		prepare_streams([player.stream])
	var paused := player.stream_paused
	player.play(from_position)
	sync(player, paused, player.pitch_scale)

static func sync(player: AudioStreamPlayer, paused: bool, rate: float = 1.0) -> void:
	# Apply rate before resuming so the new source starts at the intended speed.
	var pitch := maxf(0.01, rate)
	if not is_equal_approx(player.pitch_scale, pitch):
		player.pitch_scale = pitch
	if player.stream_paused != paused:
		player.stream_paused = paused

static func sync_tween(tween: Tween, paused: bool) -> void:
	if not tween.is_valid():
		return
	if paused and tween.is_running():
		tween.pause()
	elif not paused and not tween.is_running():
		tween.play()
