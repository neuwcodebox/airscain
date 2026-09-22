class_name GameLocale
extends RefCounted
## Single source of truth for supported UI locales and locale selection policy.

const ENGLISH := "en"
const KOREAN := "ko"
const DEFAULT_LANGUAGE := ENGLISH
const SUPPORTED_LANGUAGES: Array[String] = [ENGLISH, KOREAN]
const OPTIONS: Array[Dictionary] = [
	{"code": ENGLISH, "native_name": "English"},
	{"code": KOREAN, "native_name": "한국어"},
]

static func is_supported(language: String) -> bool:
	return SUPPORTED_LANGUAGES.has(language)

static func preferred_language(system_language: String) -> String:
	return KOREAN if system_language.to_lower().begins_with(KOREAN) else DEFAULT_LANGUAGE

static func option_index(language: String) -> int:
	for index: int in OPTIONS.size():
		if String(OPTIONS[index].code) == language:
			return index
	return 0

static func language_at(index: int) -> String:
	if index < 0 or index >= OPTIONS.size():
		return DEFAULT_LANGUAGE
	return String(OPTIONS[index].code)

static func apply(language: String) -> String:
	var resolved := language if is_supported(language) else DEFAULT_LANGUAGE
	TranslationServer.set_locale(resolved)
	return resolved
