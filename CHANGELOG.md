# Changelog

## Unreleased

## 0.1.1

- Replaced the raw day/night step control with named duration presets from Very Fast through Marathon.
- Replaced the full-screen night dim with a Gen 1 world-only moonlit palette treatment; normal interiors and UI remain substantially unchanged.
- Added a non-blocking `NIGHT HAS FALLEN` / `MORNING HAS COME` transition cue.
- Kept the Gen 1 night presentation isolated so future Gold/Silver support can use the target game's native time-of-day visuals.
- Added `AGENTS.md` with contributor rules for presets, shared hooks, generation compatibility, packaging, and validation.
- Changed automated releases from every `main` commit to one tagged ZIP release per completed change set, triggered by the `.release` marker.

## 0.1.0

- Initial systems-first Kanto Expansion framework.
- Added centralized World Director, moods, run mutations, rumors, After Dark time-of-day, encounter arbitration, ecology pressure, and strange encounters.
- Added trainer memory/grudges, battle bets, Rocket heat, trainer archaeology, and trainer-class encounter tracking.
- Added per-Pokémon personality/history/titles/relationships, reverse-Pokédex observations, and party superstitions.
- Added museum, urban legend, traveler/con-artist, bootleg-League, and cursed-object state foundations.
- Added the Expansion Start-menu status screen and public extension API.
