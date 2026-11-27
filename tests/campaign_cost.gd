extends Node
## Headless per-frame cost of the always-present campaign objects (army at the
## muster, the company's horses, the King, the director), interleaved with and without
## the campaign so throttling affects both alike:
##   godot --headless --fixed-fps 60 --path . res://tests/campaign_cost.tscn

const MAIN_SCENE := preload("res://scenes/main/main.tscn")


func _ready() -> void:
	var results := {"with": [], "without": [], "nohorses": [], "nosoldiers": []}
	for round in 2:
		for mode in ["with", "without", "nohorses", "nosoldiers"]:
			var main := MAIN_SCENE.instantiate()
			main.auto_capture_mouse = false
			main.spawn_bots = false
			main.campaign_persist = false
			main.spawn_campaign = mode != "without"
			add_child(main)
			await main.ready_for_play
			if mode == "nohorses":
				for h in main.campaign.army.horses:
					h.queue_free()
				main.campaign.army.horses.clear()
			if mode == "nosoldiers":
				main.campaign.army.despawn_all()
			for i in 60:
				await get_tree().physics_frame
			var t0 := Time.get_ticks_usec()
			for i in 600:
				main.player.input_override = {"move": Vector2(0, 1)}
				await get_tree().physics_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 600.0
			results[mode].append(ms)
			print("[cost] %-8s round %d: %.2f ms per frame" % [mode, round, ms])
			main.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	print("[cost] ", results)
	get_tree().quit()
