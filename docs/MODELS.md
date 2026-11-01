# Giving characters 3D models and animations

Every character already has a look: a coloured block. This guide replaces the block with a real 3D model
and animations, one character at a time, without touching game code. Characters without a model keep
the block, so you can add art gradually.

## The quick way: one file per character

1. Build the character as a **Model** in Studio. It needs:
   - a root part (`HumanoidRootPart`, or set the Model's `PrimaryPart`);
   - to stand upright, with its **front facing -Z** (the normal Roblox forward);
   - for animation, parts joined with `Motor6D` joints (any Roblox rig works, including R15).
     A model with no joints still works: it is shown as a rigid statue and gets the simple fallback
     movements below.
2. Save it as `assets/models/<unit id>.rbxm`, for example `assets/models/noodle_nugget.rbxm`. Unit ids are
   in `src/shared/Data/Units.luau`. Right-click the Model in Studio, Save to File, choose `.rbxm`.
3. Sync with Rojo. The model appears in `ReplicatedStorage/UnitModels` and is used immediately.
4. Check it: with the game running, in the command bar:

   ```lua
   local P = require(game.ServerScriptService.Server.Combat.ModelPreview)
   P.show("noodle_nugget")   -- loops idle, walk, attack, cast, hit and death
   P.clear()
   ```

That is all a character needs. The game scales the model to a standard height (one board cell), puts its
feet on the ground, turns it to face the enemy, and removes its default scripts and collisions.

## Animations

Animations are Roblox animation asset ids (`rbxassetid://123456`). The states are:

| State | When it plays |
| --- | --- |
| `idle` | standing still (looped) |
| `walk` | moving between cells (looped) |
| `attack` | each auto attack |
| `cast` | casting an ability |
| `hit` | taking damage |
| `death` | when the unit dies; the unit is removed when it finishes |
| `victory` | reserved for the end of a fight |

- **Shared animations for every character:** put the ids in `defaults` in `src/shared/Data/Models.luau`.
  This is the easiest start: one set of animations on one rig shape, used by all of them.
- **A character's own animation:** add an entry in `Models.models` and list only the states that differ:

  ```lua
  { id = "noodle_nugget", animations = { attack = "rbxassetid://1234567" } },
  ```

  Missing states use the shared defaults.
- A state with no animation at all falls back to a simple move (a lunge, a hop, a white flash, a sink), so
  nothing is ever frozen.
- Animations must be owned by the account or group that owns the experience, or Roblox will not play them.
  A failed load prints a warning and that state uses its fallback.

## Other adjustments (only if needed)

Add or edit an entry in `Models.models` (`src/shared/Data/Models.luau`):

```lua
{ id = "noodle_nugget", scale = 1.3, facing = 180 },
```

| Field | What it does |
| --- | --- |
| `scale` | size multiplier on top of the standard height (default 1) |
| `facing` | degrees to turn the model if it was built facing another way (default 0) |
| `template` | use a Model with a different name in `UnitModels` |
| `assetId` | a Roblox asset id of a Model; it is loaded into `UnitModels` when the server starts if there is no file for it |
| `animations` | this model's animation ids |

**Sharing a model:** give a unit `modelId = "other_model"` in `src/shared/Data/Units.luau`.

**Models for things that are not units:** `monster` (PvE monsters), `token` (summoned tokens such as the
Training Pup) and `pet` (Pet Squad pets) are model ids too. Save `assets/models/monster.rbxm` and so on.

## Where models show up

- **The arena in the workspace** (`CombatPlayback`): units walk between cells, turn to face their target,
  play attack, cast and hit animations, and play their death animation before they are removed.
- **Shop, bench, board and the unit card:** a still 3D portrait replaces the coloured tile.
- **Not yet:** the combat screen the player normally watches is the 2D view (decision D-44), which does
  not show models. Switching combat to the 3D arena is a separate step.

## Under the hood

| Piece | File |
| --- | --- |
| Data: shared animations, per-model entries | `src/shared/Data/Models.luau` |
| Lookup and defaults | `src/shared/Util/ModelRegistry.luau` |
| Build the 3D look (real model or placeholder) | `src/shared/Visual/ModelFactory.luau` |
| Play animations, with fallbacks | `src/shared/Visual/UnitAnimator.luau` |
| Load asset-id models at server start | `src/server/Combat/ModelLoader.luau` |
| Check a model by eye | `src/server/Combat/ModelPreview.luau` |
| Drive the models during a fight | `src/server/Combat/CombatPlayback.luau` |
| 2D portraits | `src/client/UI/UnitPortrait.luau` |
