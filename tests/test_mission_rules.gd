extends Node
func run(t) -> void:
	var k := CombatKit.new(t)
	var p := t.main.player as PlayerController
	k.place(p,Vector3.ZERO)
	p.input_override = {}
	var enemy := SoldierFactory.spawn(self,t.world,{"faction":"enemy","pos":k.center+Vector3(0,0,-1.8),"exact":true,"max_health":300})
	enemy.paused = true
	enemy.sight_range = 10
	enemy.hear_range = 2.5
	await k.frames(5)
	Combat.request_action(p.player_id,"attack")
	await k.seconds(0.1)
	t.check(enemy.avatar.combatant.health==300,"sword cannot damage before active window")
	await k.seconds(0.25)
	t.check(enemy.avatar.combatant.health==250,"commander basic contact deals 50 once")
	await k.seconds(0.5)
	t.check(enemy.avatar.combatant.health==250,"one swing does not damage every frame")
	Combat.request_action(p.player_id,"special_attack")
	await k.seconds(0.5)
	t.check(enemy.avatar.combatant.health==150,"commander finisher contact deals 100")
	await k.seconds(0.5)
	var wall := k.wall(Vector3(0,0,-0.9),Vector3(4,3,0.3))
	await k.frames(3)
	Combat.request_action(p.player_id,"attack")
	await k.seconds(0.4)
	t.check(enemy.avatar.combatant.health==150,"sword cannot hit through wall")
	t.check(enemy._detect()!=p.player_id,"close-range detection blocked by wall")
	wall.queue_free()
	await k.frames(3)
	t.check(enemy._detect()==p.player_id,"close-range detection senses nearby commander")
	k.place(p,Vector3(0,0,15))
	await k.frames(5)
	t.check(enemy._detect()!=p.player_id,"enemy cannot detect beyond ten metres")
	k.place(p,Vector3.ZERO)
	k.face(enemy.avatar,p.global_position)
	var health := p.combatant.health
	Combat.request_action(enemy.avatar.player_id,"attack")
	await k.seconds(0.4)
	t.check(p.combatant.health==health-10,"enemy sword contact deals ten to commander")
	var ally := SoldierFactory.spawn(self,t.world,{"faction":"kingdom","pos":k.center+Vector3(1,0,-1.8),"exact":true})
	ally.paused = true
	k.face(ally.avatar,enemy.avatar.global_position)
	await k.frames(4)
	var eh := enemy.avatar.combatant.health
	Combat.request_action(ally.avatar.player_id,"attack")
	await k.seconds(0.4)
	t.check(enemy.avatar.combatant.health==eh-20,"allied soldier sword deals twenty")
	enemy.avatar.queue_free()
	ally.avatar.queue_free()
	await k.cleanup()
