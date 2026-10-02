class_name SaveStore
extends RefCounted

const PATH := "user://progress.json"
const MAX_LEVEL := 10
var coins := 0
var level := 0
var best_score := 0
var clears := 0
var muted := false
var last_error := OK
var storage_path := PATH

func load_progress(path: String = "") -> void:
	if path.is_empty():
		path = storage_path
	if not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var data = parser.data
	if not data is Dictionary:
		return
	coins = _safe_int(data.get("coins", 0), 0, 10000000)
	level = _safe_int(data.get("level", 0), 0, MAX_LEVEL)
	best_score = _safe_int(data.get("best_score", 0), 0, 100000000)
	clears = _safe_int(data.get("clears", 0), 0, 1000000)
	muted = data.get("muted", false) == true

func _safe_int(value: Variant, low: int, high: int) -> int:
	return clampi(int(value), low, high) if value is float or value is int else low

func save_progress(path: String = "") -> Error:
	if path.is_empty():
		path = storage_path
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify({"version": 1, "coins": coins, "level": level, "best_score": best_score, "clears": clears, "muted": muted}))
	file.close()
	last_error = OK
	return OK

func upgrade_cost() -> int:
	return 60 + level * 35

func upgrade() -> bool:
	if level >= MAX_LEVEL or coins < upgrade_cost():
		return false
	coins -= upgrade_cost()
	level += 1
	save_progress()
	return true

func record(won: bool, reward: int, score: int) -> void:
	coins += maxi(0, reward)
	best_score = maxi(best_score, score)
	if won:
		clears += 1
	save_progress()
