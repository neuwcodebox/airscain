class_name UiAudio
extends Node

const CLICK := &"click"
const PLACEMENT_SUCCESS := &"placement_success"
const ACTION_COMPLETE := &"action_complete"
const ACTION_REJECTED := &"action_rejected"
const VOLUME_LINEAR := 0.7

const STREAMS: Dictionary[StringName, AudioStream] = {
	CLICK: preload("res://ui/audio/click.ogg"),
	PLACEMENT_SUCCESS: preload("res://ui/audio/placement_success.ogg"),
	ACTION_COMPLETE: preload("res://ui/audio/action_complete.ogg"),
	ACTION_REJECTED: preload("res://ui/audio/action_rejected.ogg"),
}

@export var enabled: bool = true

var event_counts: Dictionary[StringName, int] = {}
var click_player: AudioStreamPlayer
var feedback_player: AudioStreamPlayer
var prepared_stream_count: int = 0

func _ready() -> void:
	prepared_stream_count = prepare_samples()
	click_player = _create_player("ClickPlayer")
	feedback_player = _create_player("FeedbackPlayer")

static func prepare_samples() -> int:
	if not uses_sample_playback():
		return 0
	var streams: Array[AudioStream] = []
	for stream: AudioStream in STREAMS.values():
		if stream not in streams:
			streams.append(stream)
	for stream: AudioStream in streams:
		if not AudioServer.is_stream_registered_as_sample(stream):
			AudioServer.register_stream_as_sample(stream)
	return streams.size()

static func uses_sample_playback() -> bool:
	return OS.has_feature("web")

func connect_buttons(root: Node) -> void:
	_connect_buttons_recursive(root)

func play_event(event_id: StringName) -> bool:
	if not enabled or not STREAMS.has(event_id):
		return false
	var player := click_player if event_id == CLICK else feedback_player
	if player == null:
		return false
	if event_id != CLICK and click_player != null:
		click_player.stop()
	player.stream = STREAMS[event_id]
	player.play()
	event_counts[event_id] = event_counts.get(event_id, 0) + 1
	return true

func played_count(event_id: StringName) -> int:
	return event_counts.get(event_id, 0)

func stop_all() -> void:
	if click_player != null:
		click_player.stop()
	if feedback_player != null:
		feedback_player.stop()

func _create_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"UI"
	player.name = player_name
	player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if uses_sample_playback() else AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_db = linear_to_db(VOLUME_LINEAR)
	add_child(player)
	return player

func _connect_buttons_recursive(node: Node) -> void:
	var button := node as BaseButton
	if button != null and not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)
	for child: Node in node.get_children():
		_connect_buttons_recursive(child)

func _on_button_pressed() -> void:
	play_event(CLICK)
