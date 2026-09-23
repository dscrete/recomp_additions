# Kanto Expansion

An experimental, systems-first expansion layer for **Gen1Recomp**. The goal is to make Kanto feel reactive and slightly unpredictable without replacing the original game or requiring renderer/shader-level work.

This repository is the mod folder itself. It targets Gen 1 through the current Gen1Recomp **API 2** mod interface.

## Install

Place the repository contents in a single mod directory so the layout is:

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
        ├── pokemon.lua
        ├── ui.lua
        └── api.lua
```

Enable **Kanto Expansion** in the Gen1Recomp mod manager. The manifest is marked experimental while the systems are still being filled with content.

## What exists in 0.1.0

The first pass implements the reusable mechanics rather than filling every route with finished authored content:

- centralized **World Director** with cooldowns and weighted events
- persistent **world moods / luck states**
- lightweight **run mutations** (the anti-randomizer idea)
- **rumors**, bulletin headlines, and unreliable travel tips
- step-based **After Dark** time-of-day cycle with named duration presets
- optional lightweight **night visual** fallback for Gen 1
- one centralized wild encounter arbiter for rumors, ecology, night rules, run mutations, and strange encounters
- **route ecology pressure** tracking with registerable replacement rules
- rare **strange wild encounters** with boosted levels
- **trainer memory / grudges**, battle history, trainer-class notes, and trainer archaeology state
- **battle bet** mechanics for pre-agreed party restrictions
- **Rocket heat**
- per-Pokémon **personality**, battle history, titles, and partner/rival relationship counters
- **Reverse Pokédex** observations about the player
- party-based **Pokémon superstitions**
- **museum exhibit** unlock state (fossils are wired as the first automatic exhibits)
- **urban legend** discovery/progression state and director whispers
- **traveling NPC / con artist itinerary** state
- **bootleg League / hidden boss** progression registry
- **cursed-object** state machine
- an **EXPANSION** Start-menu screen showing the main live systems
- a public `mod.exports` API so later content can register rumors, ecology rules, night rules, legends, travelers, bosses, bulletins, bets, and director events without adding competing engine hooks

See [`docs/FEATURES.md`](docs/FEATURES.md) for the feature-by-feature status.

## Architecture

`main.lua` only defines options and loads modules with `mod:read()` + the sandboxed `load()` supplied by Gen1Recomp. No engine-internal `require` calls or extra permissions are used.

The important design rule is that systems which can collide share one arbitration point. Wild encounter features all pass through one `encounter.species` wrapper, while timed/ambient events all pass through the World Director. This keeps future content from turning into a stack of hooks fighting over the same result.

Persistent global state lives in the mod's `mod.save` namespace. Per-Pokémon history is stored in one `mon.gen1Expansion` table.

## Day/night options

The day/night cycle uses named presets instead of a raw step-only control:

- Very Fast — 256 steps
- Fast — 512 steps
- Normal — 1024 steps
- Long — 2048 steps
- Very Long — 4096 steps
- Marathon — 8192 steps

`NIGHT VISUAL` controls the optional Gen 1 visual fallback independently of the semantic time-of-day system. Future Gold/Silver support should prefer the target game's native time-of-day presentation and leave this fallback disabled or bypassed.

## Automated development releases

Every push to `main` is packaged by GitHub Actions into an installable ZIP and published as a prerelease tagged to that commit. The ZIP contains a single top-level `gen1recomp_expansion/` directory so it can be extracted directly into a `mods/` directory.

## Deliberately deferred pieces

A few ideas have foundations but are not force-implemented yet because doing so now would be brittle or content-dependent:

- **Cursed physical bag item:** the current public hook catalog does not expose an item-discard interception point. The curse state machine exists, but a truly "refuses to be thrown away" item should wait for an appropriate public seam rather than patching engine internals.
- **Traveling con artist on-map NPC:** the itinerary system works, but actual spawn coordinates, sprite, dialogue, and map-safe placement are content decisions. Hard-coding them in the systems layer would create map conflicts immediately.
- **Bootleg League:** boss registration/progression exists; the actual four trainers, location, dialogue, and rewards are authored content for the next pass.
- **Battle-bet prompt:** the battle hook can enforce an agreed party scope. The dialogue/UI that offers and accepts a bet is intentionally left to trainer-specific content instead of interrupting every trainer encounter.
- **Museum room changes:** exhibit unlocks are tracked now; visible museum object/text changes need the concrete exhibit layout/content pass.

One area worth validating carefully in-game is custom per-Pokémon metadata through every lifecycle path (PC deposit/withdraw, evolution, trading/link flows). The design keeps all metadata under one field so it can be migrated cleanly if a specific path needs special handling.

## Validation

For an engine source checkout, run Gen1Recomp's normal mod validator from the engine root:

```bash
python3 tools/modkit.py validate /path/to/gen1recomp_expansion --strict --base auto
```

The Lua modules have also been smoke-tested with a stubbed API for load, event, hook, persistence, encounter, trainer, and export behavior. A real Gen1Recomp boot is still the authoritative integration test.

## Current version

`0.1.0` — framework/basics pass. Content density comes next.
