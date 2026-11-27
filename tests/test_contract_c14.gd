extends Node
## Contract C-14 conformance tests for Atmosphere (profiles, signals, wind vector, unknown id).


func run(t) -> void:
	var atm := Atmosphere.new()
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(atm)
	add_child(sun)
	atm.bind_environment(env, sun, preload("res://assets/materials/sky.tres"))

	var emitted := []
	atm.profile_applied.connect(func(id: String) -> void: emitted.append(id))

	for pid: String in ["golden_day", "atmospheric_evening", "moonlit_night", "misty_valley"]:
		var res := atm.apply(pid, 0.0)
		t.check(bool(res.get("ok", false)), "C-14 apply('%s') succeeds" % pid, str(res.get("reason", "")))
		t.check(atm.current() == pid, "C-14 current() == '%s'" % pid, atm.current())

	t.check(emitted.size() == 4, "C-14 profile_applied emitted for each applied profile", str(emitted.size()))

	var bad := atm.apply("nonexistent_profile_xyz", 0.0)
	t.check(not bool(bad.get("ok", true)) and String(bad.get("reason", "")) == "unknown_profile",
		"C-14 unknown profile fails cleanly without crash", str(bad))

	atm.set_wind(Vector2(1.0, 0.0), 1.5, 1.4, 0.4)
	var wv := Atmosphere.get_wind_vector()
	t.check(is_equal_approx(wv.x, 1.5) and is_equal_approx(wv.z, 0.0),
		"C-14 wind vector reflects set_wind()", str(wv))

	sun.queue_free()
	atm.queue_free()
