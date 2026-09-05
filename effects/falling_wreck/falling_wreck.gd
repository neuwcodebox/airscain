class_name FallingWreckEffect
extends Node3D

const FALL_TIMEOUT := 10.0
static var wreck_materials: Dictionary[Color, StandardMaterial3D] = {}

var velocity: Vector3
var ground_height: float
var battlefield: Battlefield
var elapsed: float = 0.0
var impacted: bool = false
var impact_flash_enabled: bool = true
var smoke_released: bool = false

@onready var wreck: Node3D = $Wreck
@onready var body: MeshInstance3D = $Wreck/Body
@onready var wing: MeshInstance3D = $Wreck/Wing
@onready var smoke: LingeringSmokeTrail = $SmokeTrail

func setup(color: Color, initial_velocity: Vector3, ground_height_value: float, wreck_scale: float = 1.0, smoke_enabled: bool = true, flash_enabled: bool = true) -> void:
	velocity = initial_velocity * 0.55 + Vector3(0.0, -4.0, 0.0)
	ground_height = ground_height_value
	impact_flash_enabled = flash_enabled
	wreck.scale = Vector3.ONE * wreck_scale
	_set_wreck_material(body, color)
	_set_wreck_material(wing, color)
	smoke.emitting = smoke_enabled

func use_airframe(source: Node3D) -> void:
	# Share existing geometry; copy only visual nodes, never AI, lights or trails.
	for child: Node in wreck.get_children():
		child.free()
	wreck.scale = Vector3.ONE
	wreck.basis = source.global_basis
	_copy_visuals(source, wreck)

func _copy_visuals(source: Node, destination: Node3D) -> void:
	for child: Node in source.get_children():
		if not child is Node3D or not (child as Node3D).visible:
			continue
		if child is Light3D or child is GeometryInstance3D and not child is MeshInstance3D:
			continue
		var copy: Node3D
		if child is MeshInstance3D:
			var original := child as MeshInstance3D
			if original.mesh == null:
				continue
			var material := original.get_active_material(0) as StandardMaterial3D
			if material != null and material.emission_enabled:
				continue
			var mesh_copy := MeshInstance3D.new()
			mesh_copy.mesh = original.mesh
			for surface: int in original.mesh.get_surface_count():
				mesh_copy.set_surface_override_material(surface, _charred_material(original.get_active_material(surface)))
			copy = mesh_copy
		else:
			copy = Node3D.new()
		copy.name = child.name
		copy.transform = (child as Node3D).transform
		destination.add_child(copy)
		_copy_visuals(child, copy)

static func _charred_material(source: Material) -> Material:
	if not source is StandardMaterial3D:
		return source
	var color := (source as StandardMaterial3D).albedo_color
	if not wreck_materials.has(color):
		var surface := StandardMaterial3D.new()
		surface.albedo_color = color.darkened(0.48)
		surface.roughness = 0.92
		surface.metallic = 0.25
		wreck_materials[color] = surface
	return wreck_materials[color]

func _set_wreck_material(mesh_instance: MeshInstance3D, color: Color) -> void:
	var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = color.darkened(0.45)
	mesh_instance.material_override = material

func _process(delta: float) -> void:
	elapsed += delta
	if not impacted:
		var previous_position := global_position
		velocity += Vector3.DOWN * 34.0 * delta
		global_position += velocity * delta
		var hit := false
		if battlefield != null:
			var terrain_hit := battlefield.terrain_segment_impact(previous_position, global_position)
			var building_hit := battlefield.building_segment_impact(previous_position, global_position)
			var nearest := INF
			for impact: Dictionary in [terrain_hit, building_hit]:
				if not impact.is_empty():
					var distance := previous_position.distance_squared_to(impact.position)
					if distance < nearest:
						nearest = distance
						global_position = impact.position
						hit = true
		elif global_position.y <= ground_height + 1.0:
			global_position.y = ground_height + 1.0
			hit = true
		smoke.sample_world_segment(previous_position, global_position)
		wreck.rotate_x(delta * 4.2)
		wreck.rotate_z(delta * 3.4)
		if hit:
			impacted = true
			wreck.visible = false
			_release_smoke()
			if impact_flash_enabled:
				ExplosionEffect.spawn(get_parent() as Node3D, global_position, Color("ff9b48"), 8.0)
			elapsed = 0.0
	else:
		if elapsed >= 1.4:
			queue_free()
	if not impacted and elapsed >= FALL_TIMEOUT:
		_release_smoke()
		queue_free()

func _release_smoke() -> void:
	if smoke_released or not is_instance_valid(smoke):
		return
	smoke_released = true
	smoke.release_to(get_parent())
