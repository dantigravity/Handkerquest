# Cache ForQuest test harness

Runs the addon outside WoW against a mocked WoW API (`wowmock.lua`) and checks the main paths:
parchment rows (items only, no redundant "/N", strike only through the item text, quill ticks),
one page per area with the dog-eared page-turn corner, area-change page return, handwriting cycle,
lvl/dist sort cycling, menu Reset, stacking toggles never changing the watch list, options panel,
`/cfq debug`.

## Run
From the repo root (needs Lua 5.1 — WoW's Lua version):

    lua5.1 tests/smoke.lua CacheForQuest.lua

Prints any failures, then "N passed, N failed". Exit code is 0 only if everything passed.

## Notes
- The mock is deliberately loose: any unknown capitalized method is a no-op, so this catches
  logic errors, nil-index crashes and broken flows — not visual problems. Still /reload in game.
- When adding a feature, add a few `check(...)` lines to smoke.lua for it.
- If the mock is missing an API the addon starts calling, add a stub to wowmock.lua.
