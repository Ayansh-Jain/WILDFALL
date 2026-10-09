# WILDFALL — Phases 1–2: World, Secret Identity and Combat

First-person dark-fantasy game for 8–10 players (multiplayer comes in Phase 3).

- **Phase 1:** the world, the player controller, hiding / line of sight, and the scroll.
- **Phase 2:** the scroll grants a hidden monster identity (the Ember Beast), plus
  transformation, combat, human defences, a Power score, and simulated opponents to
  test against. See [Phase 2](#phase-2--secret-identity-and-combat).

- Engine: **Godot 4.7.2** (any 4.7.x should work), GDScript only, no plugins or paid assets.
- Renderer: **Compatibility** (OpenGL 3.3). Chosen for steady frame rates on integrated
  GPUs; fog, glow, shadows and the night sky all work in it.
- Physics: Jolt (Godot built-in).

## Run the game

1. Open Godot 4.7, **Import** `Game/project.godot`, then press **F5**.
   If the editor already had the project open while these files were created, use
   **Project → Reload Current Project** first (do not save project settings over the new
   `project.godot`).
2. Command line (from the `Game` folder):
   `"<path>\Godot_v4.7.2-stable_win64.exe" --path .`

The world is generated at start-up from a fixed seed (about 3 s on an i5-1235U),
behind a short loading screen.

## Controls

| Action | Default | | Action | Default |
|---|---|---|---|---|
| Move | W A S D | | Interact | E |
| Look | Mouse | | Pause / settings | Esc |
| Jump / swim up | Space | | Debug overlay | F3 |
| Sprint | Shift | | Crouch / dive | Ctrl or C |

**Changing controls:** press **Esc → Controls**, click a binding and press the new key or
mouse button (Esc cancels, *Reset to defaults* restores). Bindings and the options under
**Esc → Settings** (mouse sensitivity, invert Y, FOV, head bob, volume) are saved to
`user://settings.cfg` (on Windows: `%APPDATA%\Godot\app_userdata\WildFall\settings.cfg`).
Default bindings live in `DEFAULT_BINDINGS` in `scripts/managers/settings.gd`.
Movement tuning (speeds, jump, crouch, swimming, step height, head bob) is exported on the
`Player` node (`scenes/player/player.tscn`).

**Esc → Game → Unstuck** returns you to the nearest spawn. Falling below the world respawns
you automatically.

## Test the scroll

Developer keys work in debug runs (editor / `--path .`), not in release exports:

| Key | Developer tool |
|---|---|
| F4 | Drop / remove a **sight probe** (a floating eye). It turns red and draws red rays when it can see you, and green when you are hidden. Walk behind a tree, rock or wall to watch it change. |
| F6 | Teleport to the next point of interest (bridges, fords, cave, keep, viewpoints...) |
| F7 | Teleport beside the scroll |
| F8 | Noclip (fly) |

1. Press **F5**, then **F7**. The console also prints the chosen marker, e.g.
   `[ScrollSpawner] seed 20240 -> marker 'west_clearing'`.
2. Look at the glowing scroll. Within about 2.8 m the prompt **[E] Take the scroll** appears.
3. Press **E**. The scroll vanishes with a chime and you privately become the Ember Beast,
   still looking human. **F3** only shows *scroll taken*, never who took it. The scroll
   cannot be collected again.

**Seeds.** Debug runs use a fixed scroll seed (20240) so placement is reproducible.
Pass options after `--`:

```
--scroll-seed=N    reproducible placement with seed N
--random-scroll    random placement in a debug run
--world-seed=N     different prop scattering / terrain noise (layout stays the same)
--no-dev           behave like a release build: random scroll, dev keys off
```

Example: `Godot_v4.7.2-stable_win64.exe --path . -- --scroll-seed=5`

The scroll picks one of 12 designated markers (ruins, keep top, cave chamber, island,
watchtower top, chapel, castle, hut, clearings, summit). Every marker is validated at
start-up (ground, not underwater, walkable slope, no geometry overlap). Markers that fail
are skipped and reported. Nothing on screen reveals the scroll in normal play.

## Phase 2 — Secret identity and combat

The loop: explore, find the scroll, gain monster powers, approach other players, choose
whether to reveal, then fight or escape, and gain or lose Power. Phase 2 has no networking:
you play against **simulated opponents** (four "Wanderers" spawn by default; set `-- --bots=N`).

### Controls

| Action | Human (and hidden monster) | Revealed Ember Beast |
|---|---|---|
| Mouse L (`attack`) | Sword strike | Claw |
| Mouse R (`heavy_attack`) | none | Heavy Strike |
| Q (`ability_1`) | Dodge | Pounce |
| R (`ability_2`) | Ward | Roar |
| F (`transform`) | Reveal the beast (only if you hold the scroll's power) | Return to human (when allowed) |

All of these keys can be rebound in **Esc → Controls**. A hidden monster has exactly the
human moveset, so its actions give nothing away.

### Testing the mechanics (debug runs)

| Key | Developer tool |
|---|---|
| F7, then E | Go to the scroll and take it (the real way to become the beast) |
| F10 | Give yourself the Ember Beast without the scroll |
| F11 | Spawn three wanderers around you (one fights back) |
| F9 | Spawn a hostile test hunter behind you: it stalks hidden, reveals within about 12 m and attacks |

- **Be the monster:** press F10 (or take the scroll), then F11. Walk up to the wanderers
  looking human, press **F** to reveal, then try claw, heavy strike, pounce and roar. Watch
  the cooldowns and Power in the HUD. After 12 s, and once you've been out of combat for
  4 s, **F** returns you to human form. Transforming again has a 20 s cooldown.
- **Escape as a human:** press F9 and run. Sprint costs stamina; **Q** dodges with brief
  invulnerability; **R** wards (2 per life) to stun the beast for 2 s. The hunter gives up
  after about 4 s without line of sight, so break it with trees, rocks and ruins.
- The HUD shows health, stamina, Power, ability slots with cooldowns (and ward charges), a
  private transformation status line (only for you, only if you hold the power), hit and
  hurt feedback, and a short event feed.

### Abilities and balance values (prototype, intentionally unbalanced)

All of these are data: `data/abilities/*.tres`, `data/forms/human.tres`,
`data/monsters/ember_beast.tres` and `data/scoring_rules.tres`.

| Ability | Damage | Range / radius | Wind-up | Cooldown | Notes |
|---|---|---|---|---|---|
| Sword strike (human) | 12 | 2.3 m, 80° cone | 0.15 s | 0.8 s | one target |
| Dodge (human) | none | 5 m dash | none | 1.4 s | 25 stamina, 0.25 s invulnerable, stopped by walls |
| Ward (human) | 10 | 6 m, needs line of sight | none | 8 s | 2 charges per life; stuns revealed beasts 2 s; knockback; ignores hidden monsters |
| Claw | 18 | 2.8 m, 70° cone | 0.18 s | 0.7 s | needs a valid target in range and facing |
| Heavy Strike | 45 | 3.3 m, 60° cone, up to 4 targets | 0.85 s (ground telegraph) | 4 s | 0.4 s stun and knockback; interrupted by a stun or 15+ damage during the wind-up (0.7 s stagger); dodge it with invulnerability or by leaving the cone |
| Pounce | 15 on landing | 9 m leap, 2.4 m landing radius | 0.2 s | 8 s | 0.3 s stun; walls stop it |
| Roar | none | 10 m pressure / 28 m reveal | 0.35 s | 15 s | slows to 60% and blocks sprinting for 2.5 s; marks players within 28 m for 4 s, on the roaring player's HUD only |

| Form | Health | Walk / sprint | Stamina (drain / regen per s) | Body |
|---|---|---|---|---|
| Human | 100 | 4.6 / 7.4 m/s | 100 (22 / 20) | 1.8 m |
| Ember Beast (revealed) | 250 | 5.0 / 7.2 m/s | 100 (22 / 22) | 2.5 m collision, about 3 m model |

**Transformation:** 0.9 s animation (no attacks, half speed); must stay revealed at least
12 s; can't return to human within 4 s of dealing or taking damage; 20 s cooldown before
transforming again; refused if there is no headroom.

**Defeat:** 4 s down (falling camera, no input), then 1 s respawning at the spawn farthest
from where you fell, then 3 s of protection. A monster stays a monster (respawns hidden, with
the transform cooldown running).

**Power** (`scripts/combat/power_score.gd` is the only place it changes; it never affects
combat):

| Event | Change |
|---|---|
| Start | 100 |
| A revealed beast defeats a player | +25 for the beast, −5 for the player |
| A revealed beast is defeated | −40 for the beast, +30 for the final blow, +15 for each other player who damaged it in the last 15 s |
| A player hurt by a beast survives 15 s and gets at least 20 m away | +10 |

Every award has a unique key, so a replayed or duplicated event never pays twice.

### How it is built

- **State model:** `scripts/match/player_state.gd` defines HUMAN, MONSTER_HIDDEN,
  MONSTER_REVEALED, DEFEATED and RESPAWNING, with a validated transition table. Holding monster
  powers (`monster_id` on the record) is separate from showing them (the state).
- **Server-ready authority:** `GameState` owns player records and the secret identity.
  `Combat` (`scripts/combat/combat_authority.gd`) owns every rule: validation, cooldowns,
  wind-ups, cone, range and line-of-sight hit checks, damage, interruption, transformation,
  defeat and respawn. It runs on its own simulation clock. Avatars, bots, HUD and visuals
  only send requests and react to signals, so `Combat` can move to the server in Phase 3.
- **Privacy:** public signals and `GameState.public_view()` never carry the identity.
  `identity_granted` and `roar_marks` are per-player messages. The beast model is created
  only when the (visible) transformation starts, so a hidden monster's scene tree is
  identical to a human's (tested). Bots all carry the same `Brain` node whatever their role.
  The overlay shows identity details only for yourself, and only in developer builds.
- **Data-driven monsters:** add a `MonsterDefinition` `.tres` under `data/monsters/`, its
  abilities under `data/abilities/`, and a rig in `AvatarVisual.create_rig()`.
- **Characters:** `scripts/characters/` holds procedural low-poly rigs animated in code,
  modelled on the reference sheets. The Explorer has dark hair, a red scarf and hood, a grey
  tunic with leather harness, pouches and a hip lantern, a backpack with bedroll, a tattered
  cloak, bracers, boots and a sword. The Ember Beast is a hunched charcoal brute with glowing
  cracks, burning eyes and mouth, swept horns, spiked back and tail, red claws, embers and
  smoke. Animations: idle, walk/run, crouch, jump, attack, dodge roll, ward, hurt, defeat;
  beast claw, heavy wind-up and slam, pounce, roar, transform. First-person
  `scripts/player/view_model.gd` shows a sword and lantern (which lights your way) as a human,
  and ember claws as the beast.
- **Simulated opponents:** `scripts/ai/sim_bot.gd` drives a normal avatar through the same
  input and Combat requests a player uses. Wanderers explore trails, flee revealed beasts
  (sprint, dodge, ward, cover), and the brave ones fight back. Hunters stalk hidden, reveal
  up close, chase, and give up without line of sight.

## Automated tests

```
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1                 # everything (~1 min)
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1 -Extra "--skip-walk"
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1 -Extra "--only=scroll"
```

The wrapper runs an import pass and then the headless suite (`tests/test_runner.tscn`). It
fails on any `SCRIPT ERROR`. Set `GODOT` or pass `-Godot <console exe>` if Godot is not at
`D:\Godot_v4.7.2-stable_win64.exe\`. The suites drive the real player controller through
physics:

- **terrain**: collision matches the height function, water depths, fords, island, cave holes and roof, mountain edge.
- **spawns**: 11 valid player spawns far from the landmark, spread out and dry; all 12 scroll markers valid, deterministic, varied, exactly one scroll.
- **line_of_sight**: walls, trunks, terrain and bushes block sight; bushes do not block movement; a player behind a wall is hidden; view cone; the sight probe.
- **player**: landing, walk/sprint/crouch speeds, jump height, mouse look and pitch clamp, staying crouched under a roof, step-up vs. wall, wall collision, swimming, wading, fall respawn.
- **scroll**: prompt distance and facing, collection through an `interact` input event, single collection, removal, match reset.
- **settings**: rebinding (including through the Esc menu), persistence, reset, live sensitivity, head bob on/off.
- **traversal**: walks every trail, both bridges, both fords, the island causeway, the lake swim, the citadel keep, rampart and inner passage, the watchtower stairs, the whole cave, the landmark dais, the summit, the chapel, castle and hut, and three off-trail forest crossings.
- **identity** (Phase 2): collecting once; refusal of a second collection by anyone; public vs. private views; identical scene trees for hidden monsters and humans; no identity in the overlay; transform rules (no powers, no room, reveal lock, cooldown, combat lockout); camera and mouse look during the transformation; powers kept after returning to human.
- **combat**: claw wind-up, exact damage, cooldown; range, facing and wall checks; no damage from proximity alone; heavy-strike wind-up, stun, dodge by invulnerability, stepping out, interruption by ward or damage; stunned players can't act; pounce distance, landing hit, cooldown and walls; roar slow and private marks; the human sword.
- **defense**: stamina drain, exhaustion and regeneration; dodge distance, cost, invulnerability window, walls and spam limit; ward stun, damage, knockback, line of sight, charges and ignoring hidden monsters; humans out-sprint the beast; a ward opens a gap; hunters lose you behind cover; a chase comparing a human using its tools with one standing still.
- **power**: base score; prey reward and penalty; slayer and assist rewards; monster penalty; escape reward; every award applied exactly once, even when events are replayed; defeat → respawning → valid state for both humans and monsters; respawn protection and camera; invalid state transitions refused.
- **soak**: one hunter and five wanderers fighting freely for three simulated minutes, checking state invariants on every player every second.

Visual and performance check (windowed; saves PNGs and prints frame times):
`Godot_v4.7.2-stable_win64_console.exe --path . res://tests/screenshot_tour.tscn -- --out=C:/temp/shots [--vsync] [--only=name]`

## The world

About 600 × 600 m of playable ground, ringed by impassable mountains (terrain extends to
680 m). The layout is hand-authored in **`data/world_layout.json`**: regions, rivers,
lake, fords, bridges, hills, ridges, trails, forest zones, clearings, sites, the cave map,
spawns, scroll markers and points of interest. Edit that file and rerun to reshape the map.

```
                         N (-Z)   waterfall
   Greyback Ridge   [Hollow Deep cave]    |   NE hills
         \           North Wall ridge     |      Old Ford ---- Crag Spine
   Old Citadel ----------- trails --- North Bridge         Sentinel Crag (summit)
   (main ruins)   Moss Knoll    \         |
   West woods          ELDER TREE (0,0)   Moonmere Lake  (island shrine via causeway)
   Fern Knoll          (landmark)          \        East Downs
        Sunken Chapel        South Barrow   Stone Bridge    Lakeside Castle
   Watcher's Hill (watchtower)      Reed Ford     \
                         S (+Z)    river exits under a rock arch
```

- **Deep Forest**: west, south-west, north-west and east woods. Pines, firs, oaks, birches, dead trees, bushes, logs, boulders, ferns, glowing mushrooms; clearings and off-trail routes.
- **Ancient Ruins**: the Old Citadel has three gates, a breach, a collapsed corner, a raised keep with stairs and a rubble ramp, a walkable rampart, narrow inner passages, a courtyard and a collapsed hall. Smaller sites: Sunken Chapel, Lakeside Castle, Watchtower, Island Shrine, Ferryman's Hut, Hunter's Camp.
- **Lake and river**: Moonmere Lake, and the Silverrun river running north to south through it. Crossings: North Bridge (wood), Stone Bridge, Old Ford, Reed Ford, and the island causeway. Shore trails run on both sides, and deep water is swimmable.
- **Caves**: the Hollow Deep has two mouths, a tunnel loop and a crystal chamber. A trail of glowing mushrooms leads back out. Inside, ambient light dims and audio gains reverb. The cave is optional.
- **Elevated terrain**: Watcher's Hill, Sentinel Crag, Greyback Ridge, the North Wall ridge, the cave dome, and viewpoints on the watchtower and the keep.
- **Landmark**: the Elder Tree, about 45 m tall, on a stepped dais with rune stones, kneeling statues and a sword in stone. Its fog-piercing lantern-orbs are visible from the viewpoints.

## Project structure

```
Game/
  data/world_layout.json        hand-authored layout (the main design file)
  scenes/                       main, world, player, interactables (HUD and menu are built in code)
  scenes/world/props/           reusable @tool ruin pieces (wall, pillar, archway, stairs, ...)
  data/abilities, forms, monsters, scoring_rules.tres   Phase 2 combat data
  scripts/managers/             Settings, GameState (autoloads), Ambience
  scripts/match/                PlayerState (state model), PlayerRecord
  scripts/combat/               Combat authority + PowerScore (autoloads), Combatant,
                                Ability/Form/Monster definitions, ScoringRules
  scripts/characters/           CharacterRig, HumanRig, EmberBeastRig, AvatarVisual, Fx
  scripts/ai/                   SimBot (simulated opponents)
  scripts/world/                terrain data + mesh, vegetation, sites, landmark, bridge, cave,
                                spawn validation, scroll spawner, mesh kit, layers
  scripts/world/pieces/         RuinPiece (the reusable piece script)
  scripts/player/               controller, interactor, abilities input, first-person view model
  scripts/interactions/         Interactable, Scroll
  scripts/stealth/              LineOfSight utility, SightProbe debug tool
  scripts/ui/, scripts/main/    HUD, pause menu, bootstrap
  scripts/audio/                Synth (placeholder sound generator), AudioLib
  assets/materials/             shaders and .tres materials (terrain, water, sky, props, glow)
  assets/audio/                 generated .wav placeholders (replace with recordings of the same name)
  tools/generate_audio.gd       regenerates assets/audio
  tests/                        headless suites, runner, screenshot/perf tour
```

How this differs from the suggested layout:

- `scripts/stealth`, `scripts/ui`, `scripts/main` and `scripts/audio` were added to keep responsibilities apart.
- `tools/` holds editor-time scripts.
- The HUD and pause menu are built in code, so there are no `scenes/ui` scene files.
- `assets/models` and `assets/textures` are empty: all geometry is procedural low-poly, and surface detail comes from shaders.

Repeated props use chunked `MultiMeshInstance3D` (68 m chunks, distance-culled). Their
collision lives in batched static bodies (`StaticBatch`): trunks, rocks and logs are on the
`world` layer. Bushes are on `foliage_sight`, which blocks line of sight but not movement.

## Performance

Measured with `screenshot_tour` on an Intel i5-1235U with Iris Xe graphics (a 15 W laptop
chip), over 22 viewpoints, during a 120 Hz session:

| | 1280 × 720 | 1920 × 1080 |
|---|---|---|
| Uncapped average frame | 7.4 ms (~134 fps) | 10.9 ms (~92 fps) |
| VSync on | 120 fps on gameplay views (p95 about 10 ms) | 60 fps (p95 about 23 ms, occasional missed frames) |

Draw calls stay around 250–500. Phase 2 re-measured with four bots plus the beast on screen:
about 7.3 ms (~138 fps) at 720p, the same as before.

## Known limitations

- The world is generated at runtime, so `world.tscn` looks empty in the editor. Ruin pieces preview individually, and the screenshot tour, F6 and noclip are the ways to inspect the map.
- Tree and rock collision uses server-side bodies, so *Debug → Visible Collision Shapes* does not draw it.
- Water is one flat plane at height 0. Rivers do not flow downhill, and the waterfall and river exit are visual set pieces.
- The terrain is a heightfield. The cave is built from blocky box geometry with rock dressing.
- Some mountain gullies past ~300 m can be climbed partway. The terrain edge is a fallback, and falling off the world respawns you.
- Sounds are synthesized placeholders. Faint shadow acne remains on some flat stone tops.
- Per-instance tints use MultiMesh instance colours, because custom data did not reach shaders in the Compatibility renderer on this GPU.
- No navigation mesh yet. The traversal tests use a simple steering walker. Future AI will need a navmesh.

Phase 2:

- No networking. Opponents are bots. `Combat` and `GameState` are written as the authority, but nothing is replicated yet, and "private" messages are local signals that Phase 3 must turn into per-peer RPCs.
- The characters are procedural placeholders: rigid low-poly parts animated in code, not skinned meshes. They follow the reference sheets' silhouettes and palettes, not their detail. Swap in real models through `AvatarVisual.create_rig()`.
- Balance values are prototypes. In the open forest, the flee bot survives far longer than a player standing still (about 27–30 s versus 5–6 s) but does not reliably shake the hunter. Escaping cleanly depends on breaking line of sight, which the tests show separately.
- The human's only attack is a light sword strike; a group of brave bots can wear a beast down. The bow from the reference sheet isn't implemented.
- A defeated beast keeps its powers (it respawns hidden). The scroll never returns to the world.
- The first-person hands and claws aren't on a separate render pass, so they can clip into walls when you stand very close.
- The in-world beast is about 3 m tall but its collision capsule is 2.5 m. Monster footsteps are the human sounds pitched down.
