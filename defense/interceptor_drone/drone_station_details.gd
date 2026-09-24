extends Node3D
## Static deck dressing for the drone station: sealed launch pods, landing marks,
## deck rails and an antenna mast. Pods imply no drone count; launches stay live.

static var _geometry: Array[ArrayMesh] = []

func _ready() -> void:
	if _geometry.is_empty():
		_build()
	_geometry = ModelGeometry.replace_static_children(self, _geometry)

func _build() -> void:
	var pod := ModelGeometry.material(Color("3d4b46"), 0.35, 0.5)
	var lid := ModelGeometry.material(Color("27302e"), 0.4, 0.45)
	var marking := ModelGeometry.material(Color("c9b24a"), 0.0, 0.8)
	var rail := ModelGeometry.material(Color("8d938f"), 0.5, 0.5)
	var deck_top := 3.82
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var center := Vector3(corner.x * 3.2, deck_top, corner.y * 3.2)
		ModelGeometry.box(self, "Pod", Vector3(2.4, 1.3, 2.4), center + Vector3.UP * 0.65, pod)
		ModelGeometry.box(self, "PodLid", Vector3(2.1, 0.2, 2.1), center + Vector3.UP * 1.4, lid)
		ModelGeometry.box(self, "PodHinge", Vector3(2.1, 0.3, 0.25), center + Vector3(0.0, 1.35, corner.y * 1.05), lid)
	for axis: int in 2:
		var size := Vector3(4.6, 0.04, 0.35) if axis == 0 else Vector3(0.35, 0.04, 4.6)
		ModelGeometry.box(self, "LaunchMark", size, Vector3(0.0, deck_top + 0.02, 0.0), marking)
	for side: float in [-1.0, 1.0]:
		ModelGeometry.box(self, "EdgeStripe", Vector3(10.6, 0.04, 0.3), Vector3(0.0, deck_top + 0.02, side * 5.2), marking)
		ModelGeometry.box(self, "EdgeStripe", Vector3(0.3, 0.04, 10.6), Vector3(side * 5.2, deck_top + 0.02, 0.0), marking)
		ModelGeometry.box(self, "Rail", Vector3(11.0, 0.12, 0.12), Vector3(0.0, deck_top + 1.0, side * 5.45), rail)
		ModelGeometry.box(self, "Rail", Vector3(0.12, 0.12, 11.0), Vector3(side * 5.45, deck_top + 1.0, 0.0), rail)
		for post: int in 5:
			var along := -5.4 + float(post) * 2.7
			ModelGeometry.box(self, "Post", Vector3(0.12, 1.0, 0.12), Vector3(along, deck_top + 0.5, side * 5.45), rail)
			ModelGeometry.box(self, "Post", Vector3(0.12, 1.0, 0.12), Vector3(side * 5.45, deck_top + 0.5, along), rail)
	ModelGeometry.cylinder(self, "Mast", 0.14, 6.0, Vector3(5.0, deck_top + 3.0, -5.0), rail)
	ModelGeometry.box(self, "MastAntenna", Vector3(0.5, 1.2, 0.2), Vector3(5.0, deck_top + 5.6, -5.0), lid)
