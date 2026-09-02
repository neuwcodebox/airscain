class_name PlacementController
extends Node3D

signal feedback_changed(message: String)
signal asset_selected(unit: DefenseUnit)
signal world_selected(position: Vector3, screen_position: Vector2)
signal sandbox_threat_placement_requested(definition: ThreatDefinition, position: Vector3)

var session: GameSession
var battlefield: Battlefield
var camera: Camera3D
var defense_parent: Node3D
var projectile_parent: Node3D
var registry: ThreatRegistry
var relocation_manager: RelocationManager
var selected: DefenseDefinition
var selected_threat: ThreatDefinition
var relocating_unit: DefenseUnit
var candidate_position: Vector3
var candidate_valid: bool = false
var preview: Node3D
var range_disc: MeshInstance3D
var preview_material := StandardMaterial3D.new()

func configure(session_value: GameSession, battlefield_value: Battlefield, camera_value: Camera3D, defense_parent_value: Node3D, projectile_parent_value: Node3D, registry_value: ThreatRegistry, relocation_manager_value: RelocationManager) -> void:
	session = session_value
	battlefield = battlefield_value
	camera = camera_value
	defense_parent = defense_parent_value
	projectile_parent = projectile_parent_value
	registry = registry_value
	relocation_manager = relocation_manager_value
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func select(definition: DefenseDefinition) -> void:
	relocating_unit = null
	selected_threat = null
	selected = definition
	_create_preview()
	feedback_changed.emit("좌클릭 배치 · 우클릭/Esc 취소")

func select_relocation(unit: DefenseUnit) -> void:
	selected_threat = null
	relocating_unit = unit
	selected = unit.definition
	_create_preview()
	feedback_changed.emit("새 위치를 좌클릭 · 우클릭/Esc 취소")

func select_sandbox_threat(definition: ThreatDefinition) -> void:
	selected = null
	relocating_unit = null
	selected_threat = definition
	_create_threat_preview()
	feedback_changed.emit("지도에서 위협 투입 위치를 좌클릭 · 우클릭/Esc 취소")

func cancel() -> void:
	selected = null
	selected_threat = null
	relocating_unit = null
	if preview != null:
		preview.queue_free()
	preview = null
	feedback_changed.emit("")

func _process(_delta: float) -> void:
	if selected == null and selected_threat == null or preview == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var hit := _terrain_hit(mouse)
	if hit.is_empty():
		preview.visible = false
		candidate_valid = false
		feedback_changed.emit("지도 위를 가리켜 주세요")
		return
	preview.visible = true
	candidate_position = hit.position if selected_threat != null else battlefield.snap_placement_position(hit.position, selected.placement_profile)
	preview.global_position = candidate_position
	var result := {"valid": true, "reason": "위협 투입 가능"} if selected_threat != null else _validation()
	candidate_valid = result.valid
	preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if candidate_valid else Color(1.0, 0.18, 0.12, 0.52)
	feedback_changed.emit(result.reason)

func _unhandled_input(event: InputEvent) -> void:
	if selected == null and selected_threat == null:
		if event is InputEventMouseButton:
			var selection_click := event as InputEventMouseButton
			if selection_click.pressed and selection_click.button_index == MOUSE_BUTTON_LEFT and get_viewport().gui_get_hovered_control() == null:
				var hit := _terrain_hit(get_viewport().get_mouse_position())
				if not hit.is_empty():
					if pick_asset_at(hit.position) == null:
						world_selected.emit(hit.position, get_viewport().get_mouse_position())
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
			if selected_threat != null:
				sandbox_threat_placement_requested.emit(selected_threat, candidate_position)
				feedback_changed.emit("위협을 투입했습니다")
				cancel()
				get_viewport().set_input_as_handled()
				return
			var result: Dictionary
			if relocating_unit != null:
				var moved := relocation_manager.request_relocation(relocating_unit, candidate_position)
				result = {"success": moved, "reason": "재배치 시작" if moved else "재배치할 수 없습니다"}
			else:
				result = session.request_placement(selected, candidate_position, battlefield, defense_parent, registry, projectile_parent)
			feedback_changed.emit(result.reason)
			if result.success:
				cancel()
			get_viewport().set_input_as_handled()

func _validation() -> Dictionary:
	if relocating_unit == null and not session.unlimited_budget and session.budget < selected.price:
		return {"valid": false, "reason": "예산이 부족합니다"}
	return battlefield.placement_result(candidate_position, selected.placement_profile)

func pick_asset_at(world_position: Vector3) -> DefenseUnit:
	var picked: DefenseUnit
	var nearest_distance := 24.0
	for child: Node in defense_parent.get_children():
		var unit := child as DefenseUnit
		if unit == null:
			continue
		var flat_distance := Vector2(unit.global_position.x - world_position.x, unit.global_position.z - world_position.z).length()
		if flat_distance < nearest_distance:
			nearest_distance = flat_distance
			picked = unit
	if picked != null:
		asset_selected.emit(picked)
	return picked

func _terrain_hit(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 3000.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(query)

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
	var disc := TorusMesh.new()
	disc.inner_radius = selected.preview_range - 2.5
	disc.outer_radius = selected.preview_range
	disc.rings = 8
	disc.ring_segments = 96
	wall_material_setup()
	range_disc.mesh = disc
	range_disc.position.y = 1.5
	range_disc.material_override = preview_material
	preview.add_child(range_disc)

func _create_threat_preview() -> void:
	if preview != null:
		preview.queue_free()
	preview = Node3D.new()
	preview.name = "ThreatPlacementPreview"
	add_child(preview)
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 8.0
	sphere.height = 16.0
	marker.mesh = sphere
	preview_material.albedo_color = Color(1.0, 0.2, 0.12, 0.62)
	marker.material_override = preview_material
	marker.position.y = 8.0
	preview.add_child(marker)

func wall_material_setup() -> void:
	preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_material.no_depth_test = false
