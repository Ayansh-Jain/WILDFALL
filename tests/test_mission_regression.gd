extends Node
func run(t) -> void:
	var suite := preload("res://tests/test_campaign.gd").new()
	add_child(suite)
	suite.t = t
	suite.main = t.main
	suite.c = t.main.campaign
	suite.player = t.main.player
	suite.world = t.world
	suite.cycle = t.world.get_node("DayNightCycle")
	suite._pure_state()
	var c: CampaignDirector = t.main.campaign
	c.restart_campaign()
	c.opening_completed = true
	for id in [1,2]:
		for state in [CampaignState.M.BRIEFING_AVAILABLE,CampaignState.M.BRIEFING,CampaignState.M.ACTIVE,CampaignState.M.ENCOUNTER_ACTIVE,CampaignState.M.OBJECTIVE_COMPLETED,CampaignState.M.RETURN_TO_CASTLE,CampaignState.M.COMPLETE]:
			c.state.transition(id,state)
	c.army.spawn_missing(c._courtyard(),0)
	await t.physics_frames(5)
	await suite._army_orders()
	for id in [3,4,5]:
		for state in [CampaignState.M.BRIEFING_AVAILABLE,CampaignState.M.BRIEFING,CampaignState.M.ACTIVE,CampaignState.M.ENCOUNTER_ACTIVE,CampaignState.M.OBJECTIVE_COMPLETED,CampaignState.M.RETURN_TO_CASTLE,CampaignState.M.COMPLETE]:
			c.state.transition(id,state)
	suite._persistence()
	# Old saves retain their original council progression without unexpected Mission 1 insertion.
	var saved := c.state.to_dict()
	saved["states"]["1"] = "Reserved"
	saved["completed"].erase(1)
	var migrated := CampaignState.new(c.config)
	t.check(migrated.from_dict(saved) and migrated.state_of(1)==CampaignState.M.COMPLETE and migrated.roster_size()==c.state.roster_size(),"legacy reserved mission migrates without adding recruits")
	suite.queue_free()
