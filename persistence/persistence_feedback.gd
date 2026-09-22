class_name PersistenceFeedback
extends RefCounted

enum Action { SAVE, LOAD }

const BACKUP_RECOVERY := "기본 저장 대신 마지막 정상 백업을 사용했습니다"
const FILE_WRITE_FAILURE_PREFIXES: Array[String] = [
	"저장 파일을 만들 수 없습니다",
	"저장 파일을 기록하지 못했습니다",
	"임시 저장 파일을 검증하지 못했습니다",
	"기존 저장 파일을 보존하지 못했습니다",
	"저장 파일을 확정하지 못했습니다",
	"이전 저장 파일을 복구하지 못했습니다",
]
const DAMAGED_SAVE_MARKERS: Array[String] = [
	"JSON이 손상되었습니다",
	"payload",
	"저장 섹션",
	"올바르지 않습니다",
	"찾을 수 없습니다",
]

static func success_message(action: Action, repairs: Array[String]) -> String:
	var display_action := action_name(action)
	var used_backup := repairs.has(BACKUP_RECOVERY)
	var repaired_state_count := repairs.size() - (1 if used_backup else 0)
	if used_backup and repaired_state_count > 0:
		return TranslationServer.translate("%s 완료 · 이전 정상 저장을 복구하고 상태 %d건을 정리했습니다") % [display_action, repaired_state_count]
	if used_backup:
		return TranslationServer.translate("%s 완료 · 이전 정상 저장을 복구했습니다") % display_action
	if repaired_state_count > 0:
		return TranslationServer.translate("%s 완료 · 문제가 있던 상태 %d건을 자동으로 정리했습니다") % [display_action, repaired_state_count]
	return TranslationServer.translate("%s 완료") % display_action

static func failure_message(action: Action, diagnostic: String, current_operation_preserved: bool = false) -> String:
	if diagnostic == SaveStore.ERROR_MISSING:
		return TranslationServer.translate("저장된 작전을 찾을 수 없습니다.")
	if diagnostic.begins_with("지원하지 않는 저장"):
		return TranslationServer.translate("이 저장 파일은 현재 게임 버전과 호환되지 않습니다. 게임 버전을 확인해 주세요.")
	if action == Action.SAVE:
		if _is_file_write_failure(diagnostic):
			return TranslationServer.translate("저장 파일을 쓸 수 없습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요.")
		return TranslationServer.translate("현재 작전을 안전하게 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.")
	var message := TranslationServer.translate("저장 파일이 손상되어 작전을 불러오지 못했습니다.") if _is_damaged_save(diagnostic) else TranslationServer.translate("저장된 작전을 불러오지 못했습니다.")
	if diagnostic.contains("백업도 복원할 수 없습니다"):
		message = TranslationServer.translate("기본 저장과 이전 정상 저장을 모두 불러오지 못했습니다.")
	return TranslationServer.translate("%s 현재 작전은 그대로 유지됩니다.") % message if current_operation_preserved else TranslationServer.translate("%s 새 작전을 시작하거나 다른 저장 파일을 사용해 주세요.") % message

static func action_name(action: Action) -> String:
	return TranslationServer.translate("저장") if action == Action.SAVE else TranslationServer.translate("불러오기")

static func _is_file_write_failure(diagnostic: String) -> bool:
	for prefix: String in FILE_WRITE_FAILURE_PREFIXES:
		if diagnostic.begins_with(prefix):
			return true
	return false

static func _is_damaged_save(diagnostic: String) -> bool:
	for marker: String in DAMAGED_SAVE_MARKERS:
		if diagnostic.contains(marker):
			return true
	return false
