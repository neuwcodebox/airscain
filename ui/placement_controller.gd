class_name PlacementController
extends Node3D

const DEPENDENCY_REFRESH_INTERVAL := 0.2
const POWER_LINK_COLOR := Color(1.0, 0.72, 0.24, 0.9)
const SUPPORT_LINK_COLOR := Color(0.36, 1.0, 0.54, 0.9)
const POWER_LINK_HEIGHT := 9.0
const POWER_DASH_LENGTH := 14.0
const POWER_DASH_GAP := 9.0

signal feedback_changed(message: String, transient: bool)
signal asset_selected(unit: DefenseUnit)
signal world_selected(position: Vector3, screen_position: Vector2)
signal sandbox_threat_placement_requested(definition: ThreatDefinition, position: Vector3)
signal placement_preview_changed(definition: DefenseDefinition, position: Vector3, active: bool)

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
var dependency_refresh_remaining: float = 0.0
var last_dependency_definition: DefenseDefinition
var last_dependency_position: Vector3
var dependency_preview_active: bool = false
var power_dependency_link_count: int = 0
var power_dependency_lines := MeshInstance3D.new()
var power_dependency_material := StandardMaterial3D.new()
var support_dependency_link_count: int = 0
var support_dependency_lines := MeshInstance3D.new()
var support_dependency_material := StandardMaterial3D.new()

func _ready() -> void:
	power_dependency_lines.name = "PowerDependencyLines"
	power_dependency_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	power_dependency_material.vertex_color_use_as_albedo = true
	power_dependency_material.no_depth_test = true
	power_dependency_lines.material_override = power_dependency_material
	add_child(power_dependency_lines)
	support_dependency_lines.name = "SupportDependencyLines"
	support_dependency_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	support_dependency_material.vertex_color_use_as_albedo = true
	support_dependency_material.no_depth_test = true
	support_dependency_lines.material_override = support_dependency_material
	add_child(support_dependency_lines)

func configure(session_value: GameSession, battlefield_value: Battlefield, camera_value: Camera3D, defense_parent_value: Node3D, projectile_parent_value: Node3D, registry_value: ThreatRegistry, relocation_manager_value: RelocationManager) -> void:
	session = session_value
	battlefield = battlefield_value
	battlefield.set_rooftop_pads_visible(false)
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
	battlefield.set_rooftop_pads_visible(definition.placement_profile.rooftop_allowed)
	_create_preview()
	_publish_dependency_preview(definition, Vector3.ZERO, false, true)
	feedback_changed.emit("지도에서 배치 위치를 선택하세요    우클릭 또는 Esc: 취소", false)

func select_relocation(unit: DefenseUnit) -> void:
	selected_threat = null
	relocating_unit = unit
	selected = unit.definition
	battlefield.set_rooftop_pads_visible(selected.placement_profile.rooftop_allowed)
	_create_preview()
	_publish_dependency_preview(null, Vector3.ZERO, false, true)
	feedback_changed.emit("새 위치를 선택하세요    우클릭 또는 Esc: 취소", false)

func select_sandbox_threat(definition: ThreatDefinition) -> void:
	selected = null
	relocating_unit = null
	selected_threat = definition
	battlefield.set_rooftop_pads_visible(false)
	_create_threat_preview()
	_publish_dependency_preview(null, Vector3.ZERO, false, true)
	feedback_changed.emit("지도에서 위협 투입 위치를 선택하세요    우클릭 또는 Esc: 취소", false)

func cancel() -> void:
	selected = null
	selected_threat = null
	relocating_unit = null
	if battlefield != null:
		battlefield.set_rooftop_pads_visible(false)
	if preview != null:
		preview.queue_free()
	preview = null
	_publish_dependency_preview(null, Vector3.ZERO, false, true)
	feedback_changed.emit("", false)

func _process(delta: float) -> void:
	if selected == null and selected_threat == null or preview == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var hit := _terrain_hit(mouse)
	if hit.is_empty():
		preview.visible = false
		candidate_valid = false
		_publish_dependency_preview(null, Vector3.ZERO, false)
		feedback_changed.emit("배치 위치를 지도 위에서 선택하세요", false)
		return
	preview.visible = true
	candidate_position = hit.position if selected_threat != null else battlefield.snap_placement_position(hit.position, selected.placement_profile)
	preview.global_position = candidate_position
	var result := {"valid": true, "reason": "위협 투입 가능"} if selected_threat != null else _validation()
	candidate_valid = result.valid
	if selected != null and selected_threat == null and relocating_unit == null:
		dependency_refresh_remaining -= delta
		var refresh_due := dependency_refresh_remaining <= 0.0
		_publish_dependency_preview(selected, candidate_position, true, refresh_due)
		if refresh_due:
			dependency_refresh_remaining = DEPENDENCY_REFRESH_INTERVAL
	preview_material.albedo_color = Color(0.18, 0.95, 0.42, 0.48) if candidate_valid else Color(1.0, 0.18, 0.12, 0.52)
	feedback_changed.emit(String(result.reason), false)

func _unhandled_input(event: InputEvent) -> void:
	if selected == null and selected_threat == null:
		if event is InputEventMouseButton:
			var selection_click := event as InputEventMouseButton
			if selection_click.pressed and selection_click.button_index == MOUSE_BUTTON_LEFT and get_viewport().gui_get_hovered_control() == null:
				var screen_position := get_viewport().get_mouse_position()
				var hit := _terrain_hit(screen_position)
				if not hit.is_empty():
					if pick_asset_at(hit.position) == null:
						world_selected.emit(hit.position, screen_position)
				else:
					world_selected.emit(Vector3.INF, screen_position)
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
				request_selected_sandbox_threat_placement()
				get_viewport().set_input_as_handled()
				return
			request_selected_defense_placement()
			get_viewport().set_input_as_handled()

func request_selected_defense_placement() -> bool:
	if selected == null:
		return false
	var result: Dictionary
	if relocating_unit != null:
		var moved := relocation_manager.request_relocation(relocating_unit, candidate_position)
		result = {"success": moved, "reason": "재배치 시작" if moved else "재배치할 수 없습니다"}
	else:
		result = session.request_placement(selected, candidate_position, battlefield, defense_parent, registry, projectile_parent)
	feedback_changed.emit(String(result.reason), true)
	if not result.success:
		return false
	if session.unlimited_budget and relocating_unit == null:
		_publish_dependency_preview(selected, candidate_position, true, true)
		feedback_changed.emit("배치했습니다. 같은 자산을 계속 배치할 수 있습니다.", true)
	else:
		cancel()
	return true

func request_selected_sandbox_threat_placement() -> bool:
	if selected_threat == null:
		return false
	sandbox_threat_placement_requested.emit(selected_threat, candidate_position)
	feedback_changed.emit("위협을 투입했습니다. 같은 위협을 계속 투입할 수 있습니다.", true)
	return true

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
	var displayed_range := (selected as SupportFacilityDefinition).service_range if selected is SupportFacilityDefinition else selected.preview_range
	disc.inner_radius = displayed_range - 2.5
	disc.outer_radius = displayed_range
	disc.rings = 96
	disc.ring_segments = 8
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

func _publish_dependency_preview(definition: DefenseDefinition, position: Vector3, active: bool, force: bool = false) -> void:
	if not force and definition == last_dependency_definition and active == dependency_preview_active and (not active or position.is_equal_approx(last_dependency_position)):
		return
	last_dependency_definition = definition
	last_dependency_position = position
	dependency_preview_active = active
	placement_preview_changed.emit(definition, position, active)

func show_dependency_preview(definition: DefenseDefinition, position: Vector3, active: bool) -> void:
	power_dependency_link_count = 0
	support_dependency_link_count = 0
	if not active or definition == null or defense_parent == null:
		power_dependency_lines.mesh = null
		support_dependency_lines.mesh = null
		return
	var power_targets: Array[DefenseUnit] = []
	if definition is SupportFacilityDefinition:
		for child: Node in defense_parent.get_children():
			var consumer := child as DefenseUnit
			if consumer != null and consumer.active and consumer.power_demand() > 0.0 and position.distance_to(consumer.global_position) > 0.01:
				power_targets.append(consumer)
	elif definition.placement_power_demand() > 0.0:
		for child: Node in defense_parent.get_children():
			var facility := child as SupportFacility
			if facility != null and facility.active and position.distance_to(facility.global_position) > 0.01:
				power_targets.append(facility)
	_draw_dependency_lines(power_dependency_lines, power_targets, position, POWER_LINK_COLOR, true)
	power_dependency_link_count = power_targets.size()
	var support_targets: Array[DefenseUnit] = []
	if definition is SupportFacilityDefinition:
		var service_range := (definition as SupportFacilityDefinition).service_range
		for child: Node in defense_parent.get_children():
			var unit := child as DefenseUnit
			if unit == null or position.distance_to(unit.global_position) <= 0.01:
				continue
			var offset := Vector2(unit.global_position.x - position.x, unit.global_position.z - position.z)
			if offset.length() <= service_range:
				support_targets.append(unit)
	_draw_dependency_lines(support_dependency_lines, support_targets, position, SUPPORT_LINK_COLOR, false)
	support_dependency_link_count = support_targets.size()

func _draw_dependency_lines(line_mesh: MeshInstance3D, targets: Array[DefenseUnit], position: Vector3, color: Color, dashed: bool) -> void:
	if targets.is_empty():
		line_mesh.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var start := position + Vector3.UP * POWER_LINK_HEIGHT
	for target: DefenseUnit in targets:
		var finish := target.global_position + Vector3.UP * POWER_LINK_HEIGHT
		if dashed:
			_add_dashed_segment(mesh, start, finish, color)
		else:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(start)
			mesh.surface_add_vertex(finish)
	mesh.surface_end()
	line_mesh.mesh = mesh

func _add_dashed_segment(mesh: ImmediateMesh, start: Vector3, finish: Vector3, color: Color) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.01:
		return
	var direction := start.direction_to(finish)
	var cursor := 0.0
	while cursor < distance:
		var dash_end := minf(cursor + POWER_DASH_LENGTH, distance)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(start + direction * cursor)
		mesh.surface_add_vertex(start + direction * dash_end)
		cursor += POWER_DASH_LENGTH + POWER_DASH_GAP
