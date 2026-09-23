# Kanto Expansion

A systems-first expansion layer for **Gen1Recomp**. The goal is to make Kanto reactive, persistent and slightly unpredictable while keeping the original game recognizable.

This repository is the mod folder itself and targets Gen 1 through Gen1Recomp's API 2 mod interface.

## Install

Place the repository contents in one mod directory:

```text
mods/
└── gen1recomp_expansion/
    ├── manifest.json
    ├── main.lua
    └── src/
        ├── core.lua
        ├── extras.lua
        ├── trainers.lua
        ├── world.lua
        ├── compat.lua
        ├── night_visual.lua
        ├── pokemon.lua
        ├── knowledge.lua
        ├── ui.lua
        └── api.lua
```

Enable **Kanto Expansion** in the Gen1Recomp mod manager.

## What v0.2.0 establishes

The 0.2.0 pass hardens the mechanics underneath the planned content. The systems are intended to accept substantially different future events without requiring feature-specific engine patches.

- **World Director:** event categories, pacing budget, event/global cooldowns, recent-category suppression, category suppression, reservations, conditions and persistent history.
- **Deterministic run state:** a persistent run seed plus independent RNG streams for mutations, rumors, moods, ecology/anomalies and Director decisions, so adding a roll to one subsystem does not reshuffle unrelated systems.
- **Save migrations:** explicit schema migrations for persistent data shapes.
- **World moods:** structured mood state with intensity, pressure, causes, duration and standard system modifiers.
- **Run mutations:** weighted definition registry with categories, incompatibility support and persistent selection.
- **Rumors:** source, credibility, strength, truth state, age, map spread, confidence loss, distortion, expiry and resolution.
- **Bulletin boards:** per-location feeds with authors, priority, conditions and expiry.
- **Travel advice:** persistent claims with source, topic, confidence, truth/disproven state and expiry.
- **Route ecology:** per-map/species pressure, catches/defeats/flees, bounded pressure, natural recovery, abundance, optional migration links and threshold-based encounter replacement.
- **Wild anomalies:** definition-driven encounter traits rather than a hard-coded level flag. `LEVEL_SURGE` remains the first built-in trait.
- **Wilds of Kanto integration:** visible land/water Pokémon use the same rumor, night, ecology, mutation and anomaly arbitration as classic encounters; anomaly identity follows the specific visible Pokémon into battle.
- **Trainer memory/grudges:** resentment, respect, embarrassment, confidence, decay, tiers, encounter/battle history and bounded party adaptation.
- **Trainer archaeology:** chronological trainer snapshots instead of only a stage counter.
- **Trainer knowledge/notes:** class knowledge records, observations, unlock thresholds and confidence-ready note definitions.
- **Battle bets:** proposed/accepted/in-battle/resolved/cancelled contract lifecycle, battle identity, party restrictions and one-shot settlement effects.
- **Rocket heat:** global and regional heat, history, passive decay and named reaction tiers.
- **Reputation/NPC memory:** reputation facets, witnessed community facts, NPC memory propagation and confidence degradation.
- **Stable Pokémon identity:** every tracked Pokémon receives a persistent UID; party/box reconciliation preserves moved Pokémon and splits duplicate IDs created by clone/copy operations.
- **Pokémon relationships:** directed individual-to-individual affinity/rivalry/trust records keyed by UID, while preserving the old species summary for compatibility.
- **Pokémon personalities:** persistent personality plus an event-signal registry for content-defined expression.
- **Titles/achievements:** definition-driven thresholds plus persistent unlock history.
- **Reverse Pokédex:** priority-based observation definitions rather than one hard-coded conditional chain.
- **Superstitions:** species rules can be scoped by believer/community tags and additional conditions.
- **Museum:** staged exhibit records with discovery count, provenance and history.
- **Urban legends:** state, clues, history, trigger-driven transitions, conditions, effects and explicit resolutions.
- **Travelers/con artist:** persistent itinerary that avoids pointless same-town rerolls, plus encounter history, suspicion, alias and inventory state.
- **Curses:** per-curse definitions, escalation stages, ownership/action history and cleansing state. A truly un-discardable physical item remains deferred until the engine exposes a discard interception seam.
- **Bootleg League:** persistent gauntlet lifecycle with attempts, ordered bosses, failures and completions; trainers/location/rewards remain content.
- **After Dark:** one authoritative 24-hour Gen 1 clock, schedule registry, 2D moonlit presentation, warm window/door-glass lighting across connected maps, and Battle Art SYNC interoperability.
- **Diagnostics:** the `EXPANSION` Start-menu screen now has overview, system-state and per-Pokémon history pages.

See `docs/FEATURES.md` for the feature-by-feature system contract.

## Architecture

`main.lua` defines options and loads modules through `mod:read()` and sandboxed `load()`. Persistent expansion data stays in `mod.save`; individual Pokémon metadata stays under `mon.gen1Expansion`.

The important rule is **shared ownership of collision points**. Classic wild encounter changes pass through one `encounter.species` arbiter. Wilds of Kanto is adapted at its exported species-selection seams so it consumes the same semantics instead of creating a second rule set. Timed ambient events pass through the Director. Gen 1 time has one semantic clock and renderer-specific adapters consume it.

Content systems share lightweight condition/effect registries, deterministic RNG streams and explicit migrations. New content should register definitions instead of adding another low-level hook when an existing system already owns that concern.

## Day/night

`TIME SOURCE` supports:

- **Real Time** — device-local clock
- **Accelerated** — step-driven 24-hour cycle
- **Fixed Day** — 12:00
- **Fixed Night** — 00:00

Accelerated half-day presets are Very Fast (256), Fast (512), Normal (1024), Long (2048), Very Long (4096) and Marathon (8192) steps.

`NIGHT VISUAL` affects only Gen 1 presentation. Outdoor 2D maps receive a cool moonlit grade while standard house windows and the glass portions of doors are restored as warm light sources. Connected maps are included, so lights remain emissive while visible across a map seam. UI and normal interiors remain readable.

When **Battle Art Voxel Fork** is installed, its `SYNC` clock receives the same Kanto hour. Battle Art continues to own its sky, sun/moon, shadows, tint and voxel window lighting; its explicit DAY/NIGHT/DUSK/DAWN/CYCLE settings remain overrides.

Other mods can consume `mod.find("gen1recomp_expansion").exports.time` instead of creating another Gen 1 clock.

## Compatibility

The manifest optionally orders Kanto Expansion after:

- `BATTLE_ART_VOXEL_FORK` for clock synchronization
- `overworld_wild_spawns` for visible-encounter arbitration

Both adapters fail closed when the peer mod or expected export is absent. They restore wrapped exports on quit when still owned by this mod.

Sprite-only mods, shiny battle presentation and menu-icon mods generally operate on different surfaces. The areas most worth cross-testing are other encounter overhauls, trainer-scaling mods, full world render pipelines and mods that copy Pokémon tables.

## Extension API

`mod.find("gen1recomp_expansion").exports` now reports `api = 2`. The API exposes the clock/schedules, Director, RNG streams, Pokémon identity/history/relationships/titles, trainer memory/knowledge, rumors, boards, advice, ecology, anomalies, legends, travelers, museum, bets, League state, curses, Rocket heat, observations, superstitions, mutations, reputation and generic condition/effect registries.

Consumers should check the exported API version before depending on newer contracts.

## Validation

Every push now runs a GitHub Actions validation workflow that compiles `main.lua` and every `src/*.lua` file with Lua 5.4 and validates `manifest.json`. The tagged-release workflow repeats those checks before packaging, so a syntax-invalid release is not produced.

A real Gen1Recomp boot remains the authoritative runtime integration test. High-value manual checks for v0.2.0 are:

- existing save migration and new save initialization
- PC deposit/withdraw followed by Pokémon UID/history inspection
- two same-species party members retaining distinct UIDs/relationships
- Wilds of Kanto visible land and water spawns with mutations/anomalies enabled
- Battle Art SYNC versus explicit time modes
- Pallet ↔ Route 1 night lighting across the connection seam
- repeated/rematch trainer encounters for grudge decay/escalation
- long-step sessions for mood, Director, rumor, traveler, ecology and Rocket-heat decay

## Deliberately content-deferred

The systems can now represent the planned features, but authored placements/dialogue/fights are intentionally separate work: physical bulletin boards, con-artist NPC placement, legend clue chains, ecology tables, night encounter tables, trainer arcs/notes, bet offers/rewards, museum object changes, curse quest content and the four Bootleg League fights.

The cursed physical bag item itself remains technically deferred because the public API still lacks item-discard interception.

## Current version

`0.2.0` — system-hardening baseline for the expansion framework.
