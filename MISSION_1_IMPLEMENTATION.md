# Mission 1 ? The Commander's First War

Implemented in the existing Godot project. Start **New Campaign** to play the opening; older saves preserve their existing campaign progression.

## Playing

- Walk to the bedroom balcony. The 4.5-second kingdom camera sequence returns to your position, followed by a three-second delay, synthesized knock and summons.
- Open the bedroom door, descend the existing stairs and speak with the king at the gate.
- Press **T** to assemble four maroon soldiers through a fade. Soldiers hold fire until engagement. Available real horses support mounted escort; unmounted soldiers remain on foot.
- Travel to the jungle camp. Press **M** within 65 metres while hidden and on foot to open the tactical table. Both keys are rebindable in Controls.
- Select a numbered soldier and click clear ground outside the warning boundary. Use **Place group** for quick placement. Confirm Strategy opens a separate Confirm/Cancel dialog; cancelling retains placements.
- Advance after deployment. Detection gives the attack order and enemies react before engaging. Defeat the designated ten black soldiers, then return on foot or horseback to report to the king. Survivors regroup; reporting returns them through a fade without resetting their health/death records.

## Implementation

Reused StoryDirector dialogue, CampaignState checkpoints, the king, soldier models, imported animations, Army horse assignments, Battlefield target slots, collision queries and Combat authority. Added a camp encounter, a local tactical table with terrain/obstacle samples and authored roads, conservative detection warning radius derived from actual enemy sight ranges, and persistent tactical coordinates. Enemy markers require camera visibility and unobstructed world sight.

Vision defaults to 10 m with a configurable 2.5 m close radius; walls also block close detection. Checks are sampled, not performed every frame. Castle and town guards remain at their posts, with two configured guards per town. Four-person escorts use two files. Enemy reactions distinguish resting soldiers from standing guards. Camp props are lightweight bedrolls and a stone fire ring.

Damage is centralized in `data/combat_balance.json`: commander 50, finisher 100 per contacted target, allied soldiers 20, enemy soldiers 10. Existing attack timing, target limits, invulnerability and wall checks remain authoritative. Bright red blade ribbons follow the actual sword transforms during attack frames, then decay; the older generic pale slash is suppressed on commander-derived rigs.

## Validation and evidence

All runs used the actual Godot 4.7.2 project and player/combat systems. Tests are automated game scenarios, not a claim of a manual human playthrough.

| Run | Result | Evidence |
|---|---|---|
| Full mission traversal, mounted interaction, battle and physical return/report | 27 passed, 0 failed | [Full mission log](../Screenshots/mission_full_final.log) |
| Final rendered encounter plus commander model/animation/input regression | 77 passed, 0 failed | [Final validation log](../Screenshots/mission_final_validation.log) |
| Campaign state, explicit orders, persistence and legacy migration recheck | 30 passed, 0 failed | [Campaign recheck](../Screenshots/mission_regression_recheck.log) |
| Exact damage, attack windows, walls, close detection and range | 10 checks passed, plus 6 encounter checks | [Rules and encounter log](../Screenshots/mission_rendered_final.log) |
| All four escorts on distinct horses, movement direction and dismount | 4 checks passed | [Mounted checks](../Screenshots/mission_release_check.log) |

The broad legacy run recorded 197 passes and three failures: headless mouse-capture lamp input, an obsolete automatic-attack assertion, and an old four-completed-mission save assertion. The rendered lamp check and revised order/save checks subsequently passed. A combined rendered run also exposed test contamination from drawn swords; encounter teardown now sheathes them, and the final 77-check run passed. The entire repository suite was not rerun as one final invocation.

Screenshots: [Tactical table](../Screenshots/mission_strategy.png), [battle](../Screenshots/mission_combat.png), [actual red blade trail](../Screenshots/mission_red_slash.png).

Performance: Compatibility/OpenGL, Intel Iris Xe, 1280?720, full encounter, screenshot capture disabled for the final measurement. Mean rendered frame time **23.28 ms** (~43 FPS), 95th percentile **31.72 ms**, worst **183.17 ms**. The encounter completed with all ten enemies defeated and four allies surviving. This is playable, but is not a locked-60-FPS result; intermittent hitches remain a performance-polish item. Earlier `average_process_ms` instrumentation in older logs was replaced with wall-clock samples between rendered process frames; use the final log's `render frame times` line.

## Assets and remaining polish

- Dialogue/attack/alert lines use subtitles; recorded performances are not included.
- Door knock and assembly audio use synthesized/existing placeholder sounds.
- The commander starts awake in the preserved bedroom at morning; no new lying-in-bed/wake-up animation was authored.
- Camp bedrolls/fire ring and the strategy table are functional procedural visuals, not a new premium environment-art pack.
- The existing map, scene files, imported character assets and textures were preserved. Scene-file comparison against the backup: byte-for-byte unchanged.

## Backup and changed files

Backup: `D:/WildFall/Backups/mission1_20261102_180423` (scripts, data, tests and scenes before edits).

The following source/data/test files differ from that backup; this report is also new. Godot's local generated cache is excluded.

- [`scripts/ai/soldier_brain.gd`](scripts/ai/soldier_brain.gd)
- [`scripts/audio/synth.gd`](scripts/audio/synth.gd)
- [`scripts/campaign/army.gd`](scripts/campaign/army.gd)
- [`scripts/campaign/campaign_director.gd`](scripts/campaign/campaign_director.gd)
- [`scripts/campaign/campaign_state.gd`](scripts/campaign/campaign_state.gd)
- [`scripts/campaign/encounter.gd`](scripts/campaign/encounter.gd)
- [`scripts/campaign/garrison.gd`](scripts/campaign/garrison.gd)
- [`scripts/characters/avatar_visual.gd`](scripts/characters/avatar_visual.gd)
- [`scripts/characters/blade_trail.gd`](scripts/characters/blade_trail.gd)
- [`scripts/characters/commander_rig.gd`](scripts/characters/commander_rig.gd)
- [`scripts/combat/combat_authority.gd`](scripts/combat/combat_authority.gd)
- [`scripts/managers/settings.gd`](scripts/managers/settings.gd)
- [`scripts/story/castle_opening.gd`](scripts/story/castle_opening.gd)
- [`scripts/ui/tactical_map.gd`](scripts/ui/tactical_map.gd)
- [`scripts/ui/tactical_map.gd.uid`](scripts/ui/tactical_map.gd.uid)
- [`data/campaign.json`](data/campaign.json)
- [`data/combat_balance.json`](data/combat_balance.json)
- [`tests/test_campaign.gd`](tests/test_campaign.gd)
- [`tests/test_castle.gd`](tests/test_castle.gd)
- [`tests/test_castle_lifecycle.gd`](tests/test_castle_lifecycle.gd)
- [`tests/test_combat.gd`](tests/test_combat.gd)
- [`tests/test_mission_encounter.gd`](tests/test_mission_encounter.gd)
- [`tests/test_mission_mount.gd`](tests/test_mission_mount.gd)
- [`tests/test_mission_one.gd`](tests/test_mission_one.gd)
- [`tests/test_mission_regression.gd`](tests/test_mission_regression.gd)
- [`tests/test_mission_rules.gd`](tests/test_mission_rules.gd)
- [`tests/test_runner.gd`](tests/test_runner.gd)
