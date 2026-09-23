# Feature systems

This document describes the **system contract** for each original Kanto Expansion idea as of v0.2.0. Authored NPCs, dialogue, encounter tables, fights and map edits are deliberately separate from the reusable mechanics below.

| Feature | System status | v0.2.0 system contract |
|---|---|---|
| Pokémon personality quirks | Content-ready core | Every tracked Pokémon has a persistent UID and personality. Personality definitions can react to standardized event signals such as move use, critical hits, switching, KOs and fainting without owning battle hooks individually. |
| Kanto rumor machine | Content-ready core | Multiple concurrent rumors carry source, category, map, credibility, strength, truth/status, distortion chance, expiry, payload and spread history. Rumors propagate to visited maps with confidence loss and can be resolved/disproven. |
| Trainer grudges | Content-ready core | Stable trainer IDs accumulate resentment, respect, embarrassment and confidence from battle outcomes. Memory decays over time, resolves to tiers, records history, and can produce bounded trainer adaptation. |
| Pokémon urban legends | Content-ready core | Legends have unknown/heard/investigating/resolved state, stages, clues, bounded history and trigger-driven transitions with conditions/effects/resolution types. |
| Kanto Director | Content-ready core | Central event arbiter has pacing budget, category, weight, cost, global/per-event cooldowns, recent-category penalty, category suppression, reservations, conditions and persistent history. |
| Good/bad luck / world moods | Content-ready core | Moods have identity, intensity, pressure, causes, expiry and standardized modifiers consumed by Director/rumor/anomaly systems. Player outcomes can move mood pressure instead of moods being unrelated random labels. |
| Bulletin boards | Content-ready core | Per-location feeds hold posts with author, priority, condition, creation/expiry and text. Other systems/content can post into or query a board without creating separate persistence. |
| Traveling con artist | Content-ready core | Generic travelers have persistent route state, forced-different destination selection when possible, movement history, encounters, suspicion, alias index and inventory state. |
| Battle bets | Content-ready core | Bets are contracts with PROPOSED → ACCEPTED → IN_BATTLE → RESOLVED/CANCELLED lifecycle, battle identity, optional party restrictions and one-shot outcome effects. |
| Pokémon rivalries / relationships | Content-ready core | Relationships are directed edges between **individual Pokémon UIDs**, tracking affinity, rivalry, trust, switches and history. Same-species Pokémon remain distinct. |
| Museum changes | Content-ready core | Exhibits are staged records with unlock state, discovery count, provenance, species, timestamps and history. Catching initial fossil species wires into the system automatically. |
| Rocket Heat | Content-ready core | Heat has global and regional values, source history, passive step decay and named COLD/NOTICED/WATCHED/WANTED/HUNTED tiers. |
| Reverse Pokédex | Content-ready core | Observation definitions have eligibility/condition, priority and confidence. The engine returns an ordered set of observations instead of one hard-coded conditional chain. |
| Pokémon superstitions | Content-ready core | Superstition definitions match party species plus optional believer/community tags and conditions, allowing contradictory local beliefs rather than universal truth. |
| Route ecosystems | Content-ready core | Per-map/species records track bounded pressure, catches, defeats and flees. Pressure recovers toward baseline over time; rule definitions control cap/recovery/migration and pressure-scaled encounter replacements. |
| Wrong / bootleg Pokémon League | Content-ready core | Persistent gauntlet lifecycle tracks starts, ordered bosses, run progress, failures, completions, per-boss attempts/results and history. Actual trainers/rules/rewards are content. |
| Trainer archaeology | Content-ready core | Each trainer builds chronological encounter/battle snapshots containing map, class, party index, outcome and turns in addition to arc stage. |
| Cursed item | System-ready, physical item blocked | Generic curse definitions support independent curse IDs, escalation thresholds, action history, stage callbacks and cleansing. A truly un-discardable bag item still requires a public discard interception seam. |
| Wild Pokémon shenanigans | Content-ready core | Anomalies are definition-driven encounter traits with weighting/conditions and persistent encounter identity. `LEVEL_SURGE` is merely the first trait; Wilds-visible anomalies stay attached to the specific overworld Pokémon until battle. |
| Trainer Pokédex notes | Content-ready core | Trainer-class knowledge records encounters, maps, party indices, arbitrary observations and history. Note definitions unlock through encounter/observation thresholds and conditions. |
| Unreliable map / travel advice | Content-ready core | Advice is stored as claims with source, topic, truth, confidence, creation/expiry and disproven state instead of randomly damaging the real map. |
| Pokémon achievements / titles | Content-ready core | Titles are definition-driven rules stored per individual Pokémon with unlock metadata/history. Metric rules already cover moves, crits, damage, KOs, level and travel; explicit event titles cover catching/evolution. |
| NPC memory contagion / reputation | Content-ready core | Reputation has named facets/history. Communities hold witnessed facts; NPCs can inherit those memories with reduced confidence, sharing infrastructure with rumor-like propagation rather than one global reputation score. |
| Kanto After Dark | Content-ready core | One authoritative 24-hour Gen 1 clock supports real-time, accelerated and fixed sources. A reusable schedule registry exposes time/map conditions. 2D night presentation owns standard outdoor lighting while Battle Art consumes the same semantic hour through its SYNC seam. |
| Anti-randomizer / run mutations | Content-ready core | A persistent run seed selects weighted mutation definitions through an isolated RNG stream. Definitions support categories, incompatibilities and modifiers; mutation version is persisted for migration. |

## Shared infrastructure

### Stable Pokémon identity

Every tracked Pokémon receives a persistent `gen1Expansion.uid`. Party/box reconciliation scans Gen 1's `save.party` and `save.boxes`. Moving a Pokémon preserves the UID because the same Pokémon table moves between containers. If two distinct live tables contain the same UID, the later copy is treated as a clone/copy and receives a new UID with `clonedFrom` metadata.

All personality, title, history and relationship state remains under `mon.gen1Expansion`.

### Save schema migrations

Persistent data changes are versioned through `ctx.CURRENT_SCHEMA`. Feature modules register migrations against a target schema version and the core executes them in order on `game.ready`/`save.loaded`. v0.2.0 migrates legacy RNG, mood, run-mutation, exhibit, curse, rumor and ecology state.

### Deterministic RNG streams

The expansion stores one run seed but derives independent persistent streams for unrelated systems. Director rolls therefore do not consume the same sequence as mutations, rumors, personalities, advice, ecology or anomalies. Adding content to one subsystem should not silently reshuffle another subsystem's future random choices.

### Conditions and effects

Reusable content can register named conditions/effects. Conditions support named handlers and simple `all` / `any` / `not` composition. Systems such as legends, Director events, schedules, ecology rules and bet settlement can consume the same condition/effect contracts rather than inventing bespoke callbacks.

### World Director ownership

Ambient/timed content should prefer Director events instead of independently rolling every step. Events specify category, weight, cost and cooldown. Reservations allow content to request a future suitable trigger (for example, a nighttime map entry) without polling every subsystem independently.

### Encounter ownership

`encounter.species` remains the sole engine arbitration point for classic random encounters. It applies, in order:

1. active rumor replacements,
2. registered night rules,
3. route-ecology rules,
4. run mutation level changes,
5. anomaly traits.

**Wilds of Kanto** bypasses `encounter.species` by design because it chooses visible Pokémon directly. `src/compat.lua` therefore adapts Wilds' exported land/water pickers to the same semantic rule order and carries anomaly metadata on the exact visible spawn into battle.

### Time ownership

Gen 1 has one semantic Kanto hour. Renderers and content consume it instead of inventing parallel clocks. The 2D renderer applies the normal night presentation; Battle Art only receives the hour in SYNC mode and continues to own its own voxel pixels. Future Gen 2 support defers to native `MORN` / `DAY` / `NITE` state.

## Public extension API

Other content can use `mod.find("gen1recomp_expansion").exports`. The export table is now `api = 2` and includes:

```text
status(game)
time.* / registerSchedule / scheduleActive
rng.seed / rng.next / rng.chance
pokemonId / pokemonRecord / reconcilePokemonIdentity
registerPersonality / registerPokemonTitle / awardPokemonTitle
relationship / adjustRelationship
trainerMemory / grudgeState / trainerArc / advanceTrainerArc
registerTrainerNote / trainerKnowledge / trainerNotes / recordTrainerObservation
reputation / reputationFacet / adjustReputationFacet
publishCommunityMemory / npcMemories
registerRumor / activateRumor / activeRumors / resolveRumor
registerDirectorEvent / reserveDirectorEvent / suppressDirectorCategory / directorStatus
registerEcologyRule / ecologyState / ecologyPressure / ecologyAbundance / recordEcologyEvent
registerNightRule
registerAnomaly / anomalyRate
registerBulletin / postBulletin / bulletins
issueAdvice / currentAdvice / disproveAdvice
registerLegend / activateLegend / legendState / addLegendClue / advanceLegend / resolveLegend
registerTraveler / travelerState / recordTravelerEncounter
unlockExhibit / advanceExhibit / exhibitState
createBattleBet / acceptBattleBet / cancelBattleBet / battleBet / setBattleBet
registerBoss / recordBossResult / leagueState / startLeague / resetLeague
registerCurse / curseState / touchCurse / cleanseCurse
rocketHeat / rocketHeatTier / addRocketHeat
registerObservation / playerObservation / playerObservations
registerSuperstition / superstition / superstitions
registerMutation / mutations
moodState / adjustMoodPressure
registerCondition / registerEffect / checkCondition / runEffects
```

`setBattleBet` remains as an API-1-style convenience and now creates + accepts the contract immediately.

## Content still intentionally absent

v0.2.0 does **not** fill Kanto with final authored material. Still to be written later are route-specific night/ecology tables, rumor chains, board placements, recurring trainer arcs, trainer notes, community memories, con-artist dialogue/stock, museum displays, legend clues, curse quest content, bet offers/rewards and the four Bootleg League encounters.

The goal of this release is that those examples can be authored as data/content against stable mechanics rather than requiring the underlying systems to be redesigned for each case.
