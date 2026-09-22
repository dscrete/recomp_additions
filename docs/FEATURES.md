# Feature foundations

This document maps the original expansion ideas to the 0.1.0 implementation. "Foundation" means the reusable mechanic/state/API exists and content can be added without redesigning the core.

| Feature | 0.1.0 status | Current behavior / extension point |
|---|---|---|
| Pokémon personality quirks | Implemented foundation | Each encountered/used Pokémon can receive persistent `gen1Expansion.personality` metadata. |
| Kanto rumor machine | Implemented | Persistent timed rumors, eligibility rules, director activation, optional encounter replacement fields. |
| Trainer grudges | Implemented foundation | Stable NPC IDs accumulate engagements, battles, results and turns. Repeated battles can receive a small level response. |
| Pokémon urban legends | Implemented foundation | Three seed legends, persistent stage/discovery state, and a low-weight director whisper event. Map-specific trigger chains come later. |
| Kanto Director | Implemented | Weighted event arbitration, eligibility callbacks, cooldowns, map/step ticks, persisted last event. |
| Good/bad luck streaks | Implemented | QUIET/LUCKY/RESTLESS/STRANGE moods persist for a step window and can influence anomaly rates. |
| Pokémon Center / town bulletin boards | Implemented foundation | Bulletin pool and registerable conditional headlines; currently surfaced in the Expansion screen rather than physical boards. |
| Traveling con artist | Implemented foundation | A default `CON_ARTIST` has a persistent rotating city itinerary. Actual NPC spawn/dialogue is content-deferred. |
| Battle bets | Implemented foundation | Content can stage a bet by stable trainer NPC ID; `trainer.before_battle` can enforce a chosen party subset. Prompt/reward content comes later. |
| Pokémon rivalries / relationships | Implemented foundation | Switching party battlers records partner counts by species in each Pokémon's history bag. Individual relationship presentation can be expanded later. |
| Museum changes | Implemented foundation | Persistent exhibit registry; Omanyte, Kabuto and Aerodactyl catches automatically unlock initial exhibits. Physical museum changes are deferred. |
| Rocket Heat | Implemented | Rocket trainer engagements increase heat; heat is persisted, exposed in UI/API, and can gate rumors/content. |
| Reverse Pokédex | Implemented foundation | Generates observations about the player's behavior from battles, catches, blackouts and travel. |
| Pokémon superstitions | Implemented foundation | Party-aware flavor rules for Abra, Cubone, Ghosts, Magikarp and Pikachu; exported for future NPC dialogue. |
| Route ecosystems | Implemented foundation | Catching species records pressure per map; content can register threshold/chance replacement rules. |
| Wrong / bootleg Pokémon League | Implemented foundation | Four boss IDs and persistent result/progression storage. Trainers/location/rewards are content-deferred. |
| Trainer archaeology | Implemented foundation | Trainers build persistent arc records with encounter count, first map, last map and stage API. |
| Cursed item | State foundation only | Curse touch/stage state exists. A physical un-discardable item is deferred because the public API has no discard interception hook. |
| Wild Pokémon shenanigans | Implemented foundation | Rare anomaly encounters receive a level bump and are recorded; rumors/night/ecology can also rewrite species through one arbiter. |
| Trainer Pokédex notes | Implemented foundation | Trainer-class encounter counts are tracked. Authored class descriptions/UI can be added later. |
| Unreliable map / travel advice | Implemented | Rotating deliberately unhelpful tips are generated on map changes/director events. |
| Pokémon achievements / titles | Implemented foundation | Titles currently include caught, evolved, level 50, 10 crits, 50 KOs, 100 moves and 5000 cumulative damage. |
| NPC memory contagion / reputation | Implemented foundation | NPC interaction counts plus global battle/catch/blackout/story-change reputation stats are persisted for dialogue conditions. |
| Kanto After Dark | Implemented foundation | Step-based DAY/NIGHT cycle via `world.tod`; content can register night-specific encounter replacements. No shader/palette work required. |
| Anti-randomizer | Implemented | Each run selects three persistent mutations from a small pool that subtly change trainers, wild levels, rumors, Rocket heat or anomalies. |

## Collision policy

The systems layer intentionally owns only a small number of engine seams:

- `encounter.species` is the sole wild-species arbitration point for rumors, night rules, ecology, mutations and anomalies.
- `trainer.party` handles the small dynamic trainer-level response.
- `trainer.before_battle` only enforces an already-staged bet.
- `world.tod` supplies the optional step-based night cycle while respecting a non-`DAY` value returned by another mod downstream.
- `ui.start_menu.items` adds one Expansion entry.

This is preferable to giving every feature its own wrapper and relying on middleware ordering for correctness.

## Public extension API

Other content can depend on this mod and use `mod.find("gen1recomp_expansion").exports`. The current API includes:

```text
status(game)
pokemonRecord(mon)
awardPokemonTitle(mon, id)
trainerMemory(npcId)
registerRumor(def)
activateRumor(id)
registerDirectorEvent(def)
registerEcologyRule(mapId, species, def)
ecologyPressure(mapId, species)
registerNightRule(mapId, species, def)
registerBulletin(def)
registerLegend(def)
activateLegend(id, stage)
registerTraveler(def)
travelerState(id)
unlockExhibit(id)
setBattleBet(npcId, def)
advanceTrainerArc(npcId, stage)
registerBoss(def)
recordBossResult(id, result)
touchCurse(action)
rocketHeat()
addRocketHeat(amount)
playerObservation()
superstition(game)
```

The export table carries `api = 1`; future incompatible changes should increment it rather than silently changing contracts.

## Next content pass

The highest-value next step is not more engine code. It is authored content using these extension points: named rumors tied to routes, real ecology replacement tables, 5-10 recurring trainer arcs, con-artist placements/dialogue, museum text/object changes, and the four bootleg-League fights.
