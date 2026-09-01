class_name SaveDocument
extends RefCounted

const FORMAT_ID := "airscain-save"
const CURRENT_VERSION := 8
const REQUIRED_SECTIONS: Array[String] = ["scenario", "session", "world", "player_knowledge", "director"]

static func create(payload: Dictionary) -> Dictionary:
	return {
		"format": FORMAT_ID,
		"version": CURRENT_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"payload": payload.duplicate(true),
	}

static func validation_error(document: Dictionary) -> String:
	if document.get("format", "") != FORMAT_ID:
		return "지원하지 않는 저장 형식입니다"
	var version: int = int(document.get("version", -1))
	if version != CURRENT_VERSION:
		return "지원하지 않는 저장 버전입니다: %d" % version
	var payload: Variant = document.get("payload")
	if not payload is Dictionary:
		return "저장 payload가 올바르지 않습니다"
	for section: String in REQUIRED_SECTIONS:
		if not payload.has(section) or not payload[section] is Dictionary:
			return "저장 섹션이 없거나 올바르지 않습니다: %s" % section
	return ""

static func encode(document: Dictionary) -> String:
	return JSON.stringify(document)

static func decode(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed as Dictionary if parsed is Dictionary else {}

static func vector3_to_data(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func vector3_from_data(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
