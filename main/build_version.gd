class_name BuildVersion
extends RefCounted

const GENERATED_PATH := "res://build_info/build_version.txt"
const DEVELOPMENT_LABEL := "dev"

static func display_text() -> String:
	if not FileAccess.file_exists(GENERATED_PATH):
		return DEVELOPMENT_LABEL
	var value := FileAccess.get_file_as_string(GENERATED_PATH).strip_edges()
	return value if not value.is_empty() else DEVELOPMENT_LABEL

static func from_build(build_date: String, short_sha: String, dirty: bool = false) -> String:
	var date := build_date.strip_edges().replace("-", ".")
	var revision := short_sha.strip_edges()
	if date.is_empty() or revision.is_empty():
		return DEVELOPMENT_LABEL
	return "%s · %s%s" % [date, revision, "-dirty" if dirty else ""]
