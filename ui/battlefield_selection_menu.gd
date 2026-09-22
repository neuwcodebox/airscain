class_name BattlefieldSelectionMenu
extends Control
## Owns the battlefield card collection, focus restoration and selection-screen transitions.

signal layout_selected(layout_id: StringName)
signal closed

const CARD_REVEAL_STAGGER := 0.04
const CARD_REVEAL_SECONDS := 0.24

@onready var choice_list: HBoxContainer = %BattlefieldChoiceList
@onready var mode_label: Label = %BattlefieldModeLabel

var _last_layout_id: StringName = &""
var _cards_by_layout_id: Dictionary[StringName, BattlefieldChoiceCard] = {}
var _layouts: Array[BattlefieldLayoutDefinition] = []
var _random_preview: Texture2D

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _layouts.is_empty():
		_rebuild_cards()

func configure(layouts: Array[BattlefieldLayoutDefinition], random_preview: Texture2D) -> void:
	_layouts = layouts
	_random_preview = random_preview
	_rebuild_cards()

func _rebuild_cards() -> void:
	for child: Node in choice_list.get_children():
		child.free()
	_cards_by_layout_id.clear()
	var cards: Array[BattlefieldChoiceCard] = [BattlefieldChoiceCard.random_choice(_random_preview, _layouts.size())]
	for layout: BattlefieldLayoutDefinition in _layouts:
		cards.append(BattlefieldChoiceCard.for_layout(layout))
	for card: BattlefieldChoiceCard in cards:
		card.pressed.connect(_select_layout.bind(card.layout_id))
		choice_list.add_child(card)
		_cards_by_layout_id[card.layout_id] = card
	if visible:
		card_for_layout(_last_layout_id).grab_focus.call_deferred()

func present(mode_name: String) -> void:
	mode_label.text = mode_name
	visible = true
	_animate_cards()
	card_for_layout(_last_layout_id).grab_focus()

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func card_for_layout(layout_id: StringName) -> BattlefieldChoiceCard:
	return _cards_by_layout_id.get(layout_id, _cards_by_layout_id[&""])

func choice_count() -> int:
	return _cards_by_layout_id.size()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _select_layout(layout_id: StringName) -> void:
	_last_layout_id = layout_id
	visible = false
	layout_selected.emit(layout_id)

func _animate_cards() -> void:
	var cards := choice_list.get_children()
	for index: int in cards.size():
		var card := cards[index] as Control
		card.modulate.a = 0.0
		var tween := card.create_tween()
		tween.tween_interval(CARD_REVEAL_STAGGER * index)
		tween.tween_property(card, "modulate:a", 1.0, CARD_REVEAL_SECONDS)
