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

func test_reports_and_old_observations_drive_search_priority() -> void:
	var search := ReconSearch.new()
	search.configure(600.0)
	var clue_position := Vector3(240, 0, 240)
	var clue: Array[Dictionary] = [{"estimated_position": SaveDocument.vector3_to_data(clue_position), "confidence": 0.8, "uncertainty": 100.0, "observed_at": 10.0}]
	var target := search.choose(1, Vector3.ZERO, 20.0, clue)
	assert_eq(search.cell_at(target), search.cell_at(clue_position))
	search.seen[search.cell_at(target)] = 20.0
	search.release(1)
	assert_ne(search.choose(1, Vector3.ZERO, 20.0, clue), target)
	search.release(1)
	for cell: int in search.width() * search.width():
		search.seen[cell] = 200.0
	search.seen[search.cell_at(clue_position)] = 0.0
	assert_eq(search.choose(1, Vector3.ZERO, 300.0, []), target)

func test_search_memory_round_trips_and_rejects_invalid_cells() -> void:
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
	state.seen[0].cell = -1
	assert_ne(restored.validation_error(state, 2.0), "")
