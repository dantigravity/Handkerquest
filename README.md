# Handkerquest test harness

Runs the addon outside WoW against a mocked WoW API (`wowmock.lua`) and checks the main paths:
parchment rows (items only, no redundant "/N", strike only through the item text, quill ticks),
the "Near me" page and area pages (map areas / zones / distance, same names merged), the dog-eared
page-turn corner, area-change page return, handwriting cycle, lvl/dist sort cycling, menu Reset,
stacking toggles never changing the watch list, options panel, slash commands, `/hanky debug`,
looks (handkerchief / parchment / window), hunting-spot & dropper learning, glow / fire ink,
item click super-tracking, loot-window dropper evidence, hover map preview placement, minimap pins, default position margins.

## Run
From the addon folder (needs Lua 5.1 — WoW's Lua version):

    "C:\Program Files (x86)\Lua\5.1\lua.exe" smoke.lua Handkerquest.lua

Prints any failures, then "N passed, N failed". Exit code is 0 only if everything passed.

## Notes
- The mock is deliberately loose: any unknown capitalized method is a no-op, so this catches
  logic errors, nil-index crashes and broken flows — not visual problems. Still /reload in game.
- When adding a feature, add a few `check(...)` lines to smoke.lua for it.
- If the mock is missing an API the addon starts calling, add a stub to wowmock.lua.
