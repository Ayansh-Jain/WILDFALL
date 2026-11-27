# WILDFALL â€” Phases 1â€“2: World, Secret Identity and Combat

First-person dark-fantasy game for 8â€“10 players (multiplayer comes in Phase 3).

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
   **Project â†’ Reload Current Project** first (do not save project settings over the new
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
| Sit / stand on suitable ground | G | | Call / dismiss your army | T |

**Changing controls:** press **Esc â†’ Controls**, click a binding and press the new key or
mouse button (Esc cancels, *Reset to defaults* restores). Bindings and the options under
**Esc â†’ Settings** (mouse sensitivity, invert Y, FOV, head bob, volume) are saved to
`user://settings.cfg` (on Windows: `%APPDATA%\Godot\app_userdata\WildFall\settings.cfg`).
Default bindings live in `DEFAULT_BINDINGS` in `scripts/managers/settings.gd`.
Movement tuning (speeds, jump, crouch, swimming, step height, head bob) is exported on the
`Player` node (`scenes/player/player.tscn`).
Press **G** on suitable flat ground to sit; press **G** again to stand.

**Esc â†’ Game â†’ Unstuck** returns you to the nearest spawn. Falling below the world respawns
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

## Phase 2 â€” Secret identity and combat

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

All of these keys can be rebound in **Esc â†’ Controls**. A hidden monster has exactly the
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
| Sword strike (human) | 12 | 2.3 m, 80Â° cone | 0.15 s | 0.8 s | one target |
| Dodge (human) | none | 5 m dash | none | 1.4 s | 25 stamina, 0.25 s invulnerable, stopped by walls |
| Ward (human) | 10 | 6 m, needs line of sight | none | 8 s | 2 charges per life; stuns revealed beasts 2 s; knockback; ignores hidden monsters |
| Claw | 18 | 2.8 m, 70Â° cone | 0.18 s | 0.7 s | needs a valid target in range and facing |
| Heavy Strike | 45 | 3.3 m, 60Â° cone, up to 4 targets | 0.85 s (ground telegraph) | 4 s | 0.4 s stun and knockback; interrupted by a stun or 15+ damage during the wind-up (0.7 s stagger); dodge it with invulnerability or by leaving the cone |
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
| A revealed beast defeats a player | +25 for the beast, âˆ’5 for the player |
| A revealed beast is defeated | âˆ’40 for the beast, +30 for the final blow, +15 for each other player who damaged it in the last 15 s |
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

## Visual overhaul (environment, lighting, first-person rig)

The map, collision, spawns and gameplay are unchanged; only materials, meshes and lighting were upgraded in place.

- **Terrain** (ssets/materials/terrain.gdshader): Poly Haven CC0 photo textures (grass, leaf litter, rocky trail, mud, cliff rock, snow, paving) with world-space normal maps, two-scale sampling against tiling, triplanar rock on slopes, snow on the high mountains. Layers are only sampled where present.
- **Vegetation** (scripts/world/foliage_meshes.gd): pines, firs, oaks, birches, bushes, ferns and grass are now textured bark trunks plus alpha-cut foliage cards (textures painted by 	ools/generate_foliage_textures.gd). Trees and bushes have a lighter far LOD (switch at ~70 m). Trunk sizes and collision are identical to before. Pebble clutter added.
- **Stone, rock, cave, ruins** (stone_tri.gdshader): triplanar photo-textured stone with normal maps and moss; stone.tres keeps its name, so every ruin, bridge and dais picked it up in place. Boulders use 
ock.tres, the cave cave_rock.tres.
- **Water**: Fresnel sky reflection, layered ripples and a moon glitter path aimed at the real moon.
- **Lighting**: AgX tonemapping, cooler and brighter moonlight, balanced ambient fill, low ground mist, thinner distance fog so mountain silhouettes read, softer bloom, moonlit clouds and a proper moon in the sky shader.
- **First-person rig** (scripts/player/fp_arms.gd, iew_model.gd): modelled longsword (diamond-section blade, bronze guard, wrapped grip, pommel), gloved hands with fingers, leather bracers, belt lantern; idle breathing, walk bob, lowered sprint pose, look sway, landing dip and a wind-up/slash/recover attack.
- Texture credits: ssets/textures/CREDITS.txt.

## Graphics pass 2: castle interior and renderer audit (2026-10-11)

**Renderer decision: stay on Compatibility.** Measured on this laptop (i5-1235U, Iris Xe,
1920 x 1080, same views, uncapped): Compatibility about 14-17 ms, Mobile 25.6 ms (forest
views 30-39 ms), Forward+ 23.9 ms before enabling any of its extra effects, plus several
minutes of first-run shader compilation. The features that would justify Forward+ (SSAO,
SSIL, SDFGI, volumetric fog) would cost more on top. Baked lightmaps are not an option
either: the world is generated at runtime.

**Lakeside Castle keep** (`scripts/world/sites.gd`). Layout, gameplay paths, node names and
interactions are kept; additions are listed here.
- Dressed limestone walls with flagstone floors (`castle_ashlar.tres`); the curtain walls
  keep their weathered slate, and the battlements are now textured.
- Furniture and fittings use `castle_props.gdshader`: the vertex-colour alpha picks wood,
  dark planks, linen, iron, dressed stone or rubble (`Sites.SURF_*`), so each room stays one
  draw call. Castle meshes are split per room (`ZoneKits`), because Compatibility lights
  each mesh with at most 8 lights.
- Great hall: ceiling beams and girders, trestle feast table, a hearth, banners, shields and
  spears, weapon racks, chests, timber door leaves and tympana. The kitchen, library and
  armory have new dressing, a hearth, a reading desk and torches.
- **Commander's quarters** (first floor, north-west room): four-poster bed, desk under the
  west window, wardrobe, armour stand, fireplace, rug, plank floor, lowered timber
  ceiling. The north window is now a door onto a **balcony** that overlooks the lake
  (corbelled slab with parapets, collision included). The screenshot views are
  `castle_balcony` and `castle_balcony_out`.
- Lighting: wall sconces and chained lanterns replace the floating lamp blobs, with
  gentle flicker. The 20 `CastleLamp_NN` lights keep their names and order; named lights
  were added for rooms that had none.
- `Ambience` now has interior moods (`Sites.interior_zones`): inside the keep the ambient
  turns warm and the ground mist is removed; the crypt gets a cold, dim haze and reverb.

**New paths and technical fixes**
- The first floor (barracks, war room, crest-locked map room) had no stair. A two-flight
  stair hall in the south-east room now links it to the great hall, through new doors in
  the x = 17 wall. New doors also link the barracks to the commander's quarters and the
  kitchen to the library. One colonnade pillar inside that closed room was removed.
- The crypt lies below the lake's water level, so the player was treated as swimming
  there, and the water plane's underside hid the crypt ceilings. Water now only counts
  where the terrain is below the water line (`PlayerController.terrain_height_query`), and
  the water plane is hidden while you're in the crypt.
- A painting and the "THE LAKE REMEMBERS" plaque were buried inside the south wall; they
  now face the hall. Plaques are single-sided, so text no longer shows mirrored.
- Stone shader (`stone_tri.gdshader`, used by every ruin, bridge, rock and the cave):
  optional large-scale tonal variation and a second texture scale hide tiling. The new
  uniforms default to off, and the existing materials opt in.

Tests: two new traversal checks (great hall to balcony on foot; the crypt is dry). Three
failures predate this pass and also fail on the untouched backup: the trails *Stone Bridge
to Castle* and *East Lake Shore*, and *lakeside castle courtyard*. All three run into the
redesigned castle's curtain wall or keep.

## Story, village and riverbank update (2026-10-11)

**Story sequences** (`scripts/story/`, HUD dialogue panel and objective line). Talk with
**E**; **E** also skips to the next line. Dialogue pauses movement and turns the view
toward the speaker. Story characters (`StoryNPC` with `CivilianRig`) are never
registered with Combat or GameState, so they are not targets and carry no identity.
- *The missing child*: Maren waits by the well in **Ashford**. Three clues (basket,
  dropped flowers, a shoe) lead west to the lake shore, where Tam is picking white
  flowers. He walks home, and Maren closes the quest.
- *Night before war*: study the battle maps on the desk in the commander's bedroom,
  climb to the keep roof, and find Princess Reve at the north-west parapet looking at
  the moon. She notices the commander arriving, turns toward him, and they talk quietly
  about the battle; her expression softens near the end, and she looks back at the sky
  when the talk is over. She does not appear before this sequence. The balcony stays,
  but it is no longer a story location.

**Castle**
- The bedroom is now a soldier's room: plain oak bed with wool blankets, campaign desk
  with a marked map, washstand, wardrobe, armour stand with breastplate and sword, weapon
  rack, slate-blue company pennant, and moonlight from the west window. The four-poster,
  crimson drapes and gold trim are gone.
- **Roof access:** the old 50° roof stair could not be climbed, so I removed it and closed
  its opening. The stair hall continues up two more flights (about 38°) to a parapeted
  stairwell on the roof. The roof walk has crenellations, and the four keep turrets now
  rise above it with round slate roofs.
- Torches flank the keep door, braziers light the courtyard, and some keep windows glow
  from outside only.

**Ashford** (`scripts/world/village_builder.gd`, on the old East Meadow, linked to the
east lake shore by *Ashford Lane*): tavern (jettied upper floor, sign, benches, lit
windows), bakery (bread oven, baskets, sacks), granary on staddle stones, smithy (forge
lean-to, anvil, quench tub), general goods (striped awning, produce stall), joinery
(timber stack, sawhorse, ladder), and four cottages with gardens and laundry. There
are also a well, lantern posts and dry-stone walls. Every building is exterior-only:
doors closed, windows shuttered or opaque, no interior, no prompts, and one solid
collision box per building that reaches above the roof ridge. Textures: Poly Haven CC0
`reed_roof_04` (thatch) and `white_rough_plaster`.

**Riverbanks and lake shores** (`Vegetation._scatter_riverbank`): rushes at the
waterline; drifts of white, blue, yellow, purple-spike and red flowers, one species
leading each patch; moss, pebbles and fallen branches. A low-frequency noise keeps some
banks bare and others lush. Everything is drawn with MultiMeshes in small fade-in
chunks.

**World**: stone gets a subtle warm/cool hue drift (`macro_hue`); the mountain rim is
less spiky. The combat-test arena and character portraits moved from the East Meadow
(now Ashford) to a new *North Meadow* clearing.

**Measured cost** (interleaved runs against the pre-update backup, ten representative
views at 1080p): 16.3 ms before, 16.6–16.7 ms after, so about 0.4 ms. New lights: 4 lantern
posts, 3 shop lights, 2 door torches and 1 roof torch. None of them casts shadows.

Profiling switches for the screenshot tour: --clean (no overlay), --no-shadows, --hide=<multimesh prefix>, --shadow-dist=N, --lod=N, --vsync, --with-bots.

## The commander: realistic main character (2026-10-12)

The local player is now the commander, a realistic skinned 3D character, in place of the
low-poly explorer body. Bots and other avatars keep the explorer. **V** toggles a
third-person camera so you can see him in play; first person is still the default.

**What he is:** a 1.85 m, athletic man of about 30, built on a MakeHuman body.
- Face and skin: warm tanned skin with real pore detail, short dark stubble, dark-brown
  eyes, and a healed sword scar running diagonally across his **left** cheek.
- Hair: medium, untidy dark-brown hair as game hair cards.
- Outfit: quilted navy gambeson, a studded dark leather brigandine with tassets and a navy
  tabard, a forged dark-steel breastplate, riveted pauldrons, couters, vambraces,
  gauntlets and knee cops. Leather belts, pouches, a dagger and a horn lantern hang at
  the hips, with knee boots below.
- Cloak and sword: a deep-blue cloak with the kingdom's griffin embroidered on the back
  and a hood lying as a cowl, plus a longsword in a scabbard on his left hip.
- Size: about 80k triangles, 99 bones, and 52 ARKit face blend shapes for blinks,
  expressions and talking.

**How it is built:** a re-runnable Blender pipeline in `Art/commander/pipeline`:

| Script | Builds |
|---|---|
| `01_body` | Body, skeleton and face shapes |
| `02_skin` | Tan, stubble, scar, eyes and brows |
| `03_hair` | Hair cards |
| `04_outfit` | Clothing, armour, cloak drape, weapons and rig weights |
| `05_bake` | 2K PBR atlases |
| `06_anim` | Retargets the CC0 Quaternius animation library and builds the custom clips |
| `07_export` | `assets/characters/commander/commander.glb` and `commander_anim.json` |

Sources and licences are in `assets/characters/commander/CREDITS.txt`. The griffin emblem
is CC BY 3.0 and needs a credit line in the game.

**In the game:** `scripts/characters/commander_rig.gd` keeps the same API as the other
rigs (`play`, `hold`, `release`), so combat, abilities and the monster transformation
work unchanged.
- Locomotion: an `AnimationTree` blends idle, walk, jog and run, with the playback rate
  matched to the ground speed. It also handles crouch, swimming, jumping and falling.
  Short drops land normally and long falls end in a hard, braced landing; there are no
  flips.
- Sword attacks: alternating light cuts with a heavier third cut.
- Other combat clips: a dodge roll, block (Ward), hit reactions, a knockback stagger, and
  death on defeat.
- Sword handling: the sword is drawn from the hip with a real draw animation. It is drawn
  automatically when a revealed monster is within 20 m or when he attacks, and sheathed
  after about 9 quiet seconds.
- Face: he blinks, and his expression follows the situation. Variants are determined,
  angry, hurt, tired, worried and a slight smirk; he moves his jaw while speaking.
- Cloak: it swings on spring bones that collide with the legs and body.
- Story beats: he leans over the battle maps in his quarters and looks up at the moon
  on the roof. In dialogue he turns his head toward the speaker (Reve, Maren, Tam),
  and his lines carry expressions.

Materials are tuned for the Compatibility renderer in `commander_materials.gd`. Visual
check: `godot --path . res://tests/commander_tour.tscn -- --out=<dir>`, which captures
portraits, face close-ups and third-person gameplay shots with timings.

### Princess Reve

`assets/characters/reve/reve.glb` is a realistic skinned model built from the owner's
reference photograph by the re-runnable Blender pipeline in `Art/reve/pipeline`
(01_body -> 02_skin -> 03_hair -> 04_outfit -> 05_materials -> 06_anim -> 07_export).
It uses the same MPFB game-engine skeleton and Quaternius clip library as the commander.
- Look: long dark-brown hair with a full straight fringe (hair cards), eyeliner and a
  muted red lip; a black strapless floor-length dress with a pleated skirt; a wide
  leather corset belt with metal eyelets and front lacing; a fine gold necklace with
  a pendant; a small black shoulder bag. The model is about 78k triangles.
- `ReveRig` (`scripts/characters/reve_rig.gd`) drives her through the CharacterRig
  API. The `mood` property selects a slow-blending pose (idle, moon gaze, listen,
  concern, a restrained talking idle, or a rail lean), and the walk is blended in by
  speed. She takes a small step when turning and has nod and head-shake gestures.
  ARKit expressions cover neutral, listening, soft smile, smile, concern, sad, resolve
  and wistful; she also blinks, makes small eye movements, has eyes that follow the
  look target, and moves her jaw while speaking. Her hair (9 chains) and skirt
  (12 chains) are on spring bones with body and leg colliders.
- `StoryNPC.setup("reve", ...)` creates her. In dialogue, each of her lines can carry
  an expression as the third element, and she listens while the commander speaks.
- Materials are tuned in `reve_materials.gd`. Visual check:
  `godot --path . res://tests/reve_tour.tscn -- --out=<dir>`.

**Riding:** there is no horse or mount system in the game yet. Riding idle, walk, trot
and gallop clips are included and ready for one; mount and dismount clips are not made yet.

## Kingdom layout: walls, town, cemetery and mission spaces (2026-10-16)

The world is now one walled kingdom. Everything is data in the `kingdom` block of
`data/world_layout.json`, planned by `scripts/world/kingdom_plan.gd` (pure data, so
tools and tests can inspect it) and built by `scripts/world/kingdom_builder.gd`.
Backup of the project before this change: `D:\WildFall\Backups\KingdomLayout_PreChange_2026-10-16`.

```
                    N   mountains + waterfall (kept)
        wall end ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ wall end
        |   Old Citadel = training ground     Northmere      |
        |   (parade ground east of it)        Sentinel Crag  |
  GREAT |   Gate Field (100)      Elder Tree     Moonmere   Ashford
  GATE =|   ring of houses        = cemetery      Lake      Castle Square (40)
 (west) |                                                   LAKESIDE CASTLE
        |   Watcher's Hill            Stone Bridge          castle town (south)
        |______________________ water gate ________________|
                    S   curtain wall on the east, south and west
```

**Boundary.** The ring of edge mountains is gone on the east, south and west. A
curtain wall (about 1.6 km, 11 m high, 4.2 m thick, 30 round towers, merlons
toward the outside, a parapet on the town side) runs from the northern mountain
foot round to the other side; the northern quarter, where the waterfall rises,
keeps its mountains. Both wall ends sink into the mountain slopes, and an
invisible barrier continues from each end to the map edge. The wall walk cannot
be reached: the wall's collision rises 30 m above it. Where the Silverrun leaves
the kingdom it passes under a grated water gate. Outside the wall the land is
open, wooded hills, and a low-poly countryside mesh continues beyond the
terrain edge (mountains behind the northern peaks). Terrain: `mountain_sector`,
`flat_zones` (flattens the town and the gate field) and `settled_zones` (fewer
trees in inhabited ground) in the layout; `TerrainData.in_playable()` now means
"inside the wall".

**The great gate** (west wall, facing the Gate Field): an archway in a deep
gate block between two 23 m towers with slate cones and maroon banners, closed
oak leaves, a lowered portcullis and braziers. It is permanently sealed: a solid
collision block fills the whole gatehouse, and there is nothing to interact
with nearby. The King's Way runs from the gate to the Stone Bridge and on, as
Castle Road, to the castle.

**Town.** Houses are the Ashford house builder, built once per archetype
(10 types) and drawn as shared MultiMeshes with per-house tints; each house is
one solid collision box (exterior only, like Ashford). The planner lines streets
with houses (doors facing the street) and rejects any footprint that is near
the wall, inside a landmark zone or mission space, on a road or trail, on wet or
steep ground, overlapping another building, or with a blocked door apron. With
the default seed it places 82 houses and 22 market stalls:
- *Castle Square* at the castle's north wall (paved, castle level), with stalls
  along the castle wall and the square's north edge, houses on its east side
  and Ashford above it.
- *South town* below the castle: South Street, Market Lane, Cooper's Lane,
  Tanner's Lane, Baker's Row and Cross Street, with a market along the castle's
  south wall, and an intervallum road (South Wall Road) inside the wall.
- *Wall Lane* between the castle and the east wall; the *Lakeside Quarter* on
  Castle Road and Mill Lane; the *Gate Field ring* in the west.
Main roads (King's Way, Castle Road, Castle Square Road, South Street, Cemetery
Road, Training Road) are 5-7 m wide; lanes are 3.6-4.8 m. The trails *Stone
Bridge to Castle* and *East Lake Shore*, which used to run into the castle's
walls, now end at the castle approach; three western trails were moved so they
no longer cut the Gate Field ring.

**Memorial cemetery** at the Elder Tree (the tree stays the centrepiece): 30
cross graves in seven clusters on two rows between the menhir ring and a
dry-stone fence (radius 29.6 m), six cross designs (Latin, Celtic ring,
bottony, wooden, stepped base, weathered and leaning), turf mounds, white /
muted red / yellow / purple flower clusters, two benches, lanterns at the main
gate and gateways wherever a path reaches the tree. The memorial stone at the
south gate reads *"In memory of those who gave their lives for this kingdom.
Their courage guards the peace we inherit."* No house stands within 20 m of the
fence. The lake shore is about 60 m east; the cemetery does not touch the river.

**Training ground.** The Old Citadel's geometry is unchanged. Its north drill
yard has pells and a weapon rack against the wall, an archery butt stands in the
east yard, and a parade ground was levelled outside the east gate. There is no
maroon-armoured soldier model yet, so four `SoldierPost_N` markers (group
`phase3_soldier_posts`) mark their corners for Phase 3.

**Reserved mission spaces** (no houses inside; markers under `Kingdom/MissionAreas`,
group `phase3_mission_areas`):

| | Space | Where | Size |
|---|---|---|---|
| A | Cave Outskirts (10 looters) | clearing at (-28, -140), in front of the cave's south mouth | radius 14 m, 616 m2 |
| B | Castle Square (40 combatants) | (232, 94), at the castle's north wall | 48 x 28 m, 1344 m2 |
| C | Great Gate Field (100 combatants) | (-232, 70), directly in front of the gate, ringed by 21 houses | radius 44 m, 6082 m2 |
| D | Night spy routes (20 spies) | 5 patrol routes, 4 spawn points each (group `phase3_spy_spawns`) | spread across the kingdom |

**Protected zones** (`landmark_zones` plus the older `residential_exclusions`):
the castle and its approach, the cemetery (+20 m), the Old Citadel and parade
ground, the Sunken Chapel ruins, the watchtower, both cave mouths, the river,
lake, waterfall, bridges and fords, every hamlet, the Ashford story shore and
the North Meadow arena.

**Checks.** `tests/test_kingdom.gd` (65 checks) covers the boundary share, wall
continuity (rays every 3 m at four heights, plus the water gate and the
mountain barriers), the sealed gate (walking, jumping and pressing interact),
escape attempts, house rules, mission space clearance and capacity, spy spawn
validity, the cemetery and training ground, trees, and walks along every main
road. Top-down plan: `godot --headless --path . -s res://tools/kingdom_map.gd --
--out=<png> [--region=x0,z0,x1,z1] [--ppm=N] [--verbose]`. Screenshot views:
`--only=kingdom_` in the screenshot tour.

## Campaign: the King, missions, the army (2026-10-16)

The commander returns to the castle in the evening; the **King** holds council from the
old lord's chair on the great hall's dais (`story_anchors["king_throne"]`, built in
`Sites`). Walk up to him and press **E**:

- **Evening (17:00-23:30):** *Receive the King's orders* - the briefing for the next mission
  plays once through the story dialogue UI, then the mission starts.
- **By day:** *Wait for the evening council* - the screen fades and the clock moves on to
  18:00. A new briefing needs a new evening (one mission per council).
- **After a mission:** *Report to the King* - the mission completes and recruits join.
- Never during a fight (he asks you to finish it first); walking away does not restart anything.

**Missions** (all data in `data/campaign.json`: counts, layouts, waves, text):

| # | Mission | Where | Enemy | Completes when |
|---|---|---|---|---|
| 1 | The Mysterious Scroll | Cave Outskirts | 10 looters (future) | **Reserved and disabled.** Its future objectives are registered; the cave, scroll and child content are untouched. Set `"enabled": true` only once the encounter exists. |
| 2 | Shadows on the Roads | Spy routes across the kingdom | 20 spies, each on its own patrol point | 10 are killed **and** the other 10 have retreated to their escape points and been removed out of the player's sight |
| 3 | Steel in the Square | Castle Square | 20 in four squads | all 20 fall |
| 4 | Before the Sealed Gate | Great Gate Field | 50 in five groups that advance one after another | all 50 fall |
| 5 | The Gate Holds | Great Gate Field | 100 in three waves, at most 40 alive at once; their captain comes with the last wave | all 100 fall; the gate stays sealed |

Mission states (validated in `CampaignState.TRANSITIONS`): awaiting briefing, briefing
available, briefing, mission active, encounter active, objective completed, return to castle,
mission complete, mission failed, retry available. The mission panel (top left) shows the
mission name, state, objective, progress (e.g. `7 / 10`), the current phase (wave, retreat)
and the destination with its distance and bearing.

**Army.** The campaign starts with 4 soldiers (maroon tabards, steel helms, capes, one sword
each) at the Old Citadel training posts. **T** (rebindable: *Call / dismiss your army*) or the
army button above the health bar toggles **Following** / **Holding position**; far away they
report **Regrouping** and march back (straight across open ground, along roads and the
commander's own footsteps where walls are in the way). They wait outside the keep, crypt
and cave. A fight near them switches them to combat (spreading over targets, helping
hurt friends, falling back when badly hurt) and they fall back in afterwards. When the
commander mounts, soldiers walk to the company's free horses (4, `army.horses`) and climb
up; the rest keep marching on foot. Each completed mission adds 10 recruits (mission
`reward_soldiers`; 0 for the climax): with Mission 1 reserved that is 4 -> 14 -> 24 -> 34
after missions 2-4; with it enabled, 4 -> 14 -> 24 -> 34 -> 44. The dead are never respawned.

**Failure, Retry and Quit.** If the commander dies during an encounter the battle pauses and
the failed screen offers **Retry** and **Quit**. The *encounter checkpoint* is taken the moment
the encounter starts: the roster (who lives, at what health).
- **Retry** restores that roster exactly, respawns the same enemy force from its fixed
  layout, resets the kill count, and starts again (no reward). Repeat as often as needed.
- **Quit** returns to the castle courtyard. Nothing is awarded; the survivors keep their
  state (those who fell in the attempt stay fallen); the same encounter waits at its area
  (spies: once you leave the castle again).

**Save.** `user://campaign_save.json` (versioned JSON: mission states, completed missions,
roster, checkpoint). It is written at stable points (briefing, encounter start, completion,
retry, quit). A save made mid-encounter resumes as *retry available*. *Esc -> Game -> Restart
the campaign* erases progress; `-- --new-campaign` ignores the save and `-- --no-campaign-save`
neither reads nor writes it.

Code: `scripts/campaign/` (`campaign_state.gd` model, `campaign_director.gd` the only mission
manager, `army.gd`, `encounter.gd`, `route_graph.gd`), `scripts/ai/soldier_brain.gd`,
`scripts/characters/soldier_rig.gd`, `scripts/characters/king_rig.gd`,
`scripts/ui/campaign_hud.gd`. Combat gained teams (no friendly fire between soldiers of one
side) and respawn modes (soldiers never respawn; the commander's respawn is held during an
encounter). Tests: `tests/test_campaign.gd`. Visual check: `res://tests/campaign_tour.tscn --
--out=<dir> [--only=king,brief,muster,follow,mount,spies,square,gate,failed,gait,cave]`.
Frame timing of the big battles: `res://tests/campaign_perf.tscn -- [--only=m4|m5|square]`.

**Performance with the earlier low-poly soldiers (i5-1235U / Iris Xe, Compatibility, windowed, vsync off, 34 allies):**
Castle Square (20 enemies) ~42 fps, Great Gate Field (50 enemies) ~39 fps, the final battle
(40 of 100 alive at a time) ~41 fps; about 800-1,100 draw calls. Measures that got there:
bots skip the follow-camera sweeps, soldiers move at half / third physics rate beyond 30 / 80 m
from the camera and pose at ~8 Hz beyond 60 m, soldier limbs cast no shadows (torso and hips
do), soldiers are culled beyond 170 m, the company's spare horses sleep (no animation or
physics) while idle and far away, and the soldier AI uses a per-frame spatial grid. If a
battle is still too heavy, lower `max_active` (Mission 5) or the army size first.

### Soldier and spy variants of the commander's model (2026-10-16)

Soldiers are built from the commander's own model (`SoldierRig` extends `CommanderRig`):
the same body, cloak and outfit meshes (shared, not copied), skeleton, clips, gait and
riding. Only per-instance overrides differ: `SoldierMaterials` recolours the cloth layers
to deep maroon (kingdom) or near-black with a blackened griffin (enemy) on duplicated
materials, and `GreatHelm` is a closed medieval great helm on the head bone, sized from the
model's measured head and hair (every head vertex is tested to lie inside it). Hair and
eyes are not drawn under it; the head is drawn from one shared skin-only copy. One sword,
one scabbard; kingdom line soldiers carry the commander's belt lantern. The commander is
unchanged (his files are byte-identical). Visual check: `res://tests/variant_tour.tscn --
--out=<dir> [--only=lineup,helm,motion,ride,death]`; tests: `tests/test_soldier_variants.gd`.

Cost: on the i5-1235U / Iris Xe laptop the 50-enemy battle (85 soldiers) runs at about half
the frame rate of the previous low-poly soldiers (interleaved A/B: ~12-14 fps vs ~20-28 fps
in the same throttled session), mostly from 4x the triangles and skinning ~900 skinned parts.

### Group combat: factions, approach slots, assist (Phase 4, 2026-10-19)

Allied maroon soldiers, the commander and the enemy kingdom fight at once on one set of rules.

- **Factions.** `Factions` (`scripts/combat/factions.gd`) is the one place that answers "may A
  target B": `kingdom` = the commander + every maroon soldier, `enemy` = the black soldiers.
  No script compares team names itself. Combat still decides who can be hurt, so a blow never
  lands on a friend (the test counts friendly blows across ~100-soldier skirmishes: 0).
- **Battlefield** (`scripts/ai/battlefield.gd`) is the lightweight manager the brains share:
  a per-frame spatial grid (4 m cells; queries touch only nearby cells, nobody scans everybody),
  approach **slots**, target scoring, assist, and path helpers.
- **Approach slots.** A soldier does not run at its target's position: it takes one of
  `slot_count` (10) positions at `slot_radius` (1.6 m, kept inside the sword's `hit_range`),
  nearest the side it comes from. At most `max_per_target` (5) blades per target (`max_per_leader`
  = 3 on the commander), at most `max_per_sector` (2) from any 90 degree direction, and
  `open_slots` (2) always stay free. A slot is skipped when it is in water, has no ground at the
  target's height, or a wall / house stands between it and the target (so a target against a
  building simply has fewer slots). A soldier whose target is ringed waits at `wait_radius`
  (4.6 m) for a slot, switches to another fight after ~2.5 s if one exists, otherwise keeps
  waiting. Personal space between friends is `personal_space` (1.3 m, 0.85 m inside a slot).
- **Target choice** (`Battlefield.pick_target`): distance; faction; who is hurting me or a
  friend near me; whether the target's own target is an outnumbered friend; how many have
  already chosen it (slots held *and* soldiers on the way); reachability (clear line, else the
  route network); a bonus for the fight in progress (no flip-flopping: a soldier in melee does
  not re-pick); a stable per-pair taste so a crowd does not all prefer the same face; and, when
  the commander is below `leader_danger` health, his attackers first (slots still apply).
  Enemies divide between the commander and the army by the same score; no special pull to him.
- **Assist** (`find_assist`): when a soldier's target falls, a nearby death/retreat is seen, or
  nothing is left in range, it looks `assist_radius` (45 m) for a friend still fighting, prefers
  the one who is outnumbered or hurt, whose enemy is not already ringed, and whom few others
  are already helping. Runners (retreating soldiers) are never chased.
- **AI rate.** Think interval 0.2 s next to a blade, 0.3 s otherwise in combat, 0.4 / 0.7 / 1.0 s
  for idle soldiers by camera distance; blows run on their own 0.12 s clock so hits stay
  reliable however seldom the brain thinks.
- **Formation.** Followers keep a loose, uneven line (stable per-slot wobble) behind the
  commander; where walls close in on him (roads, gates, bridges) the company becomes a two-file
  column; a slot behind a wall is pulled back in front of it; everything else from the Army
  (regroup, crumbs, route network, mounted soldiers only on free horses) is unchanged.
- **Spawns.** Battle squads are laid out with `spawn_spacing` / `spawn_jitter` and never closer
  than `min_spawn_gap`; each squad (and each wave arrival) marches on its own `lane_distance`
  point in front of the defenders, on its own bearing, instead of on the commander's position.
- **Data.** `data/campaign.json` -> `battlefield` block (all tunables above). Tests:
  `tests/test_battlefield.gd` (rules, slots, 5 / 20 / 40 / 100-combatant skirmishes with
  spread, cap, stale-target, split-attention and friendly-fire checks, assist, per-call costs).
  The spy mission's 20 spies / 10 kills / retreat / safe removal and the retry checkpoint are
  Encounter / CampaignDirector behaviour covered by `tests/test_campaign.gd`.

### Movement, swords and camera

- **Third person only.** The first-person / eye view, its V key and the first-person hands
  were removed (the hidden `ViewModel` node now only owns the belt-lantern light). The
  follow camera skips its terrain/water floor clamps when the commander is underground (the
  heightfield there is the roof) and over terrain holes, so it follows him into the cave and
  the crypt; under low ceilings it eases to a flatter angle when that leaves more room.
- **Gait.** Walk, jog and run share one normalised cycle (their foot contacts line up), so
  they blend without the legs fighting; the stride follows a natural cadence for the speed
  and the cycle rate is speed / stride, so the planted foot does not slide. Idle fades in
  below walking pace; a slight chest-up carriage while moving.
- **Two swords, always.** The commander draws and sheathes both swords together (X), attacks
  draw both; the left sword sits in the mirror image of the right hand's grip; trails follow
  both blades during cuts. Soldiers carry exactly one.
- **Dual-sword sprint.** Sprinting with both swords drawn: the torso leans to about 34 degrees,
  the head levels the gaze, both arms extend back with nearly straight elbows and both
  blades trail behind, pointing back along the run (`CommanderSecondary`, solved per bone
  after the run clip; the legs stay on the clip).

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
- **power**: base score; prey reward and penalty; slayer and assist rewards; monster penalty; escape reward; every award applied exactly once, even when events are replayed; defeat â†’ respawning â†’ valid state for both humans and monsters; respawn protection and camera; invalid state transitions refused.
- **campaign**: the mission state machine and roster rules, the King and the evening council, the briefing shown once, the 20 spies and their retreat, reporting and growth, follow / hold / regroup, mounting, Mission 3 retry and quit, Mission 4's 50, Mission 5's waves and cap, the save file, and the follow camera in the cave and crypt.
- **soak**: one hunter and five wanderers fighting freely for three simulated minutes, checking state invariants on every player every second.

Visual and performance check (windowed; saves PNGs and prints frame times):
`Godot_v4.7.2-stable_win64_console.exe --path . res://tests/screenshot_tour.tscn -- --out=C:/temp/shots [--vsync] [--only=name]`

## The world

About 600 Ã— 600 m of playable ground, enclosed by the kingdom wall on the east, south and west and by mountains to the north (see *Kingdom layout* above; terrain extends to
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

| | 1280 Ã— 720 | 1920 Ã— 1080 |
|---|---|---|
| Uncapped average frame | 7.4 ms (~134 fps) | 10.9 ms (~92 fps) |
| VSync on | 120 fps on gameplay views (p95 about 10 ms) | 60 fps (p95 about 23 ms, occasional missed frames) |

Draw calls stay around 250â€“500. Phase 2 re-measured with four bots plus the beast on screen:
about 7.3 ms (~138 fps) at 720p, the same as before.

## Known limitations

- The world is generated at runtime, so `world.tscn` looks empty in the editor. Ruin pieces preview individually, and the screenshot tour, F6 and noclip are the ways to inspect the map.
- Tree and rock collision uses server-side bodies, so *Debug â†’ Visible Collision Shapes* does not draw it.
- Water is one flat plane at height 0. Rivers do not flow downhill, and the waterfall and river exit are visual set pieces.
- The terrain is a heightfield. The cave is built from blocky box geometry with rock dressing.
- Some mountain gullies past ~300 m can be climbed partway. The terrain edge is a fallback, and falling off the world respawns you.
- Sounds are synthesized placeholders. Faint shadow acne remains on some flat stone tops.
- Per-instance tints use MultiMesh instance colours, because custom data did not reach shaders in the Compatibility renderer on this GPU.
- No navigation mesh yet. The traversal tests use a simple steering walker. Future AI will need a navmesh.

Phase 2:

- No networking. Opponents are bots. `Combat` and `GameState` are written as the authority, but nothing is replicated yet, and "private" messages are local signals that Phase 3 must turn into per-peer RPCs.
- The characters are procedural placeholders: rigid low-poly parts animated in code, not skinned meshes. They follow the reference sheets' silhouettes and palettes, not their detail. Swap in real models through `AvatarVisual.create_rig()`.
- Balance values are prototypes. In the open forest, the flee bot survives far longer than a player standing still (about 27â€“30 s versus 5â€“6 s) but does not reliably shake the hunter. Escaping cleanly depends on breaking line of sight, which the tests show separately.
- The human's only attack is a light sword strike; a group of brave bots can wear a beast down. The bow from the reference sheet isn't implemented.
- A defeated beast keeps its powers (it respawns hidden). The scroll never returns to the world.
- The first-person hands and claws aren't on a separate render pass, so they can clip into walls when you stand very close.
- The in-world beast is about 3 m tall but its collision capsule is 2.5 m. Monster footsteps are the human sounds pitched down.


## Royal castle and playable morning opening (2026-11-02)

New campaigns begin in the commander's preserved bedroom. Open the chamber door, follow the chiefs' corridor, and take the existing stairs to the council hall or terrace. The hall has a short skippable reveal; the entrance leads to a soldier summons and gate audience before the existing evening council. Existing saves resume their campaign; **Restart campaign** starts the new opening. The keep now faces the outer gate, while the prison and hoist remain fixed.

See [the implementation and validation report](CASTLE_REDESIGN.md).
