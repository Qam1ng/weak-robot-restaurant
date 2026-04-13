extends Node

const TRAIT_O := "O"
const TRAIT_C := "C"
const TRAIT_E := "E"
const TRAIT_A := "A"
const TRAIT_N := "N"

const TIPI_ITEM_COUNT := 10
const STRATEGY_AFFINITY_WEIGHTS := {
	"reciprocity": {
		TRAIT_A: 0.7,
	},
	"authority": {
		TRAIT_C: 0.6,
	},
	"liking": {
		TRAIT_A: 0.45,
		TRAIT_E: 0.35,
	},
	"commitment": {
		TRAIT_C: 0.75,
	},
	"social_proof": {
		TRAIT_E: 0.6,
		TRAIT_O: 0.2,
	},
	"scarcity": {
		TRAIT_N: 0.7,
	},
}

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
		"tipi_scores": tipi_scores.duplicate(true),
		"question_count": question_count,
		"strategy_affinity": _strategy_affinity(),
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

func _normalized_trait_score(trait_key: String) -> float:
	var raw := float(tipi_scores.get(trait_key, 4.0))
	return clampf((raw - 4.0) / 3.0, -1.0, 1.0)

func _strategy_affinity() -> Dictionary:
	var affinity := {
		"reciprocity": 0.0,
		"authority": 0.0,
		"liking": 0.0,
		"commitment": 0.0,
		"social_proof": 0.0,
		"scarcity": 0.0,
	}

	if not has_tipi():
		return affinity

	for strategy in STRATEGY_AFFINITY_WEIGHTS.keys():
		var weights: Dictionary = STRATEGY_AFFINITY_WEIGHTS[strategy]
		var score := 0.0
		for trait_key in weights.keys():
			score += float(weights[trait_key]) * _normalized_trait_score(str(trait_key))
		affinity[strategy] = score

	return affinity
