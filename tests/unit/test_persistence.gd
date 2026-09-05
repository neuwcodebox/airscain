extends GutTest

const SAVE_STORE := preload("res://persistence/save_store.gd")

var save_path: String

func before_each() -> void:
	save_path = "user://save_store_test_%d.json" % get_instance_id()
	_cleanup_save_files()

func after_each() -> void:
	_cleanup_save_files()

func test_versioned_save_document_round_trips_plain_data() -> void:
	assert_eq(SaveDocument.MIN_SUPPORTED_VERSION, 16)
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

func test_version_16_migration_disables_automatic_spending_without_mutating_source() -> void:
	var document := SaveDocument.create(_valid_payload())
	document.version = 16
	document.payload.world.support = {"tasks": []}
	var migrated := SaveDocument.decode(SaveDocument.encode(document))
	assert_eq(int(migrated.version), 17)
	assert_eq(migrated.payload.world.support.automatic_resupply_ids, [])
	assert_eq(document.version, 16)
	assert_false(document.payload.world.support.has("automatic_resupply_ids"))
	document.version = 15
	assert_ne(SaveDocument.validation_error(SaveDocument.migrate(document)), "")

func test_save_store_round_trips_and_preserves_previous_file_on_invalid_write() -> void:
	var document := SaveDocument.create(_valid_payload())
	document.payload.scenario.world_seed = 48127
	assert_eq(SAVE_STORE.write(document, save_path), "")
	var loaded: Dictionary = SAVE_STORE.read(save_path)
	assert_eq(loaded.error, "")
	assert_eq(int(loaded.document.payload.scenario.world_seed), 48127)
	var invalid_document := document.duplicate(true)
	invalid_document.version = SaveDocument.CURRENT_VERSION + 1
	assert_ne(SAVE_STORE.write(invalid_document, save_path), "")
	loaded = SAVE_STORE.read(save_path)
	assert_eq(loaded.error, "")
	assert_eq(int(loaded.document.payload.scenario.world_seed), 48127)
	assert_eq(DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak")), OK)
	loaded = SAVE_STORE.read(save_path)
	assert_eq(loaded.error, "")
	assert_eq(int(loaded.document.payload.scenario.world_seed), 48127)
	assert_true(FileAccess.file_exists(save_path))
	assert_false(FileAccess.file_exists(save_path + ".bak"))

func test_save_store_reports_missing_file_without_document() -> void:
	var loaded: Dictionary = SAVE_STORE.read(save_path)
	assert_ne(loaded.error, "")
	assert_eq(loaded.document, {})

func _valid_payload() -> Dictionary:
	return {
		"scenario": {},
		"session": {},
		"world": {},
		"player_knowledge": {},
		"director": {},
	}

func _cleanup_save_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
