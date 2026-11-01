# Brainrot Battlers — Game Design Document (Claude-Readable)

Nov 1, 2026 · @Brian

## 1. How Claude must use this document

This document is the single source of truth for building the foundation of Brainrot Battlers (working title) in Roblox. Follow it literally; when it is silent, log an assumption instead of improvising.

### 1.1 Directive keywords

| Keyword | Meaning for Claude |
| --- | --- |
| MUST / MUST NOT | Non-negotiable. Violating it is a bug. |
| SHOULD | The default. Deviate only with a one-line reason in `docs/DECISIONS.md`. |
| MAY | Optional. Skip unless it is cheap and clearly useful. |
| `[CONFIG]` | A tunable number. It MUST live in a Config module and MUST NOT be hardcoded in logic. |
| `[EXAMPLE]` | Seed content. Implement it as written, and extend it later using the same schema. |
| Rule IDs (e.g. `ECON-03`) | Cite the ID in a code comment where the rule is implemented. |

### 1.2 Working protocol

1. Read the whole document before writing code. Then reply with a short plan: the modules you will create, in order, mapped to the phases in Section 14, plus any ambiguities you found.
2. Work one phase at a time. Do not start the next phase until the current phase's acceptance criteria pass and you have shown evidence (test output or a manual test checklist).
3. If the document is silent or contradicts itself, pick the simplest option that fits the pillars in Section 2. Record it in `docs/DECISIONS.md` (ID, decision, reason) and continue. Stop and ask only when the choice changes a data schema or cannot be undone cheaply.
4. MUST NOT add mechanics, content, or third-party dependencies that this document does not list. Put ideas in `docs/SUGGESTIONS.md` instead.
5. Every phase MUST end in a state that runs in Studio without errors.

### 1.3 Code standards

- Language is Luau. Every module MUST start with `--!strict` and use the shared types from `Shared/Types`.
- The server is authoritative (rule ARCH-01). Clients send intents only and never decide outcomes.
- Content is data-driven (ARCH-02). Units, traits, items and augments live in `Shared/Data`; numbers live in `Shared/Config`; behavior lives in `Server/Effects`.
- Combat is deterministic (CMB-01). Use one seeded `Random` per combat. MUST NOT use `math.random`, `tick()` or `os.clock()` inside simulation logic.
- Use current Roblox APIs (`task.wait`, `task.spawn`, `task.delay`). MUST NOT use `wait`, `spawn` or `delay`.
- Keep modules under about 400 lines with one responsibility each. Give every public function a one-line doc comment.
- Leave no dead code. A deferred item MUST be marked `-- TODO(phase N):`.
- Pure-logic modules (Economy, Shop, Pool, Merge, StatBlock, Damage, Pairing) MUST have unit tests under `tests/` using plain asserts or TestEZ.

### 1.4 Reply format after every phase

1. Summary in five lines or fewer.
2. Files created or changed.
3. How to test it (exact steps).
4. Rule IDs implemented.
5. Assumptions logged.
6. Proposed next phase.

### 1.5 Glossary

| Term | Definition |
| --- | --- |
| Unit | A character the player buys and fields. Has cost 1 to 5, a star level 1 to 3, and one to three traits. |
| Board / Bench | Board: the 7×4 grid of cells where units fight. Bench: 9 holding slots. |
| Stage / Round | A stage is a group of rounds. Round IDs read `stage-round`, e.g. `3-2`. |
| Prep / Combat | Prep: the timed phase where players shop and arrange. Combat: the automatic fight. |
| Component / Combined item | A basic stat item, and the unique item made by fusing two components. |
| Augment | A powerful one-per-offer perk chosen at set rounds. Rarity is Bronze, Silver or Gold. |
| Trait / Breakpoint | A synergy shared by units. A breakpoint is the unit count that unlocks the next tier. |
| AD / AP | Attack Damage (physical). Ability Power, where 100 AP means 100% ability damage. |
| Interest / Streak | Bonus gold from savings, and bonus gold from consecutive wins or losses. |

## 2. Game overview

Brainrot Battlers is an 8-player Roblox auto battler in the style of Teamfight Tactics: players buy meme-flavored units, build trait synergies, equip combined items, pick augments, and watch their team fight automatically until one player remains.

### 2.1 Pillars

When two designs conflict, the lower-numbered pillar wins.

1. **Readable chaos.** A new player MUST be able to see who is winning within a few seconds. Effects are loud but legible.
2. **Every game feels different.** Traits, items and augments are the variety engine. Each match SHOULD push the player toward a different build.
3. **Gold is the decision.** Gold is the only resource the player controls. Spending versus saving is the core tension.
4. **Short and decisive.** A match lasts about 25 to 30 minutes. Prep is fast, and combat never stalls.
5. **Phone-first.** Most Roblox players are on mobile. Every action MUST work with taps, not only drag and hover.

### 2.2 Audience and tone

- Target players are ages 9 to 17. Content MUST be age-appropriate: no gore, no real-world weapons, no mature jokes.
- Humor is absurd, fast, and meme-literate. Think exaggerated proportions, silly voices, and over-the-top ability names.
- All characters, names and catchphrases MUST be original. MUST NOT copy existing meme characters, creators, or branded properties. Use the genre's flavor (food-animal mashups, nonsense names, internet slang) without reusing anyone's IP.

### 2.3 Visual direction

- Chibi, high-contrast, saturated palettes. Big heads, small bodies, readable silhouettes at phone size.
- Each unit has a rarity color border: Common gray, Uncommon green, Rare blue, Epic purple, Legendary gold.
- Ability effects use one dominant color per unit so players can tell who cast what.
- Placeholder art is acceptable. Phase 1 to 6 MUST use colored blocky models with a text label, and art swaps in later by changing `modelId` in unit data.

### 2.4 Match shape

| Item | Value |
| --- | --- |
| Players per match | 8 at launch, 4 during development (LOBBY-01); empty seats are filled with bots `[CONFIG]` |
| Player health | 100 `[CONFIG]` |
| Target length | About 25 to 30 minutes, 28 to 34 rounds `[CONFIG]` |
| Win condition | Last player with health above 0. Placement is by elimination order. |
| Persistence | None in the foundation. No DataStores until a later phase. |

- **LOBBY-01.** Lobby size is `lobbySize` in `GameConfig`. It is 4 while building and 8 at launch `[CONFIG]`. Every system MUST read it, and no code may assume 8 players.
- **LOBBY-02.** The shared unit pool scales with lobby size: copies per unit = `ceil(copies × lobbySize / 8)`. A 4-player lobby has 11, 10, 9, 5 and 5 copies for costs 1 to 5.
- **LOBBY-03.** The carousel (4.8) offers exactly one item per living player.

### 2.5 Out of scope for the foundation

Claude MUST NOT build these yet: ranked ladder, cosmetics, shop monetization, Robux purchases, chat features, tutorials, spectating, and cross-server matchmaking.

## 3. Roblox architecture

The server owns every outcome; clients send intents and render what they are told. All content is data, and all behavior is an effect module that reacts to hooks.

### 3.1 Architecture rules

- **ARCH-01.** Server authority. Clients MUST NOT decide gold, units, items, damage, or results. For every intent the server checks phase, ownership, affordability, bounds and rate (max 20 intents per second per player), then replies with `{ok, reason}`.
- **ARCH-02.** Data-driven content. Units, traits, items and augments are tables in `Shared/Data`. Numbers are in `Shared/Config`. Adding content MUST NOT require editing core services.
- **ARCH-03.** Effects by hooks. Trait, item, augment and ability behavior lives in Effect modules that subscribe to hooks (3.4). Match and combat code MUST NOT contain `if traitId == ...` branches.
- **ARCH-04.** Pure simulation. `CombatSim`, `StatBlock`, `Damage`, `Targeting`, `Grid` and the economy services take plain tables and return plain tables. They MUST NOT touch Instances. A separate `CombatRunner` adapts sim output to models.
- **ARCH-05.** One `MatchService` per server owns the match state machine. Services receive their dependencies as arguments so tests can inject fakes.
- **ARCH-06.** No persistence in the foundation. MUST NOT use DataStores or MessagingService yet.
- **ARCH-07.** Replicate snapshots, not edits. The server sends each player one `StateUpdate` snapshot after any change, at most 10 times per second.

### 3.2 System overview

&#91;embedded content: system architecture · client, server, shared data\]

Every arrow from the client carries an intent that the Action Router validates. Everything the client shows comes from snapshots and combat events.

### 3.3 Project layout (Rojo)

Claude MUST create this layout with a `default.project.json` mapping `src/shared` to `ReplicatedStorage/Shared`, `src/server` to `ServerScriptService/Server`, and `src/client` to `StarterPlayer/StarterPlayerScripts/Client`.

```text
default.project.json
src/
  shared/
    Types.luau
    Config/   GameConfig, EconomyConfig, ShopConfig, CombatConfig, Assets
    Data/     Units, Traits, Items, Augments
    Util/     Signal, Rng, Grid
  server/
    Main.server.luau
    Match/    MatchService, RoundSchedule, Pairing, PveBoards
    Player/   PlayerState, ActionRouter
    Economy/  EconomyService, ShopService, UnitPool, MergeService, LevelService
    Items/    InventoryService, CarouselService
    Augments/ AugmentService
    Combat/   CombatSim, StatBlock, Damage, Targeting, Statuses, CombatRunner
    Effects/  EffectRunner, Traits/, Items/, Augments/, Abilities/
    Bots/     BotController
  client/
    Main.client.luau
    StateStore.luau
    UI/       components and panels
    View/     BoardView, CombatView
tests/
docs/         DECISIONS.md, SUGGESTIONS.md
```

### 3.4 Effect hooks

The `EffectRunner` attaches an Effect module when its source becomes active, calls its hooks, and detaches it when the source ends. Payloads are plain tables.

| Hook | Fires | Payload | Typical use |
| --- | --- | --- | --- |
| `OnPrepStart` | Start of Prep, after income | player | Tycoon gold-based setup |
| `OnIncomeCalc` | While income is computed | player, breakdown (mutable) | +1 gold effects, interest cap changes |
| `OnUnitBought` | After a purchase | player, unit | Augments reacting to buys |
| `OnItemCombined` | After a combine | player, item | Gold-Plated Gear |
| `OnRoundEnd` | After combat resolves | player, result | Noob growth |
| `OnCombatStart` | Sim begins | unit or team | Shields, charms, summons, stat buffs |
| `OnTick` | Every sim tick | unit, dt | Rot stacks, ramping attack speed |
| `OnAttack` | An auto attack fires | attacker, target | Every-3rd-attack items |
| `OnDamageDealt` | After damage resolves | source, target, amount, type | Omnivamp, lifesteal |
| `OnDamageTaken` | After damage resolves | target, source, amount, type | Thorns, mana gain |
| `OnCast` | An ability is cast | caster | Glitch recast, Gooey Heart |
| `OnKill` | A unit kills another | killer, victim | Speedrunner |
| `OnDeath` | A unit dies | victim, killer | Aura burst, Obby respawn |
| `OnCombatEnd` | Sim ends | result | Cleanup |

### 3.5 Networking

Intents use one `RemoteFunction` named `Action`, called as `Action:InvokeServer(name, args)`. It returns `{ ok: boolean, reason: string? }`.

| Remote | Direction | Payload | Notes |
| --- | --- | --- | --- |
| `Action` | Client to server | name plus args (below) | Validated by `ActionRouter` (ARCH-01). |
| `StateUpdate` | Server to client | full snapshot of the player's own state | Throttled (ARCH-07). |
| `PhaseChanged` | Server to client | phase, roundId, `endsAt` (server time) | Clients compute the timer from `workspace:GetServerTimeNow()`. |
| `CombatEvents` | Server to client | batch of events per tick | Sent only for fights the player is watching. |
| `Toast` | Server to client | message code | Rejected-action messages (UI-05). |

Action names and args: `BuyUnit(slot)`, `RerollShop()`, `BuyXP()`, `ToggleLock()`, `MoveUnit(unitUid, dest)`, `SellUnit(unitUid)`, `EquipItem(itemUid, unitUid)`, `UnequipItem(itemUid)`, `CombineItems(itemUidA, itemUidB)`, `PickAugment(index)`, `RerollAugment()`.

Carousel picks use one more action, `PickCarousel(index)` (4.8).

### 3.6 Performance budget `[CONFIG]`

- At most 4 fights run at once with about 18 units each plus tokens, so under 120 simulated units.
- Average sim cost MUST stay under 2 ms per fight per frame on the server.
- A snapshot MUST stay under 4 KB. Send it only when state changed.
- A client renders only its own arena. Other fights are simulated but not replicated to that client.
- Target 60 FPS on a mid-range phone during combat.

## 4. Match structure and flow

A match is a loop of Prep, Combat and Resolve phases grouped into stages, and it ends when one player remains. Players can act only during Prep.

### 4.1 Match flow

&#91;embedded content: match flow · Prep, Combat, Resolve loop\]

The `MatchService` state machine MUST implement these states, plus Carousel (4.8): `Lobby`, `MatchStart`, `Prep`, `Combat`, `Resolve`, `MatchEnd`. Each transition fires `PhaseChanged` to all clients.

Carousel rounds run the Carousel phase and then Prep, with no Combat or Resolve (4.8).

### 4.2 Round schedule `[CONFIG]`

Round IDs read `stage-round`. The global round number is `round` in stage 1, and `4 + 7 × (stage − 2) + round` from stage 2 on (so 2-1 is global round 5).

| Round | Type | Notes |
| --- | --- | --- |
| 1-1 | PvE | 1 monster. Players receive the free starter unit (LVL-05). No income. |
| 1-2, 1-4 | PvE | 2 and 3 monsters. Each drops 1 component on a win. |
| 1-3 | Carousel | Mid-stage item pick (4.8). No combat. |
| x-1 (x ≥ 2) | PvP | Round 2-1 is augment offer 1. |
| x-2 | PvP | Round 3-2 is augment offer 2. Round 4-2 is augment offer 3. |
| x-3 | PvE | Monster pack. Drops 2 components on a win. |
| x-4 | Carousel | Mid-stage item pick (4.8). No combat. |
| x-5, x-6, x-7 | PvP | The stage ends after x-7. The next round is (x+1)-1. |

### 4.3 Phases and timers `[CONFIG]`

| Phase | Duration | What happens, in order |
| --- | --- | --- |
| Prep | 25s (20s in round 1-1). Add 15s in augment rounds. | 1. Passive XP. 2. Income paid with its breakdown (ECON-02). 3. Shop refreshes unless locked. 4. Augment offer if due. 5. Players act. At the end the server locks all intents. |
| Combat | Up to 30s, then overtime | Pair opponents, build both teams on the home plot, run the sim, and stream events. |
| Resolve | 4s | Apply the result: player damage, streaks, PvE drops, eliminations, then the end check. |

### 4.4 Opponents and pairing

- **PAIR-01.** In PvP rounds, living players are paired at random. A pair MUST NOT repeat the previous round's pairing when another valid pairing exists.
- **PAIR-02.** With an odd number of living players, one player fights a ghost: a copy of another living player's board. The ghost's owner takes no damage and gets no reward.
- **PAIR-03.** The home player is whoever has been home fewer times so far. Ties are random. The fight happens on the home player's plot, and the away player's camera moves there for the fight (CMB-02 mirrors their team).
- **PAIR-04.** In PvE rounds, every player fights monsters at the same time on their own plot.

### 4.5 Player damage and elimination `[CONFIG]`

```latex
damage = stageBase(stage) + survivingUnits
```

| Stage | 2 | 3 | 4 | 5 | 6 and later |
| --- | --- | --- | --- | --- | --- |
| `stageBase` | 2 | 4 | 6 | 8 | 10 |

- `survivingUnits` is the number of living units on the winning side at the end of the fight. Only the loser takes damage. Draws deal none.
- Losing a PvE round deals no player damage and drops nothing.
- A player at 0 or less health is eliminated during Resolve. If several players are eliminated in the same round, the one with lower final health places lower, with random ties.
- After global round 40 `[CONFIG]`, all player damage doubles each additional round, so matches always end.

### 4.6 PvE monsters `[CONFIG]`

Monsters are plain units generated from formulas, with `g` as the global round. They use the Fighter archetype movement and have no ability. Tune them later by running `CombatSim` against typical boards.

| Value | Formula |
| --- | --- |
| Monster count | `min(1 + floor(g / 2), 8)` |
| Health | `250 + 60 × g` |
| AD | `12 + 3 × g` |
| Attack speed | 0.6 |

### 4.7 Bots

- **BOT-01.** When fewer than 8 humans join, bots fill the empty seats.
- **BOT-02.** Bots MUST act only through the same `ActionRouter` intents as humans. They get no hidden bonuses.
- **BOT-03.** The first bot version is simple: each Prep it buys affordable units that share a trait with its board, buys XP when it holds 50 or more gold, and places units front-line first by range.

### 4.8 Carousel rounds `[CONFIG]`

The carousel is a shared item pick in the middle of each stage: round 1-3 in stage 1, and round x-4 from stage 2 on. No combat happens and no player takes damage.

- **CAR-01.** A carousel round runs the Carousel phase first, then a normal Prep (income, shop, and any augment offer that is due). It changes no streak (ECON-04).
- **CAR-02.** The server rolls one offering per living player. Each offering is one random component. All 6 component types appear before any repeats.
- **CAR-03.** Players pick one at a time in ascending order of current health, with random ties, so trailing players choose first. Each pick has 4 seconds `[CONFIG]`. On timeout the server picks a random remaining offering. Bots pick instantly.
- **CAR-04.** All players see the offerings and each pick live. A picked item goes straight to that player's inventory.
- **CAR-05.** The phase lasts a 3 second intro plus 4 seconds per living player, at most 35 seconds in an 8-player lobby.
- **CAR-06.** Picks use the `PickCarousel(index)` action. The server accepts it only from the player whose turn it is (ARCH-01).
- **CAR-07.** `CarouselService` MUST keep offering contents and turn order on the server and replicate them in `StateUpdate`.

## 5. Economy and gold

Gold is the only resource the player controls, and every choice is spend versus save. Interest rewards saving: every 10 gold held pays 1 gold, capped at 5 gold per round once the player holds 50.

### 5.1 Rules

- **ECON-01.** Gold is a non-negative integer. Gold changes ONLY through `EconomyService.add(player, amount, reason)` and `EconomyService.spend(player, amount, reason)`. No other code writes to gold.
- **ECON-02.** Income is paid once, at the very start of each Prep phase, before the shop refreshes. The player sees an itemized breakdown for 2 seconds.
- **ECON-03.** Interest is computed from the gold the player holds at that moment, before the new income is added.
- **ECON-04.** Streaks and the win bonus count PvP rounds only. PvE rounds, carousel rounds and draws change neither.
- **ECON-05.** There is no gold cap and no negative balance. A purchase the player cannot afford MUST be rejected server-side with a reason code.
- **ECON-06.** Every gold-changing effect from traits, items and augments MUST go through the `OnIncomeCalc` hook (Section 3.4) so it appears in the breakdown.

### 5.2 Income formula

```latex
income = base(r) + \min(\lfloor gold / 10 \rfloor,\ 5) + streak(n) + win
```

In the formula, `r` is the global round number, `n` is the current win or loss streak length, and `win` is 1 if the player won the previous PvP round, else 0. Order of operations is: base, interest, streak, win bonus, then modifiers.

### 5.3 Base income by global round `[CONFIG]`

| Global round | 1 | 2 | 3 | 4 | 5 | 6 and later |
| --- | --- | --- | --- | --- | --- | --- |
| Base gold | 0 | 2 | 2 | 3 | 4 | 5 |

### 5.4 Interest `[CONFIG]`

| Gold held | 0 to 9 | 10 to 19 | 20 to 29 | 30 to 39 | 40 to 49 | 50 or more |
| --- | --- | --- | --- | --- | --- | --- |
| Interest | 0 | 1 | 2 | 3 | 4 | 5 (cap) |

### 5.5 Streak bonus `[CONFIG]`

The same table applies to win streaks and loss streaks. Loss streaks pay so that losing players can recover.

| Streak length | 0 to 1 | 2 to 3 | 4 | 5 or more |
| --- | --- | --- | --- | --- |
| Bonus gold | 0 | 1 | 2 | 3 |

### 5.6 Spending

| Action | Cost | Result |
| --- | --- | --- |
| Buy a unit | The unit's cost (1 to 5) | Unit goes to the first open bench slot |
| Reroll shop | 2 gold `[CONFIG]` | Replaces all 5 shop slots |
| Buy XP | 4 gold for 4 XP `[CONFIG]` | Adds XP, may trigger a level-up |
| Sell a unit | Refund = unit cost × 3^(star − 1) | Unit returns to the shared pool |

### 5.7 Worked examples (use as unit tests)

| Case | Inputs | Expected income |
| --- | --- | --- |
| A | Round 8, 37 gold, win streak 3, won last PvP | 5 + 3 + 1 + 1 = 10 |
| B | Round 12, 62 gold, loss streak 5, lost last PvP | 5 + 5 + 3 + 0 = 13 |
| C | Round 3, 9 gold, no streak, last round was PvE | 2 + 0 + 0 + 0 = 2 |
| D | Round 9, 50 gold, win streak 4, won last PvP | 5 + 5 + 2 + 1 = 13 |

## 6. Levels, XP, and the shop

Player level sets two things: how many units can fight at once, and which unit costs appear in the shop. Players start at level 1 and reach a maximum of level 10 `[CONFIG]`.

### 6.1 Level rules

- **LVL-01.** Board size equals player level. A level 5 player fields at most 5 units. Summoned tokens (Section 8, Pet Squad) do not count.
- **LVL-02.** Players gain 2 XP passively at the start of every round from global round 2 onward `[CONFIG]`.
- **LVL-03.** Players may buy XP at 4 gold for 4 XP `[CONFIG]` during Prep. Excess XP carries over. Buying is rejected at max level.
- **LVL-04.** Level-ups apply immediately: the board cap rises at once, and shop odds change on the next shop refresh.
- **LVL-05.** At match start each player receives one free random 1-cost unit on their bench.

### 6.2 XP required to reach the next level `[CONFIG]`

| Current level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| XP to next level | 2 | 2 | 6 | 10 | 20 | 36 | 48 | 80 | 84 |

### 6.3 Shop odds by player level `[CONFIG]`

Each shop slot first rolls a cost tier using these percentages. Every row MUST sum to 100.

| Level | 1-cost Common | 2-cost Uncommon | 3-cost Rare | 4-cost Epic | 5-cost Legendary |
| --- | --- | --- | --- | --- | --- |
| 1 | 100 | 0 | 0 | 0 | 0 |
| 2 | 100 | 0 | 0 | 0 | 0 |
| 3 | 75 | 25 | 0 | 0 | 0 |
| 4 | 55 | 30 | 15 | 0 | 0 |
| 5 | 45 | 33 | 20 | 2 | 0 |
| 6 | 30 | 40 | 25 | 5 | 0 |
| 7 | 19 | 30 | 35 | 15 | 1 |
| 8 | 16 | 20 | 35 | 25 | 4 |
| 9 | 12 | 18 | 28 | 28 | 14 |
| 10 | 5 | 10 | 20 | 40 | 25 |

### 6.4 Shop rules

- **SHOP-01.** The shop has 5 slots. Each slot rolls a cost tier from 6.3, then picks a unit of that cost, weighted by copies remaining in the shared pool.
- **SHOP-02.** Copies shown in a shop are removed from the pool immediately. Unbought copies return to the pool when the shop refreshes or the player leaves.
- **SHOP-03.** The shop refreshes automatically at the start of every Prep, after income is paid, unless the player has locked it.
- **SHOP-04.** A manual reroll costs 2 gold `[CONFIG]`. A lock toggle holds the current shop across rounds until unlocked.
- **SHOP-05.** If the rolled tier has no copies left, fall back to the next lower tier. If all tiers are empty, show an empty slot.
- **SHOP-06.** A purchase is rejected if the bench is full, unless the purchase completes a star-up merge that frees space.
- **SHOP-07.** The server rolls the shop. The client displays it and sends only slot indices.

### 6.5 Shared unit pool `[CONFIG]`

One pool exists per match, shared by all players. Counts below are for an 8-player lobby and scale per LOBBY-02. It makes contested units scarcer.

| Cost | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| Copies per unit | 22 | 20 | 17 | 10 | 9 |

### 6.6 Star-up merging

- **MRG-01.** When a player owns 3 copies of the same unit at the same star level, anywhere on board or bench, they merge automatically into one unit at the next star level. Maximum is star 3.
- **MRG-02.** The merged unit takes the board position of a consumed copy if any was on the board, otherwise the leftmost bench slot of a consumed copy.
- **MRG-03.** Items on consumed copies transfer to the merged unit up to its 3-item limit. Overflow returns to the item inventory.
- **MRG-04.** Star level multiplies base Health and Attack Damage by 1.8 per star above 1 `[CONFIG]` (star 2 = ×1.8, star 3 = ×3.24). Ability numbers use the per-star values in the unit's data.
- **MRG-05.** Selling or merging returns copies to the pool by count: a star 2 unit returns 3 copies, a star 3 returns 9.

## 7. Units

A unit's base stats come from two lookups, its cost tier and its archetype, so Claude never hand-types stat blocks. Each unit then adds a name, traits, and one ability.

### 7.1 Stat list

Every unit has these stats. All are numbers on a `StatBlock` (see Section 11).

| Stat | Default | Meaning |
| --- | --- | --- |
| Health | by cost and archetype | Reaches 0, the unit dies. |
| Attack Damage (AD) | by cost and archetype | Base physical damage of an auto attack. |
| Ability Power (AP) | 100 | Multiplies all ability output. 100 means 100%. |
| Armor / Magic Resist (MR) | 25 plus archetype bonus | Reduces physical / magic damage. |
| Attack Speed (AS) | by archetype | Attacks per second. Hard cap 5.0 `[CONFIG]`. |
| Range | by archetype | In cells, using Chebyshev distance. 1 means adjacent, including diagonals. |
| Crit chance / Crit damage | 25% / 140% `[CONFIG]` | Auto attacks only, unless an item says abilities can crit. |
| Start Mana / Max Mana | by archetype | The unit casts its ability when mana reaches Max Mana. |
| Move speed | 2 cells per second `[CONFIG]` | Same for all units. |

### 7.2 Base stats by cost tier (star 1) `[CONFIG]`

| Cost | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| Base Health | 600 | 700 | 800 | 900 | 1000 |
| Base AD | 45 | 55 | 65 | 80 | 100 |

### 7.3 Archetypes `[CONFIG]`

Each unit has exactly one archetype. It multiplies the cost-tier values and sets range, speed and mana.

| Archetype | Health × | AD × | Armor + | MR + | AS | Range | Start Mana | Max Mana |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Brawler | 1.30 | 0.80 | 20 | 20 | 0.60 | 1 | 30 | 80 |
| Fighter | 1.00 | 1.00 | 10 | 5 | 0.75 | 1 | 20 | 90 |
| Assassin | 0.85 | 1.10 | 0 | 0 | 0.85 | 1 | 30 | 70 |
| Marksman | 0.80 | 1.15 | 0 | 0 | 0.80 | 4 | 0 | 80 |
| Mage | 0.80 | 0.60 | 0 | 10 | 0.65 | 3 | 20 | 60 |
| Support | 0.90 | 0.70 | 5 | 10 | 0.65 | 2 | 30 | 70 |

```latex
Health = costHealth \times archetypeHealth \times 1.8^{(star - 1)} \qquad AD = costAD \times archetypeAD \times 1.8^{(star - 1)}
```

**Check value.** Noodle Nugget (cost 1, Brawler, star 1) MUST resolve to Health 780, AD 36, Armor 45, MR 45, AS 0.60, Range 1, Mana 30 of 80. Write this as a unit test.

### 7.4 Ability rules

- **ABL-01.** Ability output is `(base[star] + adRatio × AD) × (AP / 100)`. It applies to damage, healing and shields. AP does NOT change durations or counts.
- **ABL-02.** A unit gains 10 mana per auto attack and 3 mana each time it takes damage `[CONFIG]`. At Max Mana it casts at its next tick, and mana resets to 0.
- **ABL-03.** A cast takes 0.5 seconds `[CONFIG]`. During it the unit cannot move or attack and gains no mana.
- **ABL-04.** Stunned units cannot act. Silenced units gain mana but cannot cast. Charmed units cannot attack and walk toward the charmer.
- **ABL-05.** Each ability is declared in data as a `targeting` mode plus a list of `effects` (Section 13). Ability code MUST NOT live inside the combat loop.

### 7.5 Board, bench and sell rules

- **BRD-01.** The board is 7 columns by 4 rows for each player. The bench has 9 slots `[CONFIG]`.
- **BRD-02.** Units move between board, bench and sell zone only during Prep. Moves are validated server-side.
- **BRD-03.** Dropping a unit on an occupied cell swaps the two units.
- **BRD-04.** The server rejects a move to the board if the board already holds a number of units equal to the player level, unless it is a swap.

### 7.6 Launch roster (24 units) `[EXAMPLE]`

Trait abbreviations are expanded in Section 8. Ability values read as ★1 / ★2 / ★3. "Magic" and "physical" name the damage type. IDs are the snake\_case version of the name.

| # | Name | Cost | Traits | Archetype | Ability |
| --- | --- | --- | --- | --- | --- |
| 1 | Noodle Nugget | 1 | Noob, Bouncer | Brawler | **Slurp Shield.** Gain a 200/300/450 shield for 4s and taunt adjacent enemies for 1.5s. |
| 2 | Sleepy Sock | 1 | Brainrot, Camper | Marksman | **Snooze Barrage.** Fire 3 bolts at the target, each 60/90/135 magic. |
| 3 | Moo Moo Mogul | 1 | Tycoon, Bouncer | Brawler | **Cash Cow Stomp.** 100/150/225 magic to adjacent enemies and stun them 1/1.25/1.5s. |
| 4 | Zippy Zucchini | 1 | Speedrunner, Obby | Assassin | **Zoom Slash.** Dash to the lowest-health enemy within 4 cells and deal 150/225/340 physical. |
| 5 | Pixel Pup | 1 | Pet Squad, Glitch | Support | **Bark.exe.** Heal the lowest-health ally 150/225/340 and give it +20% AS for 3s. |
| 6 | Rizz Rabbit | 1 | Rizzler, Brainrot | Fighter | **Wink Blast.** 80/120/180 magic to the target and charm it for 1.5/2/2.5s. |
| 7 | Wobble Banana | 2 | Brainrot, Bouncer | Brawler | **Banana Slip.** The 3 nearest enemies lose 40% AS for 3/4/5s. |
| 8 | Mini Mod | 2 | Admin, Aura | Support | **Moderate.** Silence the highest-mana enemy within 5 cells for 2/3/4s and drain 30 mana. |
| 9 | Lag Lizard | 2 | Glitch, Speedrunner | Assassin | **Teleport Lag.** Blink behind the target and deal 140/210/315 magic to it. |
| 10 | Pocket Pharaoh | 2 | Tycoon, Obby | Fighter | **Gilded Slam.** 120/180/270 physical to the target. Gain +20/30/45 Armor for 5s. |
| 11 | Smooch Snail | 2 | Rizzler, Camper | Mage | **Slime Kiss.** 130/195/290 magic to the target and slow it 30% for 3s. |
| 12 | Newbie Knight | 2 | Noob, Pet Squad | Fighter | **Learn the Ropes.** Gain +15/25/35% AS for the fight. Summon a Training Pup token (200/300/450 Health). |
| 13 | Grumpy Gelato | 3 | Brainrot, Bouncer | Brawler | **Brain Freeze.** 100/150/225 magic to the target and adjacent enemies, and freeze them 1/1.5/2s. |
| 14 | Auntie Aura | 3 | Aura, Admin | Support | **Good Vibes.** Shield allies within 2 cells for 150/225/340 for 4s and cleanse their crowd control. |
| 15 | Respawn Rascal | 3 | Obby, Noob | Fighter | **Checkpoint Dash.** Leap to the farthest enemy within 5 cells, deal 150/225/340 physical, take 20% less damage for 3s. |
| 16 | Sniper Sprout | 3 | Camper, Glitch | Marksman | **Headshot.exe.** 300/450/700 physical to the lowest-health enemy in range. A kill refunds 50% mana. |
| 17 | Cash Cat | 3 | Tycoon, Pet Squad | Mage | **Make It Rain.** Coins hit 3 random enemies for 90/135/200 magic each. |
| 18 | Sir Slaysalot | 4 | Speedrunner, Rizzler | Assassin | **Flurry.** Strike the target 4 times, each 40/60/90 plus 60% AD physical. |
| 19 | Ban Hammer Bear | 4 | Admin, Bouncer | Brawler | **Ban Hammer.** 250/375/560 physical to the highest-health enemy within 2 cells and stun it 1.5/2/2.5s. |
| 20 | Spoiled Spaghetti | 4 | Brainrot, Aura | Mage | **Carbonara Chaos.** 200/300/450 magic in a 1-cell radius, leaving sauce that slows enemies 35% for 4s. |
| 21 | Lootbox Lemur | 4 | Tycoon, Noob | Fighter | **Mystery Box.** Roll once with the combat RNG: 200/300/450 magic to the target, OR a 250/375/560 self shield, OR +30% AS for 4s. |
| 22 | Rotzilla Prime | 5 | Brainrot, Obby, Speedrunner | Fighter | **Maximum Rot.** Leap to the target, deal 300/500/1200 magic in a 2-cell radius, and gain 3 Rot stacks. |
| 23 | Grand Rizzmaster | 5 | Rizzler, Aura, Admin | Support | **Admin Override.** Charm all enemies within 3 cells for 1.5/2/3s and run one Admin command immediately. |
| 24 | Granny Glitchgun | 5 | Glitch, Camper, Pet Squad | Marksman | **Mega Bark Barrage.** Fire 10 rockets at random enemies, each 60/90/270 magic in a 1-cell radius. |

**Pool check.** Cost counts MUST be 6, 6, 5, 4, 3 for tiers 1 to 5. Each trait MUST appear on the unit counts listed in 8.2. Write a data-validation test that fails if either drifts.

## 8. Traits

Traits are the synergies that make teams feel different. The launch set has 12 traits (6 Origins and 6 Classes), and each uses a different mechanic so no two builds play alike.

### 8.1 Trait rules

- **TRT-01.** A trait's count is the number of distinct unit IDs on the board that have it. Two copies of the same unit count once.
- **TRT-02.** Only the highest reached breakpoint is active. Tiers do not stack.
- **TRT-03.** Bench units and summoned tokens never count. Counts recalculate whenever the board changes during Prep.
- **TRT-04.** Each trait is data (`Shared/Data/Traits.luau`) plus one Effect module (`Server/Effects/Traits/<traitId>.luau`) that registers hooks. See Section 3.4. MUST NOT put trait logic in the combat loop.
- **TRT-05.** A trait's `scope` is `members` (only units with the trait are affected) or `team` (all allies are affected).
- **TRT-06.** All trait numbers MUST be read from the trait's `tiers[].params`, never typed in the effect module.
- **TRT-07.** The UI MUST show every trait's current count, active tier, and next breakpoint.

### 8.2 Trait overview `[EXAMPLE]`

| Trait | Type | Units | Breakpoints | Scope | Mechanic |
| --- | --- | --- | --- | --- | --- |
| Brainrot | Origin | 6 | 2 / 4 / 6 | members | Rot stacks ramp speed and power; at 6 it turns chaotic. |
| Noob | Origin | 4 | 2 / 4 | members | Permanent growth after every round fought. |
| Rizzler | Origin | 4 | 2 / 3 / 4 | team | Charms enemies at combat start. |
| Aura | Origin | 4 | 2 / 3 / 4 | team | Proximity defense, plus a shield burst on Aura death. |
| Tycoon | Origin | 4 | 2 / 3 / 4 | members | Bonus gold each round, and power that scales with banked gold. |
| Obby | Origin | 4 | 2 / 3 / 4 | members | Respawns at the starting cell once per fight. |
| Bouncer | Class | 5 | 2 / 4 / 5 | members | Armor, MR, a shield, and a taunt. |
| Glitch | Class | 4 | 2 / 3 / 4 | members | Abilities sometimes cast twice. |
| Camper | Class | 4 | 2 / 3 / 4 | members | Damage grows with distance to the target. |
| Pet Squad | Class | 4 | 2 / 3 / 4 | members | Summons pet tokens at combat start. |
| Speedrunner | Class | 4 | 2 / 3 / 4 | members | Crit, plus attack speed bursts on kills. |
| Admin | Class | 4 | 2 / 3 / 4 | team | Runs random team commands on a timer. |

### 8.3 Tier effects `[EXAMPLE]`

Times are in seconds. "Per stack" and similar values are the params to store in data.

| Trait | Tier | Effect |
| --- | --- | --- |
| Brainrot | 2 | Each member gains 1 Rot stack every 2s. Each stack gives +2% AS and +2 AP. Max 10 stacks. |
| Brainrot | 4 | A stack every 1.5s. Each stack gives +3% AS and +3 AP. |
| Brainrot | 6 | A stack every 1s. Each stack gives +4% AS and +4 AP. At 10 stacks a member enters **Full Rot**: +25% damage dealt, but its attacks and abilities pick a random enemy. |
| Noob | 2 | After each round fought, each Noob on the board permanently gains +40 Health and +4 AD for the rest of the match. Max 25 gains `[CONFIG]`. |
| Noob | 4 | The gain becomes +80 Health and +8 AD per round. |
| Rizzler | 2 | At combat start, the enemy closest to a Rizzler is charmed for 2s. |
| Rizzler | 3 | The 2 closest enemies are charmed for 2.5s. |
| Rizzler | 4 | The 3 closest enemies are charmed for 3s. |
| Aura | 2 | Allies within 2 cells of an Aura unit gain +15 Armor and +15 MR. When an Aura unit dies, all allies gain a 150 shield for 4s. |
| Aura | 3 | +30 Armor and MR. Death shield 250. |
| Aura | 4 | +45 Armor and MR. Death shield 400. |
| Tycoon | 2 | +1 gold at the start of each Prep (via `OnIncomeCalc`). Tycoons deal +1% damage per 10 gold held at combat start, max +5%. |
| Tycoon | 3 | +2 gold. +2% per 10 gold, max +10%. |
| Tycoon | 4 | +3 gold. +3% per 10 gold, max +15%. |
| Obby | 2 | The first time an Obby would die each fight, it becomes untargetable for 2s, then respawns at its starting cell with 30% Health. |
| Obby | 3 | Respawn with 45% Health. |
| Obby | 4 | Respawn with 60% Health and gain 1.5s of damage immunity. |
| Bouncer | 2 | Members gain +20 Armor and MR and a shield equal to 10% max Health for 6s. |
| Bouncer | 4 | +40 Armor and MR, a 20% shield, and enemies within 2 cells of a Bouncer are taunted to the nearest Bouncer for 2s. |
| Bouncer | 5 | +60 Armor and MR, a 30% shield, and a 3s taunt. |
| Glitch | 2 | Member ability casts have a 25% chance to cast again instantly at 50% power. |
| Glitch | 3 | 40% chance, recast at 60% power. |
| Glitch | 4 | 50% chance, recast at 75% power, and each recast freezes a random enemy for 1s. |
| Camper | 2 | Members deal +6% damage per cell between them and their target, max 4 cells. |
| Camper | 3 | +9% per cell. |
| Camper | 4 | +12% per cell and +1 Range. |
| Pet Squad | 2 | At combat start, summon 1 Pet in the nearest empty cell. A Pet has 30% of the average Health and AD of Pet Squad members on the board. |
| Pet Squad | 3 | Summon 2 Pets with 40% stats. |
| Pet Squad | 4 | Summon 3 Pets with 50% stats. Pets explode on death for 150 magic damage in a 1-cell radius. |
| Speedrunner | 2 | Members gain +20% crit chance. On a kill, gain +40% AS for 4s and reset the attack timer. |
| Speedrunner | 3 | +35% crit chance. |
| Speedrunner | 4 | +50% crit chance and +30% crit damage. |
| Admin | 2 | Every 8s the team runs 1 random Admin command (list below). Command strength scales with the average AP of Admin members. |
| Admin | 3 | Every 6s. |
| Admin | 4 | Every 4s, running 2 different commands each time. |

**Admin command list.** `!heal`: all allies heal 8% max Health. `!freeze`: the highest-AD enemy is frozen 1.5s. `!speed`: all allies gain +25% AS for 4s. `!shield`: all allies gain a 100 shield for 4s. `!kick`: the lowest-health enemy takes 150 true damage. The command is picked with the combat RNG (rule CMB-01).

### 8.4 Adding a new trait

To add a trait, Claude MUST do exactly these steps and nothing else:

1. Add the trait entry to `Shared/Data/Traits.luau`, following the schema in Section 13.
2. Add `Server/Effects/Traits/<traitId>.luau` that registers its hooks.
3. Add the trait to at least 4 unit definitions.
4. Add a data-validation test case. Do NOT edit the combat loop.

## 9. Items

Players collect 6 kinds of basic components, each boosting one stat. Fusing any two components makes a combined item that keeps both stat boosts and adds a unique effect: 6 components produce 21 combined items.

### 9.1 Item rules

- **ITM-01.** A unit holds at most 3 items, in any mix of components and combined items.
- **ITM-02.** Items are equipped, unequipped and combined only during Prep. Unequipping returns the item to the inventory.
- **ITM-03.** Combining: the player drags a component onto another component in the inventory, or taps both and presses Combine. The recipe is order-independent. Both components are consumed. A combined item can NOT be combined again.
- **ITM-04.** A combined item grants both components' stats plus its effect.
- **ITM-05.** If a unit holds two copies of the same combined item, their stats stack but their effect does NOT. Only one copy's effect is active.
- **ITM-06.** Items on a sold unit return to the inventory. Items on a unit that dies in combat are kept.
- **ITM-07.** Every item effect is an Effect module using the same hooks as traits (Section 3.4). Item data lives in `Shared/Data/Items.luau`.
- **ITM-08.** Every item has `tags` listing its stat families, so augments can target them (Section 10). A component has one tag. A combined item has the two tags of its components.
- **ITM-09.** The inventory has no hard cap in the foundation. The UI scrolls.

### 9.2 Components `[EXAMPLE]`

| ID | Name | Tag | Stat |
| --- | --- | --- | --- |
| `club` | Chonky Club | AD | +15 Attack Damage |
| `wand` | Glitter Wand | AP | +20 Ability Power |
| `snack` | Jumbo Snack | Health | +150 Health |
| `boots` | Hyper Boots | AS | +15% Attack Speed |
| `hoodie` | Plate Hoodie | Armor | +20 Armor |
| `cape` | Mystic Cape | MR | +20 Magic Resist |

### 9.3 Recipe matrix

Find the first component in the left column and the second across the top. The matrix is symmetric.

|  | Club | Wand | Snack | Boots | Hoodie | Cape |
| --- | --- | --- | --- | --- | --- | --- |
| **Club** | Giga Chonk | Chaos Wand | Beefy Bat | Turbo Slugger | Spike Hoodie | Hex Breaker |
| **Wand** | Chaos Wand | Mega Wand | Gooey Heart | Spin Cycle | Barrier Boba | Spell Sponge |
| **Snack** | Beefy Bat | Gooey Heart | Titan Snack | Zoomie Gut | Fortress Hoodie | Cleanse Flask |
| **Boots** | Turbo Slugger | Spin Cycle | Zoomie Gut | Hyper Hyper | Zoom Plating | Sparkle Sneakers |
| **Hoodie** | Spike Hoodie | Barrier Boba | Fortress Hoodie | Zoom Plating | Brick Wall | Drip Armor |
| **Cape** | Hex Breaker | Spell Sponge | Cleanse Flask | Sparkle Sneakers | Drip Armor | Void Cape |

### 9.4 Combined items and their effects `[EXAMPLE]`

Each row's stats are the sum of its two components. "Auto attack" means a basic attack, and "ability" means a cast.

| Item | Recipe | Unique effect |
| --- | --- | --- |
| Giga Chonk | Club + Club | Every 3rd auto attack deals bonus physical damage equal to 100% of the holder's AD. |
| Chaos Wand | Club + Wand | Auto attacks deal bonus magic damage equal to 30% of the holder's AP (30 at 100 AP). |
| Beefy Bat | Club + Snack | Heal for 15% of the physical damage dealt by auto attacks. |
| Turbo Slugger | Club + Boots | Attacking the same target stacks +5% AS, max 10 stacks. Stacks reset when the target changes. |
| Spike Hoodie | Club + Hoodie | When hit by an auto attack, deal magic damage to the attacker equal to 20% of the damage taken. |
| Hex Breaker | Club + Cape | Auto attacks apply Wound for 5s: the target's healing and shields are reduced by 33%. Wound does not stack. |
| Mega Wand | Wand + Wand | Abilities can critically strike using the holder's crit stats. Gain +10% crit chance. |
| Gooey Heart | Wand + Snack | Gain a shield of 15% max Health for 8s at combat start. After casting an ability, heal 10% max Health. |
| Spin Cycle | Wand + Boots | **Ramping attack speed.** Every 2s, gain +6% AS. Stacks without limit until the fight ends. |
| Barrier Boba | Wand + Hoodie | The first time the holder drops below 50% Health each fight, gain a 200 shield for 4s (scales with AP per ABL-01). |
| Spell Sponge | Wand + Cape | Negate the first instance of ability damage taken each fight. After that, gain 15 mana per ability hit taken (1s cooldown). |
| Titan Snack | Snack + Snack | Regenerate 2% of max Health per second. |
| Zoomie Gut | Snack + Boots | The first time the holder drops below 50% Health, gain +50% AS for the rest of the fight. |
| Fortress Hoodie | Snack + Hoodie | Adjacent allies (8 neighbors) gain +15 Armor and +15 MR. |
| Cleanse Flask | Snack + Cape | The first time the holder drops below 40% Health each fight: cleanse crowd control, heal 20% max Health, and become immune to crowd control for 2s. |
| Hyper Hyper | Boots + Boots | Every 4th auto attack triggers 1 extra free auto attack. The extra attack does not count toward the 4. |
| Zoom Plating | Boots + Hoodie | Each auto attack grants +3 Armor, max 10 stacks. |
| Sparkle Sneakers | Boots + Cape | Every 4th auto attack chains to the 2 enemies nearest the target, dealing 50% of the attack's damage as magic. |
| Brick Wall | Hoodie + Hoodie | Take 20% less damage from auto attacks. |
| Drip Armor | Hoodie + Cape | Gain 1.5% damage reduction per second of combat elapsed, max 30%. |
| Void Cape | Cape + Cape | Take 20% less ability damage. When damaged by an ability, deal 40 magic damage to the caster (1s cooldown). |

### 9.5 Where items come from `[CONFIG]`

- **ITM-10.** Components come from three sources: PvE drops, the carousel (4.8), and augments. PvE rounds drop 1 component at rounds 1-2 and 1-4, then 2 components at the x-3 round of every later stage.
- **ITM-11.** A drop picks a component uniformly at random, with one protection: the same component can not drop 3 times in a row for one player.
- **ITM-12.** Drops go straight to the inventory and show a pickup animation.

### 9.6 Adding a new item

Claude MUST add the entry to `Shared/Data/Items.luau`, add `Server/Effects/Items/<itemId>.luau`, and add a recipe-matrix test. MUST NOT add a combined item whose recipe collides with an existing one.

## 10. Augments

Augments are game-changing perks that a player picks three times per match, and they steer the whole game plan. Each augment has one or two categories (Economy, Combat, Items) and one rarity (Bronze, Silver, Gold).

### 10.1 Categories and rarities

| Category | Purpose | Typical effects |
| --- | --- | --- |
| Economy | Gives the player gold or bends the gold rules. | Instant gold, extra income, higher interest cap, cheaper rerolls. |
| Combat | Buffs the fight directly. | Raw stats, conditional buffs, a unique playstyle buff. |
| Items | Gives items or changes how items work. | Free components or combined items, extra drops. |
| Hybrid | Two categories on one augment. | An item reward plus a buff for units that hold that item type. |

| Rarity | Design intent |
| --- | --- |
| Bronze | Always useful, never build-defining. Small and flexible. |
| Silver | A solid, noticeable boost. Often rewards a specific plan. |
| Gold | Build-defining. About 2.5 times the value of Bronze. Players should think carefully before picking. |

### 10.2 Augment rules

- **AUG-01.** Each player gets an augment offer at the start of Prep in rounds 2-1, 3-2 and 4-2. The offer appears before the shop refreshes, and Prep gains 15 extra seconds `[CONFIG]`.
- **AUG-02.** An offer shows 3 choices. The player picks 1. If the timer ends first, the server picks the first choice.
- **AUG-03.** Each choice rolls its rarity independently from the weights in 10.3, then picks an augment of that rarity at random.
- **AUG-04.** The 3 choices MUST be distinct, MUST NOT be already owned, and MUST NOT all share the same primary category. The primary category is the first one listed.
- **AUG-05.** Each offer allows 1 reroll that replaces all 3 choices. The reroll is free `[CONFIG]`.
- **AUG-06.** There is no shared pool. Several players can own the same augment.
- **AUG-07.** Augments are Effect modules registered on the player (`Server/Effects/Augments/<id>.luau`). They can add stat modifiers, listen to hooks, grant items or gold, and change Config values for that player only, such as the interest cap.
- **AUG-08.** Chosen augments are visible to all players as icons beside the player's portrait.

### 10.3 Rarity weights per offer `[CONFIG]`

Each row sums to 100.

| Offer | Round | Bronze | Silver | Gold |
| --- | --- | --- | --- | --- |
| 1 | 2-1 | 70 | 28 | 2 |
| 2 | 3-2 | 25 | 60 | 15 |
| 3 | 4-2 | 5 | 45 | 50 |

### 10.4 Launch augments (24) `[EXAMPLE]`

Values are `[CONFIG]` params in the augment's data.

| ID | Name | Rarity | Categories | Effect |
| --- | --- | --- | --- | --- |
| `piggy_bank` | Piggy Bank | Bronze | Economy | Gain 8 gold immediately. |
| `side_hustle` | Side Hustle | Bronze | Economy | Gain +1 gold at the start of every Prep for the rest of the match. |
| `compound_interest` | Compound Interest | Silver | Economy | Your interest cap rises from 5 to 7 gold (reached at 70 gold held). |
| `winners_purse` | Winner's Purse | Silver | Economy | Your PvP win bonus is +3 gold instead of +1, and a loss pays +1 gold. |
| `venture_capital` | Venture Capital | Gold | Economy | Gain 20 gold immediately and +2 gold at the start of every Prep. |
| `reroll_frenzy` | Reroll Frenzy | Gold | Economy | Your first 2 shop rerolls each round are free. |
| `thick_skin` | Thick Skin | Bronze | Combat | All allies gain +120 Health. |
| `warm_up` | Warm-Up | Bronze | Combat | All allies gain +10% attack speed. |
| `frontline_frenzy` | Frontline Frenzy | Silver | Combat | Allies in the front two rows at combat start gain +25 Armor, +25 MR and +15% damage. |
| `team_spirit` | Team Spirit | Silver | Combat | For each distinct active trait, all allies gain +2% damage and +2% damage reduction, max 20% each. |
| `main_character` | Main Character Energy | Gold | Combat | Your highest-cost unit on the board gains +60% Health, +40% AD, +40 AP and 20% omnivamp. Ties go to the unit with more items. |
| `second_wind` | Second Wind | Gold | Combat | The first time an ally dies each fight, all allies heal 25% max Health and gain +30% AS for 5s. |
| `starter_pack` | Starter Pack | Bronze | Items | Gain 2 random components immediately. |
| `component_coupon` | Component Coupon | Bronze | Items | Choose and gain 1 component of your choice. |
| `anvil_delivery` | Anvil Delivery | Silver | Items | Choose 1 of 3 random combined items and gain it. |
| `pve_bounty` | PvE Bounty | Silver | Items | Every PvE round drops 1 extra component for the rest of the match. |
| `forge_master` | Forge Master | Gold | Items | Gain 2 random combined items immediately. |
| `ad_enthusiast` | AD Enthusiast | Silver | Items, Combat | Gain a Chonky Club. Units holding any AD-tagged item gain +15% damage. |
| `magic_mastery` | Magic Mastery | Silver | Items, Combat | Gain a Glitter Wand. Units holding any AP-tagged item gain +25 AP. |
| `tank_trainer` | Tank Trainer | Silver | Items, Combat | Gain a Jumbo Snack. Units holding any Health-tagged item gain +10% max Health and +15 Armor. |
| `triple_threat` | Triple Threat | Gold | Items, Combat | Gain 1 random component. Units holding 3 items gain +20% Health, +15% damage and 15% damage reduction. |
| `gold_plated_gear` | Gold-Plated Gear | Gold | Economy, Items | Gain 10 gold and 1 random combined item. Each time you combine two components, gain 2 gold. |
| `rich_kid_rampage` | Rich Kid Rampage | Silver | Economy, Combat | Gain 10 gold. Your units deal +1% damage per 10 gold you hold at combat start, max +10%. |
| `hot_streak` | Hot Streak | Bronze | Economy, Combat | While on a win or loss streak of 2 or more, allies gain +10% damage. |

**Count check.** The launch set MUST contain at least 1 augment for every category-and-rarity pair listed above. A data test MUST fail if any offer cannot fill 3 distinct choices that satisfy AUG-04.

### 10.5 Adding a new augment

1. Choose a rarity by its design intent in 10.1, then write the effect in at most two sentences with all numbers as params.
2. Add the entry to `Shared/Data/Augments.luau` and an Effect module in `Server/Effects/Augments/`.
3. If it changes a rule such as the interest cap, it MUST do so through a per-player Config override (rule ECON-06), never by editing global Config.

## 11. Combat system

Combat is a fixed-step simulation that runs only on the server and produces the same result every time for the same inputs. The simulation module MUST be pure Luau with no Roblox Instances, so it can be unit-tested and fast-forwarded for balance runs.

### 11.1 Arena and grid

- **CMB-01.** Determinism: one `Random.new(seed)` per combat, where `seed = hash(matchSeed, globalRound, homePlayerId)`. All chance, shuffling and random targeting use it. Units are processed in ascending `unitId` order.
- **CMB-02.** The arena is a 7-column by 8-row square grid. The home player's team occupies rows 1 to 4. The away team is mirrored by 180 degrees onto rows 5 to 8, so its cell (c, r) becomes (8 − c, 9 − r).
- **CMB-03.** Distance is Chebyshev: `max(abs(dx), abs(dy))`. Range 1 means adjacent, including diagonals. Only the `Grid` module may know the grid shape, so a hex grid can replace it later.
- **CMB-04.** One unit per cell. Summoned tokens spawn in the nearest empty cell to the summoner, ties broken by lowest column then lowest row.
- **CMB-05.** The home team is the player whose round it is. In a PvE round the monster team is the away team.

### 11.2 Tick loop

The sim steps at `dt = 0.05s` (20 Hz) `[CONFIG]`. Each tick runs these steps in this exact order:

1. Advance sim time. Expire statuses and timed modifiers. Fire `OnTick(dt)` hooks.
2. For each living unit, in ascending `unitId`: skip it if it is stunned or mid-cast. Otherwise validate its target, then pick the first matching action: cast if mana is full and not silenced, attack if the target is in range and the attack is ready, else move one step toward the target.
3. Resolve the queued damage, healing and shield events from step 2 in the order they were queued.
4. Process deaths. Fire `OnKill` and `OnDeath` hooks. Spawn queued summons.
5. Check the end condition. The fight ends when one team has no living units, or at the time limit in 11.7.

### 11.3 Targeting and movement

- **CMB-06.** Default target is the nearest living enemy by distance. Ties go to the lowest `unitId`. A unit keeps its target until it dies, becomes untargetable, or a taunt applies. If its target is out of range but another enemy is in range, it switches to the nearest in-range enemy.
- **CMB-07.** A taunt forces the target to the taunter for its duration. A charm makes the unit unable to attack and walk toward the charmer instead.
- **CMB-08.** Movement is one cell per step. A step takes `1 / moveSpeed` seconds (0.5s at 2 cells per second). The destination cell is reserved when the step begins.
- **CMB-09.** Pathfinding is breadth-first search on 8-neighbor moves with occupied cells blocked. If there is no path, step to the free adjacent cell that most reduces distance, or wait.

### 11.4 Damage pipeline

Every damage instance goes through `Damage.resolve` in this order. This is the only place health is reduced.

1. Base amount: AD for an auto attack, the ability formula (ABL-01) for abilities.
2. Critical strike: auto attacks only (unless an item says otherwise). Multiply by crit damage if the roll passes.
3. Attacker damage amp: multiply by `1 + sum of amp modifiers`.
4. Mitigation by damage type, using the formula below. True damage skips this step.
5. Target damage reduction: multiply by `(1 − r)` for each reduction source `r`, separately.
6. Shields absorb first, oldest shield first. The remainder reduces Health.
7. Minimum damage per instance is 1. Fire `OnDamageDealt`, `OnDamageTaken`, then heal from omnivamp or lifesteal.

```latex
afterArmor = preDamage \times \frac{100}{100 + armor} \qquad armor,\ MR \geq 0
```

Magic damage uses MR in the same formula. Healing is reduced by Wound (33%) before it is applied.

### 11.5 Statuses

| Status | Effect | Notes |
| --- | --- | --- |
| Stun | Cannot move, attack or cast. | Cancels a cast in progress. |
| Freeze | Same as Stun. | Separate name only for VFX. |
| Silence | Cannot cast. Still gains mana. | Does not stop attacks. |
| Charm | Cannot attack. Walks toward the charmer. | Ends early if the charmer dies. |
| Taunt | Forced to target the taunter. | Ends early if the taunter dies. |
| Slow | Move speed and attack speed × (1 − amount). | Strongest slow wins. They do not stack. |
| Wound | Healing and shields received − 33%. | Does not stack. Refreshes duration. |
| Untargetable | Cannot be chosen as a target. | Used by Obby respawn. Obby tier 4 also grants 1.5s of damage immunity (takes no damage). |
| CC immune | Ignores Stun, Freeze, Silence, Charm, Taunt. | Cleanse Flask. |

### 11.6 Stat modifiers

Every stat is a `StatBlock`: a base value plus a list of modifiers, each with a `sourceId`. This lets traits, items and augments add and remove effects cleanly.

```latex
stat = (base + \sum flat) \times (1 + \sum pct) \times \prod mult
```

- Removing a source MUST remove every modifier it added.
- The `StatBlock` recalculates lazily when marked dirty. Attack speed is capped at 5.0 after the formula.
- Crit chance is capped at 100%. Armor and MR floor at 0.

### 11.7 Time limit and overtime

- **CMB-10.** Combat lasts at most 30 seconds `[CONFIG]`. After that, overtime begins. Every living unit takes true damage each second equal to 2% of its max Health, and the rate rises by 1 percentage point every 2 seconds.
- **CMB-11.** If both teams reach zero living units on the same tick, the round is a draw. A draw deals no player damage and changes no streak.
- **CMB-12.** The result reports the winning side, the surviving units on it, and the sim time. Surviving unit count feeds player damage (Section 4).

### 11.8 Visual replication

- The server owns logical state. It sends clients a compact `CombatEvents` batch each tick for VFX, damage numbers and health bars. Event types are `Attack`, `Cast`, `Damage`, `Heal`, `Shield`, `Status`, `Move`, `Death`, `Summon`.
- In the foundation, the server moves anchored placeholder models to each unit's cell center once per step. Smooth client-side interpolation is a later optimization.
- Clients MUST NOT run gameplay logic. They only display events.

## 12. UI and UX requirements

The UI is a thin, phone-friendly view of server state: it renders what the server says and sends the player's intents back. The foundation needs a functional UI, not a polished one.

### 12.1 UI rules

- **UI-01.** The UI renders from a single client `StateStore` that holds the latest server snapshot. UI code MUST NOT change gameplay state. The only allowed local state is drag previews and open menus.
- **UI-02.** Build the UI with plain Roblox Instances created in code, using small reusable component helpers. MUST NOT add third-party UI libraries without logging a decision.
- **UI-03.** Every touch target MUST be at least 44 × 44 pixels at the reference scale. Lay out against a 1920 × 1080 reference with `UIScale`, and respect device safe areas.
- **UI-04.** Every action MUST work by tap as well as by drag (table in 12.3).
- **UI-05.** Rejected actions show a short toast from the server's reason code, e.g. "Not enough gold" or "Bench full". Never fail silently.

### 12.2 Required panels

| Panel | Contents |
| --- | --- |
| Top bar | Stage-round label (e.g. "3-2"), phase name, countdown timer, and the 8-player list with health bars and augment icons. |
| Economy bar | Gold with an interest meter (a pip per 10 gold, up to 5), level, XP bar with "x / y", and the streak indicator. |
| Shop | 5 slots showing name, cost, traits and rarity color. Buttons: Reroll (2), Buy XP (4), Lock. Slots grey out when unaffordable. |
| Board and bench | The 7×4 board and 9-slot bench with a sell zone. Shows a "units 4 / 5" counter against the player level. |
| Item inventory | Components and combined items. Combine mode via drag or tap-tap. Items show as small icons on units. |
| Trait panel | One row per trait on the board, with icon, count, tier pips, and next breakpoint. Active traits sort first. Tapping a row shows its tier text. |
| Unit info card | Opens on tap or long-press: stats, ability text for the current star, traits, and items. |
| Augment picker | Modal with 3 cards, rarity-colored, with a Reroll button and a countdown. Cannot be dismissed without choosing. |
| Income popup | Shows the itemized income breakdown for 2 seconds at the start of Prep (rule ECON-02). |
| Combat overlay | Health and mana bars over units, damage numbers, status icons, and a fight timer. |
| End screen | Placement, stats, and a Play Again button. |
| Carousel panel | Shows the shared offerings, whose turn it is, and a pick timer. Picked offerings are greyed out with the picker's name. |

### 12.3 Interactions

| Action | Drag (desktop and touch) | Tap-only alternative |
| --- | --- | --- |
| Buy a unit | Tap the shop slot | Same |
| Move a unit | Drag it to a cell or bench slot | Tap the unit, then tap the target cell |
| Sell a unit | Drag it to the sell zone | Open the info card, then tap Sell |
| Equip an item | Drag the item onto a unit | Tap the item, then tap the unit |
| Combine components | Drag one onto the other | Tap one, tap the other, press Combine |
| Unequip an item | Drag it off the unit | Open the info card, then tap the item |

### 12.4 Feedback requirements

- Star-up merges, trait tier changes, level-ups and augment picks each get a distinct sound and a short on-screen effect.
- The phase change from Prep to Combat gets a clear banner and sound.
- Low gold, full bench and a full board are always visible at a glance.
- Placeholder audio and effects are acceptable. Each one MUST be referenced by an ID in a `Shared/Config/Assets.luau` table so art can be swapped later.

## 13. Data schemas

Claude MUST implement these types in `Shared/Types.luau` first, then write all content as Lua tables that satisfy them. Changing a schema requires a `docs/DECISIONS.md` entry.

### 13.1 Core types

```lua
--!strict
-- Shared/Types.luau
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Archetype = "Brawler" | "Fighter" | "Assassin" | "Marksman" | "Mage" | "Support"
export type DamageType = "Physical" | "Magic" | "True"
export type ItemTag = "AD" | "AP" | "Health" | "AS" | "Armor" | "MR"
export type AugmentRarity = "Bronze" | "Silver" | "Gold"
export type AugmentCategory = "Economy" | "Combat" | "Items"
export type StarValues = { number } -- { star1, star2, star3 }

export type Targeting =
	"Self" | "CurrentTarget" | "NearestEnemies" | "RandomEnemies" | "FarthestEnemyInRange"
	| "LowestHealthEnemyInRange" | "HighestHealthEnemyInRange" | "HighestManaEnemyInRange"
	| "LowestHealthAlly" | "AlliesInRadius" | "EnemiesInRadius"

export type AbilityEffect = {
	kind: "Damage" | "Heal" | "Shield" | "Status" | "Dash" | "Summon" | "Mana" | "StatBuff" | "Custom",
	damageType: DamageType?,
	values: StarValues?,        -- damage, heal, shield, or buff amount per star
	adRatio: number?,           -- fraction of AD added before the AP multiplier (ABL-01)
	duration: StarValues?,      -- seconds
	status: string?,            -- a status name from Section 11.5
	radius: number?, count: number?, hits: number?,
	customId: string?,          -- Effect module id when kind == "Custom"
}

export type AbilityDef = {
	name: string,
	description: string,
	targeting: Targeting,
	range: number?, count: number?, radius: number?,
	castTime: number?,          -- default 0.5
	effects: { AbilityEffect },
}

export type UnitDef = {
	id: string, name: string,
	cost: number,               -- 1 to 5, also sets Rarity
	traits: { string },         -- Trait ids
	archetype: Archetype,
	ability: AbilityDef,
	modelId: string?, tint: Color3?, -- placeholder visuals
}

export type TierDef = { count: number, params: { [string]: number }, description: string }

export type TraitDef = {
	id: string, name: string, kind: "Origin" | "Class", scope: "members" | "team",
	tiers: { TierDef },         -- ascending by count
	description: string,
}

export type StatBonus = {
	health: number?, ad: number?, ap: number?, attackSpeedPct: number?,
	armor: number?, mr: number?, critChance: number?, critDamage: number?,
}

export type ItemDef = {
	id: string, name: string, kind: "Component" | "Combined",
	tags: { ItemTag },
	stats: StatBonus,
	recipe: { string }?,        -- exactly 2 component ids, only for Combined
	params: { [string]: number }?,
	description: string,
}

export type AugmentDef = {
	id: string, name: string, rarity: AugmentRarity,
	categories: { AugmentCategory }, -- first entry is the primary category
	params: { [string]: number },
	description: string,
}
```

### 13.2 Effect module interface

Every trait, item and augment behavior is one module with this shape. The game calls hooks; modules never poll.

```lua
export type HookName =
	"OnPrepStart" | "OnIncomeCalc" | "OnUnitBought" | "OnItemCombined" | "OnRoundEnd"
	| "OnCombatStart" | "OnTick" | "OnAttack" | "OnDamageDealt" | "OnDamageTaken"
	| "OnCast" | "OnKill" | "OnDeath" | "OnCombatEnd"

export type EffectModule = {
	id: string,
	-- Called when the effect becomes active (trait tier reached, item equipped, augment picked).
	attach: (ctx: EffectContext, params: { [string]: number }) -> (),
	-- Called when it stops being active. MUST remove every modifier it added (by sourceId).
	detach: (ctx: EffectContext) -> (),
	hooks: { [HookName]: (ctx: EffectContext, event: any) -> () }?,
}
```

`EffectContext` exposes: the owning unit or player, `statBlock` helpers (`addModifier`, `removeSource`), `sim` helpers (`queueDamage`, `queueHeal`, `queueShield`, `applyStatus`, `summon`, `rng`), and `economy` helpers (`addIncome`). It MUST NOT expose raw Instances.

### 13.3 Sample entry

```lua
-- Shared/Data/Units.luau (one entry)
{
	id = "noodle_nugget", name = "Noodle Nugget", cost = 1,
	traits = { "noob", "bouncer" }, archetype = "Brawler",
	ability = {
		name = "Slurp Shield",
		description = "Gain a shield and taunt adjacent enemies.",
		targeting = "Self",
		effects = {
			{ kind = "Shield", values = { 200, 300, 450 }, duration = { 4, 4, 4 } },
			{ kind = "Status", status = "Taunt", duration = { 1.5, 1.5, 1.5 }, radius = 1 },
		},
	},
	tint = Color3.fromRGB(255, 196, 61),
}
```

### 13.4 Data validation tests (MUST exist)

- All IDs are unique and snake\_case. Every referenced trait, item and unit ID exists.
- Every trait's tier counts ascend and none exceeds the number of units that carry the trait.
- Unit cost counts match 6, 6, 5, 4, 3. Each shop odds row sums to 100.
- The recipe matrix covers all 21 unordered component pairs exactly once.
- Every `Custom` ability effect, trait, item and augment has a matching Effect module.
- Every augment offer round can fill 3 distinct choices under AUG-04.

## 14. Build order and acceptance criteria

Claude builds the game in nine phases, and a phase is done only when every acceptance check passes. Do not start the next phase early (Section 1.2).

### 14.1 Phases

| Phase | Deliverables | Acceptance criteria |
| --- | --- | --- |
| 0. Scaffold | Rojo project and the layout in 3.3. `Types.luau`, empty Config and Data modules, a test runner, and `docs/DECISIONS.md` and `docs/SUGGESTIONS.md`. | The project syncs into Studio and runs with no errors. One sample test passes. |
| 1. Data and pure logic | All Data modules from Sections 7 to 10. `StatBlock`, `Damage`, `Grid`, `Rng`. | All data-validation tests in 13.4 pass. The Noodle Nugget check value in 7.3 passes. Damage tests cover armor, MR, true damage, crit, shields and the 1-damage floor. |
| 2. Economy and shop | `PlayerState`, `EconomyService`, `UnitPool`, `ShopService`, `LevelService`, `MergeService`. | Worked examples A to D in 5.7 pass. 10,000 simulated shop rolls at each level land within 2 percentage points of the 6.3 odds. Three copies merge to star 2, nine to star 3, and items transfer per MRG-03. Pool counts stay conserved through buy, sell and merge. |
| 3. Match loop | `MatchService` state machine, `RoundSchedule`, timers, `ActionRouter`, all Remotes, `Pairing`, PvE monster boards, and player damage. | A solo player can play rounds 1-1 through 2-3 with phases changing on schedule. Illegal intents (wrong phase, no gold, not owned) are rejected with a reason. Pairing never repeats the last opponent when avoidable. |
| 4. Combat sim | `CombatSim`, `Targeting`, `Statuses`, `CombatRunner` with placeholder models, and all 24 unit abilities from data. | The same seed gives an identical result twice (CMB-01). Mana, casting, stun, silence, charm, taunt, slow and overtime behave per Section 11. A fast-forward harness runs 1,000 fights without errors. |
| 5. Effects | `EffectRunner`, 12 trait modules, 6 component stats, 21 combined item modules. | Every trait tier and every item has a unit test that checks its numbers from 8.3 and 9.4. Removing a source removes all of its modifiers. |
| 6. Augments and inventory | `InventoryService`, `AugmentService`, 24 augment modules, offers at 2-1, 3-2 and 4-2, and the carousel (4.8). | Offers obey AUG-03 to AUG-05. Carousel picks go lowest health first and each player gets exactly one component. Each augment's effect is verified by a test. Per-player Config overrides (such as the interest cap) do not affect other players. |
| 7. UI | Every panel in 12.2 and every interaction in 12.3, built mobile-first. | A full game is playable on a phone-size emulator using taps only. Rejected actions show toasts. The timer matches the server. |
| 8. Bots and full match | `BotController`, the end screen, and a balance harness that simulates whole matches. | 1 human plus 7 bots completes a match to a winner with no errors. The harness prints average match length in rounds and the average win rate by trait. |

### 14.2 Definition of done for every phase

1. All acceptance criteria pass, with test output shown in the reply.
2. No console errors or warnings in a Studio play session.
3. Every rule ID touched is cited in a code comment.
4. Every assumption is logged in `docs/DECISIONS.md`.
5. The reply follows the format in 1.4.

### 14.3 Kickoff prompt for Claude

Paste this as the first message of the Roblox project, with this document attached or in the repo.

```markdown
You are the lead developer for a Roblox auto battler. Read the attached game design
document fully. It is the single source of truth.

Do this now, and nothing else:
1. Reply with a build plan: the modules you will create for Phase 0 and Phase 1, in
   order, with the files for each. List every ambiguity or contradiction you found,
   each with the default you propose.
2. Wait for my approval.

After I approve, build Phase 0, then Phase 1. Follow Section 1 (working protocol, code
standards, reply format). Do not start Phase 2 until I say so.
```

### 14.4 Open questions for the team

Claude MUST use the stated default until the team answers.

| Question | Default Claude uses |
| --- | --- |
| Final game name and art style. | Working title "Brainrot Battlers" with placeholder block models. |
| Max level? | 10, decided by the team (Section 6). |
| Carousel rounds? | Yes. One component carousel in the middle of each stage (4.8). Items also come from PvE rounds and augments. |
| Square grid or hex grid? | Square (CMB-03). Only `Grid` knows the shape. |
| Should bots be ranked-safe or beatable training bots? | Beatable training bots (BOT-03). |
| Persistence, ranked ladder and monetization. | Out of scope for the foundation (2.5). |
| Lobby size? | 4 players while building, 8 at launch (LOBBY-01). |
