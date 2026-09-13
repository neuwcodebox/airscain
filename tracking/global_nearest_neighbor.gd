class_name GlobalNearestNeighbor
extends RefCounted

const BLOCKED_COST := 1.0e12

## Returns the selected column for every row in a rectangular cost matrix.
## The caller must provide at least as many columns as rows.
static func solve(costs: Array[PackedFloat64Array]) -> PackedInt32Array:
	var row_count := costs.size()
	if row_count == 0:
		return PackedInt32Array()
	var column_count := costs[0].size()
	assert(column_count >= row_count)
	for row: PackedFloat64Array in costs:
		assert(row.size() == column_count)

	# Hungarian assignment with rows as the smaller partition.
	var row_potential := PackedFloat64Array()
	row_potential.resize(row_count + 1)
	var column_potential := PackedFloat64Array()
	column_potential.resize(column_count + 1)
	var matched_row := PackedInt32Array()
	matched_row.resize(column_count + 1)
	var previous_column := PackedInt32Array()
	previous_column.resize(column_count + 1)

	for row_index: int in range(1, row_count + 1):
		matched_row[0] = row_index
		var current_column := 0
		var minimum_reduced_cost := PackedFloat64Array()
		minimum_reduced_cost.resize(column_count + 1)
		minimum_reduced_cost.fill(BLOCKED_COST)
		var visited := PackedByteArray()
		visited.resize(column_count + 1)
		while true:
			visited[current_column] = 1
			var current_row := matched_row[current_column]
			var step_cost := BLOCKED_COST
			var next_column := 0
			for column_index: int in range(1, column_count + 1):
				if visited[column_index] != 0:
					continue
				var reduced_cost := costs[current_row - 1][column_index - 1] - row_potential[current_row] - column_potential[column_index]
				if reduced_cost < minimum_reduced_cost[column_index]:
					minimum_reduced_cost[column_index] = reduced_cost
					previous_column[column_index] = current_column
				if minimum_reduced_cost[column_index] < step_cost:
					step_cost = minimum_reduced_cost[column_index]
					next_column = column_index
			for column_index: int in range(column_count + 1):
				if visited[column_index] != 0:
					row_potential[matched_row[column_index]] += step_cost
					column_potential[column_index] -= step_cost
				else:
					minimum_reduced_cost[column_index] -= step_cost
			current_column = next_column
			if matched_row[current_column] == 0:
				break
		while true:
			var next_column := previous_column[current_column]
			matched_row[current_column] = matched_row[next_column]
			current_column = next_column
			if current_column == 0:
				break

	var columns_by_row := PackedInt32Array()
	columns_by_row.resize(row_count)
	columns_by_row.fill(-1)
	for column_index: int in range(1, column_count + 1):
		if matched_row[column_index] > 0:
			columns_by_row[matched_row[column_index] - 1] = column_index - 1
	return columns_by_row
