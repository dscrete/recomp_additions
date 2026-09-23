# AGENTS.md

Guidance for contributors and coding agents working on Kanto Expansion.

## Product rules

- Keep the mod systems-first and compatible with vanilla-style Gen1Recomp gameplay. Prefer reusable mechanics plus authored content over invasive engine patches.
- Preserve future compatibility with later-generation recomp projects, especially Gold/Silver. Generation-specific presentation belongs behind adapters; shared gameplay state must not depend on Gen 1 rendering details.
- When the target game already has a native representation for a feature, prefer that native representation instead of layering a duplicate custom system on top.
- Do not add competing low-level hooks for a concern already owned by an existing expansion system. Extend the system/data definition instead.

## Shared system contracts

- **Wild encounter semantics:** classic encounters continue through the single `encounter.species` arbiter. Mods such as Wilds of Kanto that bypass that hook must be adapted to the same semantic transform order rather than given separate gameplay rules.
- **Ambient/timed events:** register with the World Director. Avoid independent per-step random rolls for authored events when the Director can express the timing.
- **Time:** consume `ctx.currentHour()` / `ctx.currentTod()` or the exported time API. Do not create another Gen 1 clock.
- **Pokemon identity:** individual relationships/history must key by the persistent expansion UID, never species name or party index.
- **Persistent data:** changes to saved record shapes require an explicit schema migration. Do not silently reinterpret old save tables.
- **Randomness:** use a named persistent RNG stream. Do not use the default stream for a subsystem that should remain reproducible independently of unrelated content.
- **Conditions/effects:** prefer the shared condition/effect registries for reusable content rules rather than inventing bespoke callback formats per feature.

## Save migrations

- `ctx.CURRENT_SCHEMA` is the expansion save schema version.
- Register migration callbacks with `ctx.registerMigration(targetVersion, fn)` in the module that owns the affected data.
- Migrations must be idempotent enough to tolerate already-normalized records and must preserve unknown fields from other/future content.
- Do not bump the schema for code-only changes that do not alter persisted shapes.

## Pokemon metadata

- Keep expansion-owned per-Pokemon data inside `mon.gen1Expansion`.
- `gen1Expansion.uid` is the stable individual identity. PC movement should preserve it; actual duplicate/copy objects are split by reconciliation.
- Never identify relationships by species, nickname, party slot, box slot or current map position.
- New title/personality/history data should extend the existing record rather than adding parallel top-level fields to the Pokemon object.
- Treat trading/link serialization as compatibility-sensitive until explicitly verified end-to-end.

## Director / rumors / ecology

- Director definitions should declare category, weight, cost and cooldown appropriate to their interruption/intensity.
- Use reservations for future context-specific events instead of repeatedly polling every step.
- Rumor gameplay payloads must remain explicit. A rumor being heard somewhere does not automatically mean its encounter effect should apply there.
- Ecology rules must remain bounded and recover toward baseline. Do not author rules that can permanently erase a route's original encounter identity through ordinary play.
- Anomaly behavior should be expressed as registered traits/definitions; do not turn `wild_anomalies` into a second ad-hoc encounter hook.

## Options and UX

- User-facing durations, rates and difficulty bands should have readable named presets whenever practical.
- Add a separate toggle for optional visual presentation when a mechanic can function without it.
- New options must have useful defaults and degrade cleanly when disabled.
- Developer/system diagnostics belong in the Expansion status pages rather than being mixed into normal dialogue.

## Night / time-of-day

- `world.tod` is the shared semantic source of time-of-day. Gameplay logic consumes semantic state, not visual darkness.
- Kanto Expansion owns Gen 1 world time, not every renderer. Feed the clock into another renderer's own supported/exported seam when possible.
- Compatibility adapters must detect targets defensively, fail closed when absent/incompatible, and restore monkey-patched exported functions on quit only when still owned by this mod.
- Gen 1's normal 2D night presentation should remain world-only: menus/dialogue stay readable and ordinary interiors remain substantially lit.
- Battle Art keeps ownership of voxel sky, shadows, tint and window lighting. Its explicit time modes override Kanto Expansion; only SYNC consumes the expansion hour.
- Future Gold/Silver support defers to the target game's native time-of-day representation.

## Compatibility

- `optional_dependencies` should be used when a compatibility adapter needs another mod loaded first but must not make it mandatory.
- Prefer public `mod.find(...).exports` / exported library seams over engine-global replacement.
- Compatibility wrappers must preserve unrelated fields and return shapes from the target mod.
- For Wilds of Kanto, visible land/water picks must receive the same rumor → night → ecology → mutation → anomaly semantics as classic encounters, and per-spawn anomaly identity must follow the exact visible Pokemon into battle.

## Releases

- Intermediate implementation commits do not touch `.release`.
- A completed user-requested change set gets one semantic version/tag after code, docs and validation are complete.
- Keep `manifest.json`, `CHANGELOG.md` and `.release` aligned.
- The release workflow must compile all Lua sources and validate `manifest.json` before packaging.
- The ZIP contains one top-level `gen1recomp_expansion/` directory and excludes repository/development files.

## Validation

- Every push is syntax-checked by `.github/workflows/validate.yml` using Lua 5.4 plus JSON validation.
- When an engine checkout is available, additionally run:
  `python3 tools/modkit.py validate /path/to/gen1recomp_expansion --strict --base auto`
- A real Gen1Recomp boot remains the authoritative runtime test.
- After shared-state changes test: old save load, fresh save, map transitions, wild encounters, trainer battles, Start-menu diagnostics, PC deposit/withdraw, evolution and save/reload.
- After encounter changes test both classic encounters and Wilds of Kanto visible land/water encounters when available.
- After day/night changes test outdoors, interiors, menus/dialogue, battle transitions, connection seams, SGB/OG and ADVANCED color modes, plus Battle Art SYNC and explicit overrides.

## Content boundaries

- Avoid hard-coding map coordinates or NPC replacements in shared systems files unless the authored content explicitly owns that location.
- Prefer registration APIs for rumors, Director events, ecology/night rules, anomalies, legends, schedules, trainer notes, travelers, exhibits, bets, bosses, curses, observations, superstitions, titles and mutations.
- If a feature genuinely requires an unavailable engine seam, keep the reusable state/API and document the limitation rather than patching unrelated private internals.
