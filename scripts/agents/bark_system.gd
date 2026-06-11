extends RefCounted

const BARKS_PATH := "res://data/barks/agent_barks.json"

static var _loaded := false
static var _barks_by_category: Dictionary = {}

var _last_by_category: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	_ensure_loaded()


func get_bark(category: String) -> String:
	_ensure_loaded()

	var lines: Array = _barks_by_category.get(category, [])
	if lines.is_empty():
		return ""

	var index := _rng.randi_range(0, lines.size() - 1)
	if lines.size() > 1:
		var last_line := String(_last_by_category.get(category, ""))
		var attempts := 0
		while String(lines[index]) == last_line and attempts < 8:
			index = _rng.randi_range(0, lines.size() - 1)
			attempts += 1

	var bark := String(lines[index])
	_last_by_category[category] = bark
	return bark


static func _ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_barks_by_category = {}

	if not FileAccess.file_exists(BARKS_PATH):
		push_warning("Agent bark data missing at %s." % BARKS_PATH)
		return

	var text := FileAccess.get_file_as_string(BARKS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Agent bark data is not a JSON object.")
		return

	var parsed_dictionary: Dictionary = parsed
	for category in parsed_dictionary.keys():
		if String(category).begins_with("_"):
			continue

		var raw_lines: Variant = parsed_dictionary[category]
		if typeof(raw_lines) != TYPE_ARRAY:
			continue

		var lines: Array = []
		for raw_line in raw_lines:
			if typeof(raw_line) != TYPE_STRING:
				continue
			var line := String(raw_line).strip_edges()
			if not line.is_empty():
				lines.append(line)

		if not lines.is_empty():
			_barks_by_category[String(category)] = lines
