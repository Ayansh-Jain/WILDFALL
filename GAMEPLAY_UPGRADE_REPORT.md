# WILDFALL gameplay upgrade ? implementation and verification

Implemented against the existing Godot game on 3 November 2026. Backup: `D:/WildFall/Backups/major_upgrade_20261103_100850`. The earlier `MISSION_1_IMPLEMENTATION.md` describes the prior gate/balcony version; this report supersedes that behavior.

## Implemented

- Removed the central sit prompt while keeping other contextual interactions. Removed the commander stamina bar, enabled unlimited commander sprint, and stopped instantiating the potion-drop controller. Independent horse/enemy stamina remains.
- Added a shared emissive crimson blade-ribbon shader and twelve short-lived GPU sparks per commander blade. The existing active animation window drives the effect; actual-hit sparks remain. No full-screen glow pass was added.
- Swapped the bedroom's north balcony and west window, including wall openings, glazing, balcony slab/rails/corbels, door orientation and collision. Moved the desk and its furnishings beneath the north window. The existing washstand now has oak privacy screens defining a small washroom alcove.
- Entering the washroom triggers four cameras in the existing world: river, waterfall, memorial cemetery, town. The commander remains in place, returns to his camera, delivers the requested homeland line, and receives a summons to the throne room. The environmental sequence and commander line total roughly sixteen seconds at normal dialogue speed, excluding the subsequent messenger exchange.
- Kept the king seated on the throne. The audience interaction sits in front of the throne; the commander walks the last steps with normal collision and uses the imported `kneel_fix` animation. Briefing names the king's four best commandos. Reports also use the royal audience.
- Corrected horse water-depth checks to recognize reachable bridge decks above submerged terrain. Near whistle recall uses existing routes plus obstacle feelers; deep-water direct shortcuts use the route graph. Far recall uses a fade and repositions the same horse at a validated nearby point. The default threshold is 100 world metres.
- Formation direction follows actual movement rather than camera yaw. Four soldiers use two rows of two. T on a deployed company clears paths and regroups it; distant or persistently trapped soldiers can recover only when both source and destination are unseen. Recovery runs on the command, not every frame.
- Army horses are absent on foot, created during the mounting fade, and removed after coordinated dismounting. The four soldiers use existing mounting animations. Normal and forced dismount cleanup are covered. The personal horse remains independent.
- Added commander regeneration at 2 HP/second after a three-second damage delay, with fractional accumulation, health caps and a smoothed health display.
- Added a drawn gold coin icon and counter at top right, separated from the combat feed. Designated enemy deaths caused by commander or army award 500 once. The campaign save stores the wallet and stable mission/enemy reward ledger, including the giant. Retrying does not duplicate previously earned kill rewards. No store was built.
- The camp has ten ordinary stationary guards/sitters, four black pitched-roof tents, crates, barrels, bedrolls and a fire ring. Tents have physical/vision-blocking walls, appear on the existing strategy map, and leave the tested road/giant exit clear. Confirm/cancel and faded tactical placement are retained.
- Clearing the ten guards triggers a short celebration and movement/combat lock, followed by rumble, camera shots, the giant physically exiting its tent, a confrontation and the solo challenge dialogue. The camera remains controllable during the celebration. Ordinary camp clearance does not complete the mission.
- The giant reuses the black soldier rig at 1.6 scale with enlarged collision, 400 HP, slow movement, a one-second heavy telegraph, 30 damage per resolved melee contact, cooldown/recovery, and a dedicated smoothed boss bar. Combat's normal range, cone and line-of-sight checks resolve attacks. Allied damage to the giant is rejected centrally, and allies wait during the duel. Only the giant's combat death enables the return/report objective and awards its 500 coins.
- Sealed all three authored cave mouths using removable rockfall geometry and collision. The existing cave interior is preserved; the original scroll now spawns at its cave marker. The former duplicate story-scroll instance is no longer created. `Cave.unlock_entrances()` is available for a future story unlock, but no current player unlock was added.
- Added optional voice-file mapping with one dialogue stream, synchronized subtitle duration, skip/stop behavior and queued dialogue requests. See `DIALOGUE_AUDIO.md`.

Configuration: `data/gameplay_upgrade.json` contains regeneration, recall/recovery thresholds and giant combat values. `data/dialogue_voices.json` is intentionally empty until recordings are supplied.

## Tested successfully

Tests instantiate the real main scene, world, controllers and central combat authority. Focused tests use staging fixtures where described in their source; the complete mission test drives actual traversal and attacks through the updated mission.

| Evidence in `D:/WildFall/Screenshots/` | Result |
| --- | --- |
| `upgrade_mission_verified.log` | 30 passed: washroom, physical bedroom-to-throne traversal, interaction/briefing, four escorts, mounting, road travel, strategy confirmation/cancel, ten-enemy combat, telegraph-aware giant duel, road return and actual throne report |
| `upgrade_regression_final.log` | 84 passed: all new focused phase checks plus campaign state, roster, orders and save/load regressions |
| `upgrade_rendered_final.log` | 9 passed in Compatibility rendering: royal audience pose, tactical deployment, camp battle, giant duel and report |
| `upgrade_performance_final.log` | 23 passed in Compatibility rendering: mounting/forced dismount, formation/recall, full camp and giant combat/report, without screenshot capture |
| `upgrade_slash.log` | 71 commander checks passed with the new blade shader in the actual renderer |

The focused world test includes an actual horse traversal across the existing stone bridge and collision checks at every cave mouth. The boss test verifies 400 HP, hidden initial state, nearby-player emergence, solo damage rules, a real 30-HP hit, sword-combat defeat, one 500-coin reward and completion gating.

Inspected rendered captures: `upgrade_royal_audience.png`, `upgrade_giant_duel.png`, `mission_red_slash.png`. Additional tactical/combat captures are in the same folder.

### Performance measurement

Intel Iris Xe, Godot 4.7.2 Compatibility renderer, 1280?720, screenshot capture disabled: combat render average **20.42 ms (~49 FPS)**, p95 **28.16 ms**, worst sampled frame **45.25 ms**, approximately 1,024 draw calls in the sampled frame. This is a measured run, not a locked-60-FPS guarantee. The earlier screenshot-enabled run included image readback/file-save stalls and is not the clean performance measurement.

## Placeholders

- No recorded voice acting or TTS has been supplied. Subtitles and existing character gestures are active; voice mapping is prepared.
- Commander whistle and giant rumble are synthesized placeholder audio. Existing footsteps/combat sounds remain.
- Tents and rockfalls use lightweight procedural geometry and existing material conventions. No replacement character models were introduced.

## Not fully tested / remaining validation

- Normal-speed cinematic shot composition and pacing have not had a complete manual editorial pass. Voice synchronization still needs verification with the eventual recordings.
- The tested recall routes and bridge crossing do not constitute exhaustive navigation coverage of every riverbank, building or possible stuck location.
- Long-session memory/performance stability, every legacy test suite, multiplayer behavior and every possible retry/save interruption during a cinematic were not exhaustively exercised.
- More art/audio polish and broader device benchmarks remain appropriate before release. A future cave unlock and store are deliberately outside this task.

## Known bugs

No unresolved blocker appeared in the final tested first-mission flow. Earlier failing runs exposed a tent obstructing a road, a giant stopping inside its tent when the player was close, a boss HUD placement error, and a startup HUD null access; those were fixed and relevant checks rerun. The remaining validation areas above should not be interpreted as proven bug-free.

## Changed source/data/test files

- `scripts/ai/soldier_brain.gd`
- `scripts/campaign/army.gd`
- `scripts/campaign/campaign_director.gd`
- `scripts/campaign/campaign_state.gd`
- `scripts/campaign/commander_vitals.gd`
- `scripts/campaign/encounter.gd`
- `scripts/campaign/giant_duel.gd`
- `scripts/characters/avatar_visual.gd`
- `scripts/characters/blade_trail.gd`
- `scripts/combat/combat_authority.gd`
- `scripts/horse/horse.gd`
- `scripts/main/main.gd`
- `scripts/player/player_controller.gd`
- `scripts/player/player_interactor.gd`
- `scripts/player/rider.gd`
- `scripts/story/castle_opening.gd`
- `scripts/story/story_director.gd`
- `scripts/ui/coin_icon.gd`
- `scripts/ui/combat_hud.gd`
- `scripts/ui/hud.gd`
- `scripts/ui/tactical_map.gd`
- `scripts/world/cave.gd`
- `scripts/world/royal_castle.gd`
- `scripts/world/scroll_spawner.gd`
- `scripts/world/sites.gd`
- `data/campaign.json`
- `data/dialogue_voices.json`
- `data/gameplay_upgrade.json`
- `tests/test_mission_encounter.gd`
- `tests/test_mission_one.gd`
- `tests/test_runner.gd`
- `tests/test_upgrade_boss.gd`
- `tests/test_upgrade_castle.gd`
- `tests/test_upgrade_mount.gd`
- `tests/test_upgrade_navigation.gd`
- `tests/test_upgrade_presentation.gd`
- `tests/test_upgrade_vitals.gd`
- `tests/test_upgrade_world.gd`

New assets: `assets/materials/crimson_trail.gdshader`, `assets/audio/commander_whistle.wav`, `assets/audio/giant_rumble.wav` (plus Godot import metadata). New documentation: this report and `DIALOGUE_AUDIO.md`.
