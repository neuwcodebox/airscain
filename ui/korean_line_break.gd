class_name KoreanLineBreak
extends RefCounted
## Godot may wrap Hangul between any two syllables; Korean text should break only between words.

const WORD_JOINER := "\u2060"

## Joins characters inside words that contain Hangul so autowrap breaks only at spaces or newlines.
static func keep_words(text: String) -> String:
	var result := ""
	for index: int in text.length():
		var character := text[index]
		result += character
		if index + 1 < text.length() and _joins(character, text[index + 1]):
			result += WORD_JOINER
	return result

static func _joins(character: String, next: String) -> bool:
	return not _is_break(character) and not _is_break(next) and (_is_hangul(character) or _is_hangul(next))

static func _is_break(character: String) -> bool:
	return character == " " or character == "\n"

static func _is_hangul(character: String) -> bool:
	var code := character.unicode_at(0)
	return code >= 0xAC00 and code <= 0xD7A3
