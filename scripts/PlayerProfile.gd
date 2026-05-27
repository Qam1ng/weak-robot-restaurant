extends Node

const TRAIT_O := "O"
const TRAIT_C := "C"
const TRAIT_E := "E"
const TRAIT_A := "A"
const TRAIT_N := "N"

const TIPI_ITEM_COUNT := 10

var tipi_responses := {}
var tipi_scores := {
	TRAIT_O: 4.0,
	TRAIT_C: 4.0,
	TRAIT_E: 4.0,
	TRAIT_A: 4.0,
	TRAIT_N: 4.0,
}
var question_count: int = 0

func has_tipi() -> bool:
	return question_count >= TIPI_ITEM_COUNT

func set_tipi(responses: Dictionary = {}, total_questions: int = TIPI_ITEM_COUNT) -> void:
	question_count = total_questions
	tipi_responses.clear()
	for i in range(1, TIPI_ITEM_COUNT + 1):
		var value := clampf(float(responses.get(i, 4.0)), 1.0, 7.0)
		tipi_responses[i] = value
	_recompute_tipi_scores()

func get_profile() -> Dictionary:
	return {
		"tipi_responses": tipi_responses.duplicate(true),
		"tipi_scores": tipi_scores.duplicate(true),
		"question_count": question_count,
	}

func _recompute_tipi_scores() -> void:
	var item_1 := _response(1)
	var item_2 := _response(2)
	var item_3 := _response(3)
	var item_4 := _response(4)
	var item_5 := _response(5)
	var item_6 := _response(6)
	var item_7 := _response(7)
	var item_8 := _response(8)
	var item_9 := _response(9)
	var item_10 := _response(10)

	tipi_scores[TRAIT_E] = (item_1 + _reverse_score(item_6)) * 0.5
	tipi_scores[TRAIT_A] = (_reverse_score(item_2) + item_7) * 0.5
	tipi_scores[TRAIT_C] = (item_3 + _reverse_score(item_8)) * 0.5
	tipi_scores[TRAIT_N] = (item_4 + _reverse_score(item_9)) * 0.5
	tipi_scores[TRAIT_O] = (item_5 + _reverse_score(item_10)) * 0.5

func _response(index: int) -> float:
	return clampf(float(tipi_responses.get(index, 4.0)), 1.0, 7.0)

func _reverse_score(value: float) -> float:
	return 8.0 - clampf(value, 1.0, 7.0)
