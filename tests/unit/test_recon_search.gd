extends GutTest

func test_search_divides_unknown_space_and_releases_lost_aircraft() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	var first := search.choose(1, Vector3.ZERO, 0.0, [])
	var second := search.choose(2, Vector3.ZERO, 0.0, [])
	assert_ne(first, second)
	assert_eq(search.choose(1, Vector3(100, 0, 0), 1.0, []), first)
	search.release(1)
	assert_eq(search.choose(3, Vector3.ZERO, 0.0, []), first)

func test_uncertain_report_is_revisited_after_a_pass() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	var clue_position := Vector3(240, 0, 240)
	var clue := _clue(clue_position, 0.8, 100.0, 10.0)
	var target := search.choose(1, Vector3.ZERO, 20.0, clue)
	assert_eq(search.cell_at(target), search.cell_at(clue_position))
	search.seen[search.cell_at(target)] = 20.0
	search.release(1)
	assert_eq(search.choose(1, Vector3.ZERO, 20.0, clue), target, "불확실한 단서는 통과 관측 이후에도 재확인합니다")

func test_recent_precise_report_is_not_revisited_immediately() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	var clue_position := Vector3(240, 0, 240)
	var clue := _clue(clue_position, 0.92, 24.0, 10.0)
	var target := search.choose(1, Vector3.ZERO, 20.0, clue)
	assert_eq(search.cell_at(target), search.cell_at(clue_position), "정밀 보고도 최초 수색 대상으로 선택합니다")
	search.seen[search.cell_at(target)] = 20.0
	search.release(1)
	assert_ne(search.choose(1, Vector3.ZERO, 20.0, clue), target)

func test_oldest_unassigned_cell_receives_search_priority() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	var oldest_position := Vector3(240, 0, 240)
	for cell: int in search.width() * search.width():
		search.seen[cell] = 200.0
	search.seen[search.cell_at(oldest_position)] = 0.0
	assert_eq(search.cell_at(search.choose(1, Vector3.ZERO, 300.0, [])), search.cell_at(oldest_position))

func test_search_memory_round_trips() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	search.choose(1, Vector3.ZERO, 1.0, [])
	search.seen[0] = 1.0
	var state := search.capture_state()
	var restored := ReconSearch.new()
	restored.configure(600.0)
	restored.restore_state(state)
	assert_eq(restored.capture_state(), state)
	assert_eq(restored.validation_error(state, 2.0), "")

func test_search_memory_rejects_invalid_cells() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	search.seen[0] = 1.0
	var state := search.capture_state()
	state.seen[0].cell = -1
	assert_ne(search.validation_error(state, 2.0), "", "전장 밖의 탐색 셀은 복원 전에 거절합니다")

func test_search_uses_public_land_mask_instead_of_searching_empty_sea() -> void:
	var search := ReconSearch.new()
	search.configure(600.0, [12, 13])
	assert_eq(search.cell_at(search.choose(1, Vector3(-300, 0, -300), 0.0, [])), 12)
	assert_eq(search.cell_at(search.choose(2, Vector3(-300, 0, -300), 0.0, [])), 13)

func _clue(position: Vector3, confidence: float, uncertainty: float, observed_at: float) -> Array[Dictionary]:
	return [{
		"estimated_position": SaveDocument.vector3_to_data(position),
		"confidence": confidence,
		"uncertainty": uncertainty,
		"observed_at": observed_at,
	}]
