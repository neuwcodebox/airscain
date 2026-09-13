class_name SaveStore
extends RefCounted

const DEFAULT_PATH := "user://continuous_operation.json"
const ERROR_MISSING := "저장 파일이 없습니다"

static func write(document: Dictionary, path: String = DEFAULT_PATH) -> String:
	var document_error := SaveDocument.validation_error(document)
	if not document_error.is_empty():
		return document_error
	var recovery_error := _recover_backup(path)
	if not recovery_error.is_empty():
		return recovery_error
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	_remove_if_present(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "저장 파일을 만들 수 없습니다: %s" % error_string(FileAccess.get_open_error())
	var encoded := SaveDocument.encode(document)
	file.store_string(encoded)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_present(temporary_path)
		return "저장 파일을 기록하지 못했습니다: %s" % error_string(write_error)
	var verification := _read_path(temporary_path)
	if not verification.error.is_empty() or FileAccess.get_file_as_string(temporary_path) != encoded:
		_remove_if_present(temporary_path)
		return "임시 저장 파일을 검증하지 못했습니다%s" % (": %s" % verification.error if not verification.error.is_empty() else "")
	var had_previous := FileAccess.file_exists(path)
	if had_previous:
		_remove_if_present(backup_path)
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			_remove_if_present(temporary_path)
			return "기존 저장 파일을 보존하지 못했습니다: %s" % error_string(backup_error)
	var promote_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(path))
	if promote_error != OK:
		if had_previous:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
		_remove_if_present(temporary_path)
		return "저장 파일을 확정하지 못했습니다: %s" % error_string(promote_error)
	return ""

static func read(path: String = DEFAULT_PATH) -> Dictionary:
	var recovery_error := _recover_backup(path)
	if not recovery_error.is_empty():
		return {"error": recovery_error, "document": {}}
	return _read_path(path)

static func read_backup(path: String = DEFAULT_PATH) -> Dictionary:
	return _read_path(path + ".bak")

static func combined_read_error(primary_error: String, backup_error: String) -> String:
	if backup_error == ERROR_MISSING:
		return primary_error
	return "%s · 백업도 복원할 수 없습니다: %s" % [primary_error, backup_error]

static func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": ERROR_MISSING, "document": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "저장 파일을 열 수 없습니다: %s" % error_string(FileAccess.get_open_error()), "document": {}}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"error": "저장 파일을 읽지 못했습니다: %s" % error_string(read_error), "document": {}}
	var document := SaveDocument.decode(text)
	if document.is_empty():
		return {"error": "저장 파일의 JSON이 손상되었습니다", "document": {}}
	var document_error := SaveDocument.validation_error(document)
	if not document_error.is_empty():
		return {"error": document_error, "document": {}}
	return {"error": "", "document": document}

static func _recover_backup(path: String) -> String:
	var backup_path := path + ".bak"
	if FileAccess.file_exists(path):
		return ""
	if not FileAccess.file_exists(backup_path):
		return ""
	var recovery_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
	if recovery_error != OK:
		return "이전 저장 파일을 복구하지 못했습니다: %s" % error_string(recovery_error)
	return ""

static func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
