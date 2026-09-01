class_name PlacementController
extends Node3D

signal feedback_changed(message: String)

var session: GameSession
var battlefield: Battlefield
var camera: Camera3D
var defense_parent: Node3D
var projectile_parent: Node3D
var registry: ThreatRegistry
var selected: DefenseDefinition
var candidate_position: Vector3
var candidate_valid: bool = false
var preview: Node3D
var range_disc: MeshInstance3D
var preview_material := StandardMaterial3D.new()

func configure(session_value: GameSession, battlefield_value: Battlefield, camera_value: Camera3D, defense_parent_value: Node3D, projectile_parent_value: Node3D, registry_value: ThreatRegistry) -> void:
	session = session_value
	battlefield = battlefield_value
	camera = camera_value
	defense_parent = defense_parent_value
	projectile_parent = projectile_parent_value
	registry = registry_value
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func select(definition: DefenseDefinition) -> void:
	selected = definition
	_create_preview()
	feedback_changed.emit("좌클릭 배치 · 우클릭/Esc 취소")

func cancel() -> void:
	selected = null
	if preview != null:
		preview.queue_free()
	preview = null
	feedback_changed.emit("")

func _process(_delta: float) -> void:
	if selected == null or preview == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 3000.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		preview.visible = false
		candidate_valid = false
		feedback_changed.emit("지도 위를 가리켜 주세요")
		return
	preview.visible = true
	candidate_position = hit.position
	candidate_position.y = battlefield.terrain_height(candidate_position.x, candidate_position.z)
	preview.global_position = candidate_position
	var result := _validation()
	candidate_valid = result.valid
	preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if candidate_valid else Color(1.0, 0.18, 0.12, 0.52)
	feedback_changed.emit(result.reason)

func _unhandled_input(event: InputEvent) -> void:
	if selected == null:
		return
	if event.is_action_pressed("cancel_placement"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if not mouse_button.pressed:
			return
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if get_viewport().gui_get_hovered_control() != null:
				return
			var result := session.request_placement(selected, candidate_position, battlefield, defense_parent, registry, projectile_parent)
			feedback_changed.emit(result.reason)
			if result.success:
				cancel()
			get_viewport().set_input_as_handled()

func _validation() -> Dictionary:
	if session.budget < selected.price:
		return {"valid": false, "reason": "예산이 부족합니다"}
	return battlefield.placement_result(candidate_position, selected.placement_profile)

func _create_preview() -> void:
	if preview != null:
		preview.queue_free()
	preview = Node3D.new()
	preview.name = "PlacementPreview"
	add_child(preview)
	var base := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = selected.placement_profile.footprint_radius * 0.6
	cylinder.bottom_radius = selected.placement_profile.footprint_radius * 0.75
	cylinder.height = 7.0
	base.mesh = cylinder
	base.position.y = 3.5
	base.material_override = preview_material
	preview.add_child(base)
	range_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = selected.preview_range
	disc.bottom_radius = selected.preview_range
	disc.height = 0.35
	wall_material_setup()
	range_disc.mesh = disc
	range_disc.position.y = 0.4
	range_disc.material_override = preview_material
	preview.add_child(range_disc)

func wall_material_setup() -> void:
	preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_material.no_depth_test = false

