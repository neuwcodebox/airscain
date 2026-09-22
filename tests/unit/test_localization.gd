extends GutTest

const HUD_SCENE := preload("res://ui/hud.tscn")
const SCENARIO := preload("res://main/first_scenario.tres")
const SEARCH_RADAR := preload("res://sensing/search_radar/search_radar.tres")
const RANDOM_PREVIEW := preload("res://world/layout_previews/random.svg")

var previous_locale: String

func before_each() -> void:
	previous_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(previous_locale)

func test_english_catalog_translates_static_and_formatted_messages() -> void:
	TranslationServer.set_locale("en")
	assert_eq(tr("새 게임"), "New Operation")
	assert_eq(tr("위협 단계  %d") % 3, "THREAT  3")
	assert_eq(tr("상태 성능저하 · 내구도 %d%%") % 52, "Status Degraded · Integrity 52%")
	assert_eq(tr("도시 기능을 %d 복구했습니다") % 10, "Restored 10 city function")
	assert_eq(tr("고도 프로파일"), "ALTITUDE")
	assert_eq(tr("항적"), "TRACK")
	assert_eq(tr("요격체"), "INTERCEPTOR")

func test_korean_uses_korean_source_messages() -> void:
	TranslationServer.set_locale("ko")
	assert_eq(tr("새 게임"), "새 게임")
	assert_eq(tr("위협 단계  %d") % 3, "위협 단계  3")

func test_scene_controls_follow_runtime_locale_changes() -> void:
	TranslationServer.set_locale("ko")
	var hud := add_child_autofree(HUD_SCENE.instantiate()) as Hud
	var defense_button := hud.get_node("%DefenseMenuButton") as Button
	var game_over_caption := hud.get_node("GameOverPanel/VBox/Caption") as Label
	assert_ne(defense_button.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_ne(game_over_caption.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED)
	TranslationServer.set_locale("en")
	assert_eq(tr(defense_button.text), "DEFENSE  ▼")
	assert_eq(tr(game_over_caption.text), "OPERATION ENDED")

func test_content_and_battlefield_cards_translate_at_presentation_boundary() -> void:
	TranslationServer.set_locale("en")
	assert_eq(tr(SEARCH_RADAR.display_name), "Low/Medium-Altitude Radar")
	assert_string_contains(tr(SEARCH_RADAR.purchase_tooltip), "Shares tracks")
	var layout: BattlefieldLayoutDefinition = SCENARIO.battlefield_layouts[0]
	var card := BattlefieldChoiceCard.for_layout(layout)
	assert_eq(card.title, "Mountain Harbor")
	assert_eq(card.facts[0][0], "City Districts")
	var random_card := BattlefieldChoiceCard.random_choice(RANDOM_PREVIEW, SCENARIO.battlefield_layouts.size())
	assert_eq(random_card.title, "Random")
	assert_string_contains(random_card.summary, "4 battlefields")
	card.free()
	random_card.free()

func test_status_codes_are_locale_independent_while_text_is_translated() -> void:
	TranslationServer.set_locale("en")
	assert_eq(SupportManager.supply_status_text(&"resupply_active"), "Resupplying")
	assert_true(UnitStatusMarker.SUPPLY_TEXTURES.has(&"resupply_active"))
	assert_false(UnitStatusMarker.SUPPLY_TEXTURES.has(&"재보급 중"))
	assert_eq(PersistenceFeedback.failure_message(PersistenceFeedback.Action.LOAD, SaveStore.ERROR_MISSING), "No saved operation was found.")
