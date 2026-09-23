# Changelog

## Unreleased

## 0.1.10

- Restored illumination to the glass portion of Pallet Town's exterior doors without brightening the whole door frame.
- Extended 2D night-light detection across connected neighbour maps, so visible Pallet Town windows and door glass stay glowing when the player crosses onto Route 1 or another adjacent map.

## 0.1.9

- Corrected the Pallet Town house-light mapping again after inspecting the actual 2x2 house blocks: `$0B/$0C/$1B/$1C` are the glass-panelled door, while the visible facade windows are OVERWORLD tile `$0A`.
- Removed the door tiles from the night-light target set and now apply the warm emissive treatment to the actual window panes.

## 0.1.8

- Corrected Pallet Town's actual 2x2 house-window tile IDs (`$0B/$0C/$1B/$1C`).
- Added a true-color/GBC night path that redraws the real window tile art after the blue night grade and adds a warm additive boost, so lit windows remain visibly bright instead of being darkened with the rest of the map.
- Left Battle Art untouched when its render pipeline owns the world.

## 0.1.7

- Fixed 2D lit-window placement to use the actual world-pass camera and canvas dimensions, so Pallet Town window palette zones reach the rendered window pixels.

## 0.1.6

- Fixed the 2D night-light tile mapping for Pallet Town house windows.

## 0.1.5

- Added warm illuminated exterior windows to the normal Gen 1 2D night renderer, preserving the cool moonlit environment around them.
- Kept Battle Art untouched because its voxel renderer already owns night window lighting.
- Updated the GitHub update source to the renamed `dscrete/recomp_additions` repository.

## 0.1.4

- Added the manifest `github` source so Gen1Recomp can discover releases for Update and Versions once the repository is public.

## 0.1.3

- Removed the experimental manifest flag so fresh installs are enabled by default under Gen1Recomp's mod enable-state rules.
- Existing users who explicitly disabled the mod keep their saved preference.

## 0.1.2

- Added a Gen 1 time-source selector: device-local Real Time, Accelerated, Fixed Day, or Fixed Night.
- Expanded the accelerated presets into a continuous 24-hour Kanto clock while preserving the existing named speeds.
- Exported a read-only `time` API (`hour`, `period`, `fraction`, `source`) for renderer and content interoperability.
- Added optional Battle Art Voxel Fork integration: when Battle Art is in SYNC mode, its existing sky, sun/moon, shadows, tint, and window lighting consume Kanto Expansion's authoritative hour. Explicit Battle Art time modes remain untouched.
- Kept later-generation native time authoritative and avoided globally spoofing the device clock.

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
