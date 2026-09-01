extends GutTest

func test_versioned_save_document_round_trips_plain_data() -> void:
	var payload := _valid_payload()
	payload.scenario.world_seed = 73129
	payload.world.defenses = [{"definition_id": "missile_battery", "position": [1.0, 2.0, 3.0]}]
	var document := SaveDocument.create(payload)
	assert_eq(document.format, SaveDocument.FORMAT_ID)
	assert_eq(document.version, SaveDocument.CURRENT_VERSION)
	assert_eq(SaveDocument.validation_error(document), "")
	var decoded := SaveDocument.decode(SaveDocument.encode(document))
	assert_eq(SaveDocument.validation_error(decoded), "")
	assert_eq(int(decoded.payload.scenario.world_seed), 73129)
	assert_eq(decoded.payload.world.defenses[0].definition_id, "missile_battery")

func test_save_validation_rejects_unknown_version_and_missing_sections() -> void:
	var unknown_version := SaveDocument.create(_valid_payload())
	unknown_version.version = SaveDocument.CURRENT_VERSION + 1
	assert_ne(SaveDocument.validation_error(unknown_version), "")
	var missing_section := SaveDocument.create(_valid_payload())
	missing_section.payload.erase("player_knowledge")
	assert_ne(SaveDocument.validation_error(missing_section), "")
	assert_eq(SaveDocument.decode("not json"), {})

func test_vector_conversion_uses_json_safe_arrays() -> void:
	var source := Vector3(12.5, -3.0, 99.25)
	var data := SaveDocument.vector3_to_data(source)
	assert_eq(data, [12.5, -3.0, 99.25])
	assert_eq(SaveDocument.vector3_from_data(data), source)
	assert_eq(SaveDocument.vector3_from_data([1.0]), Vector3.ZERO)

func _valid_payload() -> Dictionary:
	return {
		"scenario": {},
		"session": {},
		"world": {},
		"player_knowledge": {},
		"director": {},
	}
