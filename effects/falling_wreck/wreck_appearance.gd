class_name WreckAppearance
extends RefCounted
## Visual snapshot only: no flight state, source scripts, lights or emitters.

static var wreck_materials: Dictionary[Color, StandardMaterial3D] = {}

static func copy_visuals(source: Node, destination: Node3D) -> void:
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
		copy_visuals(child, copy)

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
