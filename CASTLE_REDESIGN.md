# Royal castle redesign - 2 November 2026

The existing runtime castle is enhanced in place. No replacement world or imported castle was introduced.

1. **Existing structure and alignment.** The keep, its bedroom, stairs, rooftop, furniture, lights, collision, and story anchors rotate together about world XZ **(220, 142)**, through **-97.943 degrees** from its original +Z entrance direction. Its entrance axis points to the unchanged kingdom gate at **(-296, 70)**. The castle ward's west opening now intersects that axis at **(172, 135.302)**. Its towers, raised portcullis, bridge, broad approach stair, and paved connection were adapted. The kingdom outer wall was not altered. Castle Square Road crosses the flared stair and retains its existing route and terrain.

2. **Prison preservation.** `PreservedUndercroft` is a sibling of `RoyalKeep`, with an identity world transform. The original prison rooms, cells, tunnels, floors, shaft, hoist, and controls retain their coordinates. The hoist remains at XZ **(207, 165)** at the original terrain height. A comparison against the backup confirms no geometry statements changed inside the prison builder: only an obsolete key-search inscription and its comment changed. Physics checks verify the original floor elevations and dry traversal. End-to-end testing exposed an existing gap between the cage and landings: two small wooden boarding sills now bridge it. No original shaft, cage, room, or floor was moved. Boarding, lever focus, descent, walking into the prison, reboarding, ascent, and surface exit all pass.

3. **Exterior and interior.** Reused masonry, towers, roofs, battlements, arches, timber doors, furniture, stone textures, and room mesh batches. Warm pale stone, brown oak, muted red cloth, shallow quoin variations, a royal entrance insignia, transparent leaded windows, and reduced interior fog improve the morning appearance. The existing bedroom is furnished as before, with a working chamber door and a visible balcony latch. Four closed chiefs' doors and distinct banners dress the corridor; the former map-room lock is now an unprompted private door. The existing terrace and lower stairs are retained, with a wider junction sightline.

4. **Royal hall.** Removed the obstructing feast tables, benches, collision blocks, and transverse hall partition. Retained the central throne and dais, with six symmetrical individual chiefs' chairs, six aligned framed portrait placeholders, a clear red-carpet aisle, and a suspended sixteen-candle iron chandelier around the existing lamp. The King's existing seated rig remains in use; it can stand for the brief gate audience.

5. **Opening and story.** New campaigns begin in the preserved bedroom at 08:00. Opening the chamber door releases the balcony latch. Walking remains under player control through the corridor and both stairs. Entering the hall triggers a seven-second camera reveal of chairs, portraits, throne, and chandelier, then restores the previous camera and controls. Interact skips it; pause freezes it. Outside, one soldier delivers the requested summons line once. A short gate audience returns to the existing evening council progression. The night-before-war and village stories remain available. The opening-complete flag uses the existing campaign save; legacy saves resume their prior campaign. Use **Restart campaign** to see the new opening on an existing save.

6. **Removed key objective.** Removed the castle crest-key pickup, lock interaction, unlock handler, prompts, and search clues. The archive stays a decorative private chamber. The separate sealed crypt interaction, hoist, cave story scroll, and monster scroll are retained.

7. **Validation.** The actual Godot 4.7.2 game and Compatibility renderer were used, including real player-controller walking, real interaction focus, mounted-horse entry, camera return, and save/load. The existing regression run recorded **355 passes** and one approach-road failure. That obstruction was corrected and the exact original densified road route passed a focused recheck. The remaining suites passed: spawns, empire roads, kingdom geometry/landmarks, player controller, scroll, village/rooftop stories, garrison, and the full campaign through the final battle, retry/quit, rewards, persistence, and underground camera. The focused checks recorded **51 passes, zero failures** across the opening/architecture (36), original approach road (1), pause/restart/save lifecycle (7), and prison round trip (7), in separate final runs. Rendering measurements are recorded below. All original `data/` and `scenes/` files compare byte-for-byte with the backup; implementation changes are in scripts and castle materials.

8. **Asset and validation limits.** Chiefs' artwork uses the existing procedural medieval portrait placeholders, not finished individual oil portraits. No waking animation was available, so the commander starts standing beside his bed. Existing character models and the project's low-poly architectural style are retained. Performance captures are static castle views, not a whole-game benchmark. The full historical traversal suite was not run; its castle coordinates were updated, and the new focused route suite covers the changed route.

Backup: `../Backups/RoyalCastle_PreChange_2026-11-02/` (original scripts, scenes, data, materials, tests, and project settings).

Screenshots: `../Screenshots/RoyalCastle_2026-11-02/`.

Run the focused checks:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path D:\WildFall\Game res://tests/test_runner.tscn -- --only=test_castle
```

Run the visual tour:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path D:\WildFall\Game --windowed --resolution 1920x1080 res://tests/castle_tour.tscn
```

Final validation artifacts:

- `../Screenshots/castle_final_checks.log`: 44 passing opening, architecture, approach, and lifecycle checks.
- `../Screenshots/castle_prison_final.log`: seven passing prison round-trip checks after the boarding repair.
- `../Screenshots/castle_regression.log`: 355 passing existing checks; the sole road obstruction was subsequently fixed and rechecked in `castle_approach_recheck.log` and `castle_final_checks.log`.
- `../Screenshots/castle_visual_final.log`: final OpenGL 3.3 Compatibility capture on Intel Iris Xe, 1920 x 1080. No concurrent test process ran during this capture. Each view warmed up for 60 frames, then sampled 90 frame intervals. These are short, VSync-influenced frame samples, not sustained gameplay or battle FPS.

| View | Median frame time | 95th percentile | Draw calls |
| --- | ---: | ---: | ---: |
| Hall | 17.43 ms | 27.94 ms | 550 |
| Council seating | 17.60 ms | 27.70 ms | 489 |
| Corridor | 21.38 ms | 26.23 ms | 684 |
| Bedroom | 17.20 ms | 26.97 ms | 366 |
| Stair junction | 22.75 ms | 26.41 ms | 759 |
| Terrace | 21.10 ms | 27.12 ms | 620 |
| Entrance | 20.65 ms | 26.85 ms | 736 |
| Approach | 21.34 ms | 27.68 ms | 856 |

The median samples correspond to approximately 44-58 FPS at 1080p. A locked 60 FPS at this resolution is not established. All eight final screenshots were captured; the hall, corridor, bedroom, stair junction, entrance, and approach were visually inspected.
