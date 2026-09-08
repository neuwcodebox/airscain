class_name ReconSearch
extends RefCounted
## Geographic search memory. Inputs are map bounds and reports, never live assets.

const CELL_SIZE := 120.0
const REVISIT_SECONDS := 120.0
var extent: float = 1200.0
var searchable: Dictionary[int, bool] = {}
var seen: Dictionary[int, float] = {}
var assignments: Dictionary[int, int] = {}
var attempted: Dictionary[int, float] = {}

func configure(size: float, land_cells: Array[int] = []) -> void:
	extent = size * 0.5
	searchable.clear()
	for cell: int in land_cells:
		searchable[cell] = true

func width() -> int:
	return maxi(1, ceili(extent * 2.0 / CELL_SIZE))

func center(cell: int) -> Vector3:
	var count := width()
	return Vector3(-extent + (cell % count + 0.5) * CELL_SIZE, 0.0, -extent + (cell / count + 0.5) * CELL_SIZE)

func cell_at(position: Vector3) -> int:
	var x := clampi(floori((position.x + extent) / CELL_SIZE), 0, width() - 1)
	var z := clampi(floori((position.z + extent) / CELL_SIZE), 0, width() - 1)
	return z * width() + x

func choose(owner: int, position: Vector3, now: float, clues: Array[Dictionary]) -> Vector3:
	if assignments.has(owner):
		return center(assignments[owner])
	var reserved := assignments.values()
	var best := -1
	var best_score := -INF
	for cell: int in width() * width():
		if reserved.has(cell) or (not searchable.is_empty() and not searchable.has(cell)):
			continue
		var point := center(cell)
		var age := maxf(0.0, now - seen[cell]) if seen.has(cell) else REVISIT_SECONDS
		var information := 1.0 + minf(3.0, age / REVISIT_SECONDS)
		for clue: Dictionary in clues:
			var report_position := SaveDocument.vector3_from_data(clue.estimated_position)
			if cell_at(report_position) != cell:
				continue
			# A freshly searched cell should not repeatedly win on the same report.
			if seen.get(cell, -1.0) >= float(clue.observed_at) and float(clue.confidence) >= 0.85 and float(clue.uncertainty) <= 30.0:
				continue
			information += 3.0 * float(clue.confidence) + minf(1.0, float(clue.uncertainty) / CELL_SIZE)
		if now - attempted.get(cell, -REVISIT_SECONDS) < 30.0:
			information *= 0.1
		var distance := Vector2(point.x - position.x, point.z - position.z).length()
		var score := information / (1.0 + distance / 600.0)
		if score > best_score:
			best_score = score
			best = cell
	if best < 0:
		return position # Every sector is already assigned; do not steal work.
	assignments[owner] = best
	return center(best)

func release(owner: int) -> void:
	assignments.erase(owner)

func reset() -> void:
	seen.clear()
	assignments.clear()
	attempted.clear()

func capture_state() -> Dictionary:
	var observations: Array[Dictionary] = []
	for cell: int in seen:
		observations.append({"cell": cell, "time": seen[cell]})
	var reservations: Array[Dictionary] = []
	for owner: int in assignments:
		reservations.append({"owner": owner, "cell": assignments[owner]})
	var attempts: Array[Dictionary] = []
	for cell: int in attempted:
		attempts.append({"cell": cell, "time": attempted[cell]})
	return {"seen": observations, "assignments": reservations, "attempted": attempts}

func restore_state(state: Dictionary) -> void:
	reset()
	for item: Dictionary in state.get("seen", []):
		seen[int(item.cell)] = float(item.time)
	for item: Dictionary in state.get("attempted", []):
		attempted[int(item.cell)] = float(item.time)
	for item: Dictionary in state.get("assignments", []):
		assignments[int(item.owner)] = int(item.cell)

func validation_error(state: Dictionary, now: float) -> String:
	var owners: Dictionary[int, bool] = {}
	for key: String in ["seen", "assignments", "attempted"]:
		if not state.get(key, []) is Array:
			return "정찰 구역 목록이 올바르지 않습니다"
		var unique: Dictionary[int, bool] = {}
		for value: Variant in state.get(key, []):
			if not value is Dictionary:
				return "정찰 구역 상태가 올바르지 않습니다"
			var cell := int(value.get("cell", -1))
			if cell < 0 or cell >= width() * width() or unique.has(cell):
				return "정찰 구역 번호가 올바르지 않습니다"
			unique[cell] = true
			if key != "assignments" and (not is_finite(float(value.get("time", NAN))) or float(value.time) < 0.0 or float(value.time) > now):
				return "정찰 관측 시간이 올바르지 않습니다"
			if key == "assignments" and (int(value.get("owner", 0)) <= 0 or owners.has(int(value.get("owner", 0)))):
				return "정찰 구역 소유자가 올바르지 않습니다"
			if key == "assignments":
				owners[int(value.owner)] = true
	return ""
