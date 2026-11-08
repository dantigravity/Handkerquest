# Handkerquest — notes for Claude

WoW addon: Objective Tracker sorting/filters + (?)/(•••) quest stacks, and the "Field Tally" parchment
(a pile of handwritten pages listing quest items to gather). Single file: `Handkerquest.lua`.
Formerly "Cache ForQuest" (renamed in v1.3.0: handkerchief + quest, after Bilbo setting off without his handkerchief).
Internal names keep the old `CFQ` / `QRF_` prefixes on purpose — renaming `QRF_SavedState` would wipe
players' settings. Slash: `/hanky`, `/handkerquest`, legacy `/cfq`.

## Client
- Flavor "wowf" (WoW Forever), `## Interface: 16001`, but a **retail-style UI**: `QuestObjectiveTracker`
  module with `.ContentsFrame`, `C_QuestLog`, `C_SuperTrack`, `Settings` canvas panels.
- Client fonts are `.slug` files — don't ship custom TTFs without testing. Parchment uses built-in
  `Fonts\MORPHEUS.TTF` / `SKURRI.TTF` / standard font (user-selectable).
- No art files: everything is drawn with `SetColorTexture`, gradients, `CreateLine` and Blizzard textures.

## Testing
- `"C:\Program Files (x86)\Lua\5.1\lua.exe" smoke.lua Handkerquest.lua` (Lua 5.1 = WoW's version).
  Must end with `N passed, 0 failed`. Syntax only: `luac.exe -p Handkerquest.lua`.
- `wowmock.lua` is loose (unknown capitalized methods are no-ops): catches logic errors and crashes,
  not visuals. Add `check(...)` lines to `smoke.lua` for every feature/fix; stub missing APIs in the mock.
- The user tests in game; say plainly what was and wasn't verified there.

## Design rules (each was a bug fix or a user decision — don't undo)
- **Stacking is visual only.** A deck holds only quests that already have a native tracker block;
  toggling stacks never adds/removes quest watches. Toggles call `CFQ.RequestNativeTrackerUpdate()`
  so Blizzard re-shows its blocks. `/hanky debug` dumps the tracker for in-game diagnosis.
- **Field Tally lists only item objectives** (`obj.type == "item"`; wording fallback when untyped) —
  `qData.itemObjectives`. Kill/explore/use goals stay off it.
- Rows: hand-inked box, quill tick, strike-through only over "count  name" (one strike per wrapped
  line); "(turn in)" is a separate unstruck note.
- **Page 1 is always "Near me"** (items within the Near me distance of the player, or progressed in the
  last 3 min). Pages 2+ are area pages grouped by `CFQ.pageGrouping`: `AREA` (explored subzone via
  `C_MapExplorationInfo`), `ZONE`, or `RADIUS` (leader clustering, optionally linked to the ••• slider).
  Pages with the same name always merge — never "Name II".
- Dog-eared bottom-right corner turns pages; resize grip is bottom-left. No ribbons, no Area/Zone/All cycle.
- No brass tack / yellow square at the top of the pile (removed at the user's request in v1.4).
- **Clicking a tally item = clicking the quest's icon in the Objective Tracker** (user decision, v1.4):
  `CFQ.ToggleSuperTrack` super-tracks the quest (click again to stop), adds no watches, opens nothing.
  Blizzard then shades the quest area on the map itself. Right-click = quest log. The addon draws
  **nothing on the world map** (an earlier ring/blob overlay covered Blizzard's highlights and was removed).
  The pin filter never dims or badges quest-area highlight pins (pins with `DrawBlob`).
- Hunting grounds = spots where the item ticked up (`CFQ.huntSpots`, saved) + the quest's map POI.
  Glow = in hunting grounds; fire = target drops it ("sure"), smoulder = name-only guess.
- **Droppers are evidence-first** (`CFQ.FindTargetDrops`): sure = the loot window showed the item from that
  npc (`CFQ.ScanLootWindow`, `GetLootSourceInfo` per slot) or the unit tooltip names the item/quest.
  Name guess only if not ruled out: ≥`P.RULE_OUT_LOOTS` tries without it, `UnitIsRelatedToActiveQuest`
  false, or tooltips list quests on this client but not this one. No bundled drop database.
- Hovering a tally item: tooltip goes beside the tally on the roomier side (`P.PlaceTooltip`); a small
  map preview (`CFQ.ShowMapPreview`: zone tiles, quest-area blob, rings, player dot) takes the candidate
  spot that is on screen and overlaps least (tally/tooltip weighted heavily, then `P.AVOID_FRAMES`).
  Blizzard's blob is only ever drawn *inside the preview*.
- Minimap: amber pins for the super-tracked quest's looted spots (`CFQ.UpdateMinimapPins`), on the rim
  when out of range; world coords: X = north, Y = west.
- Parchment look has no shaded header band (removed: it grew with the window). Grain is cropped from
  plain parchment below the quest-frame header art.
- Looks (`CFQ.parchmentStyle`, `P.STYLES`): `HANDKERCHIEF` (default), `PARCHMENT`, `NATIVE` (see-through
  window, plain UI font, no pile). All tally colours come from the style table: don't hard-code ink colours.
- The handkerchief must read as **cloth, not paper**: rounded corners, scalloped lace edge with eyelets
  (`style.cloth`, `P.LayoutClothShape`), woven border stripes, soft gradient creases, drape wrinkles.
  No torn/deckled edges on it.
- Default spot sits `P.PILE_MARGIN_Y` above the chat tabs so the back pages never lap over chat.

## Code conventions
- Main chunk is near Lua's 200-local limit: put new state/functions in the `CFQ` or `P` (parchment)
  tables, not new top-level locals.
- Saved settings: `QRF_SavedState` (account-wide). Keep old keys loadable; new keys need defaults.
  `parchmentOpts` only loads boolean values.
- Wrap risky Blizzard API calls in `pcall`; layout passes are guarded so an error can't freeze the tracker.

## Naming
- The folder name, `.toc` filename, `ADDON_LOADED` check and `.pkgmeta` `package-as` must all match.
  The SavedVariables file in `WTF\Account\<id>\SavedVariables\` is named after the folder too.
- Folder must be `Interface\AddOns\Handkerquest` (matches `Handkerquest.toc` and `arg1 == "Handkerquest"`).
  Settings file: `WTF\Account\<id>\SavedVariables\Handkerquest.lua` (was `CacheForQuest.lua`).
