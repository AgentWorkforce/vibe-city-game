# Headless unit-test runner. Usage: godot --headless -s tools/run_tests.gd
# Discovers tests/test_*.gd, instantiates each, and calls every method
# starting with "test_". A test fails by pushing into the `failures` array.
extends SceneTree


func _initialize() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	if dir == null:
		print("no tests/ directory")
		quit(0)
		return
	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var suite = load("res://tests/" + file).new()
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.failures = []
			suite.call(name)
			if suite.failures.is_empty():
				print("PASS  %s :: %s" % [file, name])
			else:
				failed += 1
				for f in suite.failures:
					print("FAIL  %s :: %s — %s" % [file, name, f])
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
