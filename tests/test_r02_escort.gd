extends Node
## R02: T in the campaign calls a holding four-soldier escort and dismisses it.
func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var drv := PlayerDriver.new(p)
	c.restart_campaign()
	c.speed = 0.05
	t.main.story.speed = 0.01
	c.opening_completed = true
	c.state.transition(1, CampaignState.M.BRIEFING_AVAILABLE)
	await c.brief(1)
	var field := SpawnValidator.find(t.world, Vector2(-232, 112))
	p.teleport(field.position, 0)
	await drv.frames(10)
	var roster := c.state.roster_size()
	await c.toggle_army()
	var company := c.escort.living()
	t.check(c.deployed and company.size() == 4 and not c.army.is_following(), "T calls a four-soldier holding escort", str(company.size()))
	var posts: Array = company.map(func(b) -> Vector3: return b.avatar.global_position)
	var behind := true
	for post: Vector3 in posts:
		behind = behind and p.forward().dot(post - p.global_position) < -2.0 and post.distance_to(p.global_position) < 10.0
	t.check(behind, "they stand behind him")
	drv.set_input(Vector2(0, 1))
	await drv.frames(300)
	drv.set_input()
	var drift := 0.0
	for i in company.size():
		drift = maxf(drift, company[i].avatar.global_position.distance_to(posts[i]))
	t.check(drift < 1.5, "they hold while he walks away", "%.2f m" % drift)
	# Mounting does not drag a holding company along or put it on horses.
	var horse: Horse = t.main.horse
	horse.teleport(p.global_position + p.global_basis.x * 1.3, p.rotation.y)
	var rider := p.get_node("Rider") as Rider
	await drv.frames(10)
	rider.mount(horse)
	await drv.frames(240)
	rider.force_dismount()
	await drv.frames(60)
	drift = 0.0
	for i in company.size():
		drift = maxf(drift, company[i].avatar.global_position.distance_to(posts[i]))
	t.check(drift < 1.5 and c.army.horses.is_empty(), "his mounting leaves the escort posted", "%.2f m" % drift)
	var victim = company[0]
	var dead: int = victim.soldier_id
	Combat.apply_damage(victim.avatar.player_id, 999, -1, "test")
	await drv.frames(10)
	await c.toggle_army()
	t.check(not c.deployed and not c.escort.active(), "T dismisses")
	await c.toggle_army()
	var again := c.escort.living().map(func(b) -> int: return b.soldier_id)
	t.check(again.size() == 3 and not again.has(dead) and c.state.roster_size() == roster and not c.state.soldier(dead).alive,
		"the fallen stay fallen and nobody is created", "%s of %d" % [again, roster])
	await c.toggle_army()
	c.restart_campaign()
	drv.release()
