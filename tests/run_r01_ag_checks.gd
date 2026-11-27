extends Node
## Standalone runner for Antigravity R01-AG contract tests (C-13 and C-14).

var passed := 0
var failed := 0


func _ready() -> void:
	for suite_path: String in ["res://tests/test_contract_c14.gd", "res://tests/test_contract_c13.gd"]:
		var s: GDScript = load(suite_path)
		var suite: Node = s.new()
		add_child(suite)
		print("\n=== %s ===" % suite_path.get_file())
		await suite.run(self)
		suite.queue_free()
	print("\n[R01-AG tests] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func check(condition: bool, label: String, detail := "") -> bool:
	if condition:
		passed += 1
		print("  PASS  ", label, ("  (" + detail + ")") if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, ("  (" + detail + ")") if detail != "" else "")
	return condition
