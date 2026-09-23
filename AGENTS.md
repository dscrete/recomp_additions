# AGENTS.md

Guidance for contributors and coding agents working on Kanto Expansion.

## Product rules

- Keep the mod systems-first and compatible with vanilla-style Gen1Recomp gameplay. Prefer small reusable mechanics plus authored content over invasive engine patches.
- Preserve future compatibility with later-generation recomp projects, especially Gold/Silver. Generation-specific presentation should live behind small adapters or options; shared gameplay state should not depend on Gen 1 rendering details.
- When the target game already has a native representation for a feature (for example Gold/Silver time-of-day visuals), prefer the native representation instead of layering a duplicate custom effect on top.
- Do not add competing hooks for the same concern. Wild encounter changes must continue through the single encounter arbiter; ambient/timed events should continue through the World Director.

## Options and UX

- User-facing durations, rates, difficulty bands, and similar tunables should have readable named presets whenever practical. Do not expose a raw numeric-only setting when a small set of useful presets communicates the intent better.
- Presets should include a sensible default and enough extremes for testing. Keep the underlying value stable so save/config compatibility is straightforward.
- Add a separate toggle for optional visual presentation when a mechanic can function without it.
- Any new option should have a useful default and should degrade cleanly when disabled.

## Night / time-of-day

- `world.tod` is the shared semantic source of time-of-day. Gameplay logic should consume the semantic value (`DAY`, `NIGHT`, or future equivalents), not infer state from a visual effect.
- Gen 1 may use a presentation fallback because the original game lacks native day/night visuals, but the cue must clearly read as a different time of day rather than merely reduced brightness.
- Prefer a world-only moonlit palette/grade. Keep dialogue boxes, menus, and other UI bright and readable. Normal indoor maps should remain substantially unchanged so entering a building feels lit compared with the outdoor night.
- A non-blocking transition cue may announce major time changes such as `NIGHT HAS FALLEN` or `MORNING HAS COME`; it must not pause movement or create game-state dependencies.
- Future Gold/Silver support should defer to the game's native time-of-day visuals where available; do not force the Gen 1 fallback there.
- Visual fallbacks must not alter collision, map data, encounters, battle math, or save compatibility.

## Releases

- Do not publish a release for every implementation commit.
- A completed user-requested change set should normally produce one tagged build after all code/docs commits are finished and checked.
- `.release` is the release marker. Change it only once at the end of a completed release-worthy request, using the next semantic tag (for example `v0.1.1`). Intermediate commits must not touch it.
- The GitHub Actions release workflow triggers only when `.release` changes on `main`; it creates the Git tag/release and packages the installable ZIP from that final commit.
- Keep `manifest.json` version and the changelog aligned with the tag named in `.release`.
- The ZIP should contain one top-level `gen1recomp_expansion/` directory with `manifest.json`, `main.lua`, `src/`, and relevant documentation so it can be extracted directly into a `mods/` directory.
- While the mod is marked experimental, automated tagged builds may remain GitHub prereleases. Do not package `.git`, GitHub workflow files, `.release`, or local development debris inside the mod ZIP.

## Validation

- Keep `main.lua` a thin bootstrap. Multi-file mod code should use `mod:read()` plus the sandboxed `load()` pattern supported by Gen1Recomp.
- Run the Gen1Recomp mod validator when an engine checkout is available:
  `python3 tools/modkit.py validate /path/to/gen1recomp_expansion --strict --base auto`
- Test save/load, map transitions, wild encounters, trainer battles, Start-menu UI, PC deposit/withdraw, and evolution after changes to shared state.
- For day/night presentation changes, explicitly test outdoors, interiors, menus/dialogue over the overworld, at least one battle transition, SGB/OG color modes, and ADVANCED color mode.
- Treat trading/link behavior of per-Pokémon custom metadata as a compatibility-sensitive area until verified explicitly.

## Content boundaries

- Avoid hard-coding map coordinates or NPC replacements in shared systems files unless the content feature specifically owns that location.
- Prefer registration APIs for rumors, ecology rules, trainer arcs, night encounters, legends, bosses, travelers, and bulletin content.
- If a requested feature requires undocumented/private engine internals, leave a stable state/API foundation and document the limitation rather than introducing a brittle engine patch.
