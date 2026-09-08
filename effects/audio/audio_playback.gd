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
	_web_ready = not source.is_empty() and JavaScriptBridge.eval(source, false) == true
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
		prepared.append(stream)
	return prepared.size()

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
