class_name TrackDisplay
extends Node3D

var player_knowledge: Node
var markers: Dictionary[int, TrackMarker] = {}

func configure(player_knowledge_value: Node) -> void:
	player_knowledge = player_knowledge_value
	player_knowledge.connect("track_created", _on_track_created)
	player_knowledge.connect("track_updated", _on_track_updated)
	player_knowledge.connect("track_state_changed", _on_track_state_changed)
	player_knowledge.connect("track_removed", _on_track_removed)
	var existing_tracks: Array[PlayerTrack] = player_knowledge.call("get_active_tracks")
	for track: PlayerTrack in existing_tracks:
		_on_track_created(track)

func reset() -> void:
	for marker: TrackMarker in markers.values():
		if is_instance_valid(marker):
			marker.free()
	markers.clear()

func _on_track_created(track: PlayerTrack) -> void:
	if markers.has(track.track_id):
		return
	var marker := TrackMarker.new()
	marker.name = "TrackMarker%d" % track.track_id
	add_child(marker)
	marker.setup(track)
	markers[track.track_id] = marker

func _on_track_state_changed(track: PlayerTrack, _previous_state: PlayerTrack.State) -> void:
	var marker := markers.get(track.track_id) as TrackMarker
	if marker != null:
		marker.refresh_state()

func _on_track_updated(track: PlayerTrack) -> void:
	var marker := markers.get(track.track_id) as TrackMarker
	if marker != null:
		marker.refresh_state()

func _on_track_removed(track_id: int) -> void:
	var marker := markers.get(track_id) as TrackMarker
	if marker != null:
		marker.queue_free()
	markers.erase(track_id)
