class_name Layers
## Physics layer bits. Names match [layer_names] in project.godot.

const WORLD := 1 << 0          ## Terrain, trunks, rocks, ruins: blocks movement and sight.
const PLAYER := 1 << 1
const INTERACTABLE := 1 << 2
const FOLIAGE_SIGHT := 1 << 3  ## Bushes and canopy: blocks sight only, never movement.
const ZONES := 1 << 4          ## Trigger volumes (cave darkness etc.).
const CREATURE := 1 << 5       ## Horses: block movement, never sight or interaction rays.

const SIGHT_BLOCKERS := WORLD | FOLIAGE_SIGHT
