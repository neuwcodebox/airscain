class_name CityObjective
extends ProtectedObjective

func setup(id_value: int, definition_value: ObjectiveDefinition) -> void:
	super.setup(id_value, definition_value)
	var marker: MeshInstance3D = $CoreMarker
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("57c7ff")
	material.emission_enabled = true
	material.emission = Color("176a94")
	marker.material_override = material

