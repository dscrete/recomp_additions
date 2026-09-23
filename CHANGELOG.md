# Changelog

## Unreleased

## 0.2.0

- Reworked the expansion foundations into reusable content-ready systems rather than isolated counters/state flags.
- Added explicit persistent save-schema migrations and a persistent run seed.
- Split randomness into deterministic per-subsystem streams so Director, rumor, mood, mutation, personality and encounter rolls do not reshuffle one another when unrelated content changes.
- Added shared condition/effect registries for data-driven content rules.
- Expanded the World Director with event categories, pacing budget, costs, global/per-event cooldowns, recent-category penalties, category suppression, reservations and persistent event history.
- Rebuilt world moods around pressure, intensity, causes, duration and standardized modifiers used by Director/rumor/anomaly systems.
- Made run mutations definition-driven with weights, categories, incompatibility support and persisted mutation versioning.
- Rebuilt rumors as concurrent records with source, credibility, strength, truth/status, map spread, distortion, expiry and explicit resolution.
- Added persistent per-location bulletin feeds and persistent unreliable-advice claims with source/confidence/truth/disproven state.
- Rebuilt route ecology around bounded species pressure, catch/defeat/flee history, passive recovery, abundance and optional migration links; ecology replacement chances now scale with pressure.
- Rebuilt strange encounters as a definition-driven anomaly-trait system; `LEVEL_SURGE` is the first built-in trait.
- Added Wilds of Kanto interoperability so visible land/water Pokémon consume the same rumor, night, ecology, mutation and anomaly rules as classic encounters, with anomaly identity attached to the exact visible spawn through battle start.
- Added stable per-Pokémon expansion UIDs, party/box reconciliation and clone/copy splitting so individual history and relationships no longer depend on species or party slot.
- Rebuilt Pokémon relationships as directed individual UID edges with affinity, rivalry, trust, switch history and persistent state.
- Added a personality event-signal registry and definition-driven Pokémon title/achievement rules with persistent unlock history.
- Rebuilt Reverse Pokédex observations and Pokémon superstitions as registries with priorities/conditions and optional believer/community tags.
- Expanded trainer memory into resentment, respect, embarrassment, confidence, decay, grudge tiers, bounded trainer adaptation and chronological archaeology snapshots.
- Added trainer-class knowledge/notes with encounter/map/party observations, thresholds and confidence-ready note definitions.
- Rebuilt battle bets around a complete proposed/accepted/in-battle/resolved/cancelled contract lifecycle with one-shot settlement effects.
- Expanded Rocket Heat with global/regional state, history, passive decay and named reaction tiers.
- Added reputation facets plus community/NPC fact memory propagation with confidence degradation.
- Expanded museum exhibits into staged records with provenance/discovery history; expanded urban legends into clue/transition/resolution state machines.
- Expanded the traveling NPC system with non-repeating itinerary selection, suspicion, alias/inventory state and encounter history.
- Expanded curses into per-curse definitions with stages, action history and cleansing; the physical un-discardable bag item remains blocked by the missing public discard interception hook.
- Expanded the Bootleg League foundation into an ordered persistent gauntlet lifecycle with attempts, failures and completions.
- Added a reusable time schedule registry on top of Kanto After Dark.
- Expanded the Start-menu `EXPANSION` screen into overview, system-state and individual Pokémon-history diagnostic pages.
- Bumped the public extension exports to `api = 2` and exposed the hardened systems for future content modules.
- Added push-time Lua 5.4 syntax/manifest validation and made tagged releases repeat validation before packaging.

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
