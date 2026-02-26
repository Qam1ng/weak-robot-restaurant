extends Node

var mbti_type: String = ""
var mbti_scores := {
	"E": 0,
	"I": 0,
	"S": 0,
	"N": 0,
	"T": 0,
	"F": 0,
	"J": 0,
	"P": 0
}
var question_count: int = 0

func has_mbti() -> bool:
	return mbti_type.length() == 4

func set_mbti(result_type: String, scores: Dictionary = {}, total_questions: int = 0) -> void:
	mbti_type = result_type
	question_count = total_questions
	for k in mbti_scores.keys():
		mbti_scores[k] = int(scores.get(k, mbti_scores[k]))
	print("[PlayerProfile] MBTI set to ", mbti_type)

func get_profile() -> Dictionary:
	return {
		"mbti_type": mbti_type,
		"scores": mbti_scores.duplicate(true),
		"question_count": question_count,
		"strategy_affinity": _strategy_affinity()
	}

func _strategy_affinity() -> Dictionary:
	var affinity := {
		"reciprocity": 0.0,
		"authority": 0.0,
		"liking": 0.0,
		"commitment": 0.0,
		"social_proof": 0.0,
		"scarcity": 0.0
	}

	if not has_mbti():
		return affinity

	# E/I
	if mbti_type[0] == "E":
		affinity["social_proof"] += 0.35
		affinity["liking"] += 0.25
		affinity["reciprocity"] += 0.15
	else:
		affinity["authority"] += 0.25
		affinity["commitment"] += 0.2

	# S/N
	if mbti_type[1] == "S":
		affinity["authority"] += 0.25
		affinity["scarcity"] += 0.2
	else:
		affinity["social_proof"] += 0.25
		affinity["liking"] += 0.15

	# T/F
	if mbti_type[2] == "T":
		affinity["authority"] += 0.35
		affinity["scarcity"] += 0.25
	else:
		affinity["liking"] += 0.35
		affinity["reciprocity"] += 0.25

	# J/P
	if mbti_type[3] == "J":
		affinity["commitment"] += 0.35
		affinity["authority"] += 0.2
	else:
		affinity["reciprocity"] += 0.2
		affinity["liking"] += 0.15

	return affinity
