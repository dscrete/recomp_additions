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
- Gen 1 may use a lightweight visual fallback to communicate night because the original game lacks a native day/night presentation.
- Future Gold/Silver support should defer to the game's native time-of-day visuals where available; do not force the Gen 1 fallback there.
- Visual fallbacks must not alter collision, map data, encounters, battle math, or save compatibility.

## Releases

- Every push/commit to `main` must produce an installable ZIP through GitHub Actions.
- The ZIP should contain one top-level `gen1recomp_expansion/` directory with `manifest.json`, `main.lua`, `src/`, and relevant documentation so it can be extracted directly into a `mods/` directory.
- Development releases are prereleases tagged from the commit SHA. Do not package `.git`, GitHub workflow files, or local development debris inside the mod ZIP.

## Validation

- Keep `main.lua` a thin bootstrap. Multi-file mod code should use `mod:read()` plus the sandboxed `load()` pattern supported by Gen1Recomp.
- Run the Gen1Recomp mod validator when an engine checkout is available:
  `python3 tools/modkit.py validate /path/to/gen1recomp_expansion --strict --base auto`
- Test save/load, map transitions, wild encounters, trainer battles, Start-menu UI, PC deposit/withdraw, and evolution after changes to shared state.
- Treat trading/link behavior of per-Pokémon custom metadata as a compatibility-sensitive area until verified explicitly.

## Content boundaries

- Avoid hard-coding map coordinates or NPC replacements in shared systems files unless the content feature specifically owns that location.
- Prefer registration APIs for rumors, ecology rules, trainer arcs, night encounters, legends, bosses, travelers, and bulletin content.
- If a requested feature requires undocumented/private engine internals, leave a stable state/API foundation and document the limitation rather than introducing a brittle engine patch.
