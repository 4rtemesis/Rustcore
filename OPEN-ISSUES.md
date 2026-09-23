# Rustcore — open issues (Forever client)

Scope: `dist/forever/Rustcore/`. Branch `1.4-Forever`.
Newest first. Delete an entry when it is fixed AND verified in-client.

---

## 1. Crash on login — `GetItemInfo` is nil on Forever

**Status:** FIXED IN CODE 2026-09-22, not yet verified in-client. Reload and check.

```
Rustcore.lua:709: attempt to call a nil value    (Count: 32)
  709: in function <Rustcore.lua:700>            -- RefreshGearCache()
  1189: in function <Rustcore.lua:1139>
```

Line 709 is `local name, _, _, ilvl = GetItemInfo(link)`. `GetItemInfo` is a stock
Blizzard global that the Forever client does not expose. Not caused by the
durability split, and not by gear-cache commit `121f599`.

`Rustcore.lua:576` already guards with `if GetItemInfo then`, so the nil case was
known — line 709 just was not guarded.

**Blast radius — 13 unguarded call sites across 7 files.** A point-fix at 709
leaves 12 more crashes queued.

Unguarded `GetItemInfo`:
- `Rustcore.lua:709` (the crash), `Rustcore.lua:802`
- `RustcoreBroadcast.lua:146`
- `RustcoreStats.lua:251`, `:264`, `:433`, `:1385`
- `Verification/Inventory.lua:87`, `Verification/Transfer.lua:289`

Unguarded `GetItemIcon`:
- `Rustcore.lua:710`
- `RustcoreDeathlog.lua:405`
- `RustcoreStats.lua:460`
- `RustcoreUI.lua:129`

**Fix shape:** add `RustcoreCompat.GetItemInfo` / `RustcoreCompat.GetItemIcon`
to `RustcoreCompat.lua`, modelled on `RustcoreCompat.GetSpellTexture` (line 288).
Prefer `C_Item.GetItemInfo` / `C_Item.GetItemIconByID`, fall back to the bare
global, return nil rather than erroring. `caps.itemAPI` (line 87) already probes
the `C_Item` namespace via `HasFunc` (75/78). Compat loads at TOC 24-26, ahead of
`Rustcore.lua` at 27, so it is in scope at 709.

Several call sites already tolerate a nil return: `Rustcore.lua:714` has
`name or ("Slot " .. slotId)`, `RustcoreStats.lua:264` falls back to
`link:match("|h%[(.-)%]|h")`.

---

## 2. Dragon overlay proportions and placement

**Status:** FIXED IN CODE 2026-09-22, awaiting in-client verification.

Forever artwork is 218x180; the previous 256x128 holder stretched it.
The ornament now renders at 109x90, centered on the individual face portrait,
mirrored on the player (dragon on the left) and native on the target (right).
After screenshot feedback, both ornaments are offset 12px outward to expose more
of the face without changing their proportions.
Native portrait/frame art remains visible.

## 3. Self-found buff icon and position

**Status:** FIXED IN CODE 2026-09-22, awaiting in-client verification.

The native `UI_SelfFound` path did not produce a visible icon in the user's
client. The original icon is now bundled as `UI/SelfFound.tga`, an uncompressed
64x64 RGBA texture, avoiding dependence on client spell IDs or native asset paths.
Source: https://wow.zamimg.com/images/wow/icons/large/ui_selffound.jpg

The icon now gets a fallback screen anchor on creation, is clamped to screen,
and anchors beside BuffFrame before attempting to move the native container.
A refused container move cannot leave it unanchored. Mocked refusal test passed.

The player icon is latched to BuffFrame's right edge with a 5px gap. The native
bar shifts left 35px while enabled and restores its latest anchor on disable.
Anchor mutations are deferred during combat and Edit Mode; aura gain/loss does
not move the icon. Blizzard retains its native aura buttons and wrapping.

Lua 5.1 syntax checks passed for the Forever tree. Mocked layout checks passed
for non-accumulating offsets, replacement anchors, disable/restore, combat
transitions, dragon aspect ratio, portrait anchors, and mirrored orientation.
Check in-client: reload, gain/lose buffs, wrap rows, toggle the setting in
combat, and move the bar in Edit Mode. Confirm icon loading and dragon alignment.

## Follow-up visual adjustments (v3)

**Status:** implemented, awaiting in-client verification.

- Copy the native 24px level-badge patch above the dragon, beneath its text;
  raise player/target PvP icons above the ornament.
- Add Blizzard quickslot borders to both Self Found icons.
- Player icon follows the rightmost native buff (or AuraContainer), avoiding
  BuffFrame's extra gutter; native layout and combat deferral stay intact.
- Target detection includes named buttons, aura arrays, pools, and icon children.
  Align to the native aura's top-right; lower the empty-target fallback by 18px.
  Refresh while the target icon is shown, even if the player icon is disabled.
- Lua 5.1 syntax and mocked layout/crop checks passed.

## Follow-up v4 — badge, buff frame, popup, blocked-action diagnostics

**Status:** implemented and checked in mocks; visual/relog confirmation pending.

- Level circle uses fixed UVs from the existing `UI/UI-TARGETINGFRAME-RARE-ELITE.psd`
  sheet, shipped unmodified as a 256x128 TGA. Removed the live-frame crop calculation.
- Quickslot border canvas is 1.7x the icon to account for transparent margins.
  A complete bordered Self Found asset could not be verified; the original bundled
  icon remains combined with Blizzard's native border at runtime.
- Target lookup traverses nested aura frames; fallback is beyond the full 122px
  native row at x=146, y=-4, rather than sharing the first native buff's column.
- Popup marks its first display immediately and persists the flag in
  `RustcoreCharacterDB` (`SavedVariablesPerCharacter`). Existing profile flags migrate.
  Manual `/rcpopup` remains available.
- User confirmed protected-action error predates all portrait/buff edits.
  Root cause is still UNRESOLVED: generic dialog does not identify the function.
  `RustcoreBlockedAction.lua` records BLOCKED/FORBIDDEN event details early;
  `/rcblocked` reports the last refused function, persisted in RustcoreDB.
  No speculative changes to repair restrictions or other gameplay code were made.
- Lua 5.1 syntax and mocked layout, persistence, and diagnostic checks passed.

## Follow-up v5 — actual Forever portrait regions and forbidden event

**Status:** implemented; syntax and mocked capability/region tests passed.

The user identified UIUnitFramec60. Asset list confirms
`Interface/HUD/UIUnitFramec60.blp` (FileDataID 8036204). Forever's Camelot
PlayerFrame/TargetFrame templates use `UI-HUD-UnitFrame-SmallCircle` as a
separate LevelBackgroundCircle. Both level circles and PvP textures now copy
those native regions' texture/UVs, bounds, color, alpha, and visibility above
the dragon. Target level text resolves its actual nested region. Removed the
obsolete bundled portrait atlas and its guessed crop.

Sources:
- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Camelot/PlayerFrameTemplates.xml
- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Camelot/TargetFrameTemplates.xml

The reported blocked function is `Frame:RegisterEvent()`. The sole raw
COMBAT_LOG_EVENT_UNFILTERED registration ran unconditionally at file load.
It is now gated off on Forever 1.60.x and retail 12+, before any registration
attempt. Era/TBC retain the existing listener. IsCombatLogRestricted is also
honored where available. This targets the known forbidden event; confirm the
login dialog is gone in-client. `/rcblocked` distinguishes this login from
historical saved errors.

Attacker attribution and automatic PvP-damage death exemption depend on that
unavailable log feed; the options page now states this limitation. No alternate
PvP exemption is inferred from unrelated signals.

## Follow-up v6 — public death recap, atlas rendering, buff frame

**Status:** implemented; Lua 5.1 and mocked integration tests passed. In-client
recap field availability and final visual alignment still need verification.

- The user confirmed v5 eliminated the forbidden registration dialog.
- Atlas textures now use `SetAtlas(source:GetAtlas(), false)`. Their normal
  `GetTexCoord()` can be relative to the region, so copying just the texture
  file and those coordinates incorrectly selected the whole UIUnitFramec60 sheet.
  Ordinary non-atlas textures retain the previous copy path.
- Self Found uses the cropped native Quickslot bevel (UV 0.2..0.8), with its
  artwork inset inside the rim. No changes to the accepted buff positions.
- New `RustcoreDeathRecap.lua` checks the public recap after death when
  `Ignore PVP Death` is enabled and the raw combat log is unavailable.
  It polls briefly for fresh data, classifies GUIDs/flags rather than names,
  excludes self-inflicted damage, and recognizes player-controlled attackers.
  Restricted/secret or unidentified attackers are unknown, never assumed PvE.
- A recap only covers recent recorded hits, NOT every hit in the entire fight.
  Available NPC/environment-only recap data allows the normal penalty;
  detected player damage skips it. Missing, stale, failed, or unclassifiable
  data holds the decision without granting a PvP exemption.
- The exact selected items, original equipment snapshot, tier and weapon rule
  are saved per character before waiting. Resurrection/relog cannot reroll the
  selection. `/rcdeathreview` explains pending decisions; `apply` explicitly
  applies the saved penalty. Pending review suppresses a verified dragon until
  resolved, and cannot overwrite an earlier outstanding deletion obligation.
- `tools/test-forever-death-recap.lua` covers classification, delayed/stale/secret
  data, baseline/API failures, both death paths, original gear/rules after
  resurrection/relog, duplicate callbacks, prior obligations, and window errors.

API/source references:
- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/DeathRecapDocumentation.lua
- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua

## Follow-up v7 — binary PvP rule and final layout defaults

**Status:** implemented; syntax and regression tests passed, visual check pending.

- User explicitly selected a binary policy: detected player damage skips the
  penalty; all other results, including missing/unreadable/stale recaps, follow
  the normal penalty path. Removed the temporary verification/dragon gate.
- Existing v6 saved reviews resume automatically on login. Multiple obligations
  remain ordered; later normal penalties resume once prior items are processed.
  Fixed a forward-declaration bug in the owner check used by that queue.
- PvP tooltip explains recent enemy-player damage; green text is exactly
  "No effect on verification."
- Self Found art receives the native rounded icon mask (when available), removing
  the square corner beneath the existing bevel without changing buff placement.
- Minimap launcher moves down 3px; drag-angle calculation uses the same offset.
- Stats defaults: background on, long item names on, counter titles on, icons off.
  Previously saved preferences remain unchanged.
- Updated death-recap tests cover the binary fallback, automatic v6/relog recovery,
  and resuming queued obligations. Existing portrait/buff/popup checks pass;
  rounded-mask attachment and bounds also verified in a mock.

## Follow-up v8 — Self Found crop and minimap artwork alignment

**Status:** implemented; Lua syntax/UI regression checks passed; in-game visual check pending.

- Removed the action-bar atlas mask that over-cropped Self Found artwork.
- Bundled the unmodified native Quickslot2 border as RGBA TGA, selecting its
  complete visible 12..51 pixel bounds. This avoids client atlas remapping and
  retains transparency outside the bevel; artwork remains inset under the rim.
  Source: https://raw.githubusercontent.com/Gethe/wow-ui-textures/live/Buttons/UI-Quickslot2.PNG
- Centered minimap artwork and backing on TrackingBorder's visible circle
  (20,20 in its 64px canvas, displayed at 53px), including during click animation.
  Reverted v7's whole-button downward offset: the requested correction is inside
  the frame. Buff positions and gameplay settings are unchanged.

## Follow-up v9 — character profile dropdown

**Status:** implemented; picker regression and existing UI/syntax checks pass;
in-game click test pending.

- Forever now uses the self-contained character picker even if legacy dropdown
  globals are present. The full field explicitly accepts left-button clicks.
- An empty list opens with instructions to log in to another character with
  Rustcore enabled, instead of silently doing nothing.
- Closing the options hides the list; row selection respects the combat lock.
- Added tools/test-forever-profile-picker.lua covering the actual picker block,
  including empty state, sorting, selection, refresh and combat guards.

## Follow-up v10 — profile identity and verification persistence

**Status:** lookup fixes implemented; simulated login/accrual and existing
regressions pass. Actual client disk persistence remains unconfirmed.

- Fixed Verification/Core calling a private realm helper as a global, which
  omitted name-realm and profile-label recovery from candidate record keys.
- Fixed loss of UnitFullName's second return through a Lua boolean expression.
- Resolve a unique saved profile while waiting for the player GUID; migrate
  pre-GUID profiles once identity is available, retaining stored settings.
  Known conflicting GUIDs cannot donate settings or verification to a new character.
- FinalizeIdentity also rekeys records whose stored GUID already matches.
- Session-only tracking intentionally starts at zero; accumulated tracked time
  and the /played anchor persist. Tests exercise fresh clocks over existing data.
- Added read-only /rcsaved showing loaded/current record counts, character key,
  accumulated tracking and session tracking. This distinguishes missing saved
  data from a lookup/display issue; the TOC declares RustcoreDB account-wide.
- Tests: tools/test-forever-persistence.lua, profile picker, death recap,
  existing UI regression and all Forever Lua syntax checks.

## Confirmed persistence investigation — 2026-09-23

The user's /rcsaved screenshots on two distinct GUIDs both report loaded
profiles=0 and verification=0, then one newly created profile/record. Read-only
inspection of the installed Forever addon confirms both SavedVariables declarations
are present. Its account-wide Rustcore.lua and .bak execute as valid Lua and
contain profiles, full two-part character labels and accumulated verification time.
The current file holds one character and .bak holds another: the client is writing
session data but failing to restore the existing database. Names/realm filtering
are not the cause of the empty profile picker in these reports.

Preserved all eight current account/character save files and backups under
`dist/Forever/saved-data-backup-20260923-091923/`. These are private user data;
do not include them in addon release zips. No installed files were changed.
Do not merge verification counters or invent lost session history.

Matching firsthand beta reproduction reports:
https://us.forums.blizzard.com/en/wow/t/savedvariables-never-load-in-the-beta-%E2%80%94-all-addon-settings-reset-on-login-69913/2354798

Normal addon code cannot repair the client's SavedVariables loading step.
A temporary external file-loader/junction workaround would need separate setup
and careful account/character scoping; none installed as part of this diagnosis.

## Follow-up v11 — portrait nudges, death sources and verification import

**Status:** syntax/UI, death flow/source and import-merge regression tests pass;
in-game appearance, recap availability and export restoration need confirmation.

- Dragons move inward 1px (target left, player right) and down 1px. Self Found
  player and target icons move left 1px without changing native aura placement.
- Forever deaths read fresh public recap data even with PvP protection disabled.
  Latest readable damage source/environment is passed through the existing
  broadcast/deathlog source field. Missing/stale/secret data remains unknown;
  PvP exemptions still require the option and positive player-damage evidence.
  Recap lookup can delay normal penalty processing by up to about three seconds.
- Import previously merged a newly bootstrapped UNVERIFIED status and zero tier
  over the verified export. A session-only reference now identifies that initial
  missing-history state. Any attempted warning/degradation invalidates it.
  Imports still preserve actual statuses, death caps, counters and other findings.
  No saved schema or transfer-string format changes; existing exports still work.
- Does not repair the Forever SavedVariables loader; importing may still be needed
  after each login until the client loading bug is fixed or worked around.
- Added tools/test-forever-import-bootstrap.lua and extended death-recap tests
  for source selection, hidden names, environment damage and opt-out broadcasts.
- Source field verified against Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua
  on Gethe/wow-ui-source's forever branch. No restricted combat-log registration.

## Follow-up v12 — portrait layers and HUD layouts

**Status:** Lua syntax/UI and layout/clamp regressions passed; client visual check pending.

- Player dragon moves 1px left; target dragon moves 1px down.
- PvP artwork uses ARTWORK above the dragon but below the OVERLAY level circle.
  Player status art no longer sits on a higher child frame above the level badge.
- Raise Forever's actual PlayerRestLoop animation frame above the dragon,
  preserving its flipbook animation and Blizzard visibility handling.
  Verified path in Blizzard_UnitFrame/Mainline/PlayerFrame.xml (forever branch).
- New stats profiles default to horizontal, 440x100. Existing saved sizes and
  orientations remain unchanged. Horizontal long-item names occupy the same row
  as the other counters; vertical layouts retain their stacked arrangement.
- Lost-item icon uses Brokenframe copy.tga with a 22% dark icon overlay and
  lightly darkened frame art, preserving the frame's transparent corners.
- Durability offsets now clamp the entire panel, instead of allowing everything
  except a 40px strip to leave the screen. Native full-screen clamping also applies
  while dragging/reflowing; oversized panels scale down to fit the viewport.
- Added tools/test-forever-layout.lua for long-row geometry and viewport bounds.

## Follow-up v13 — lost items missing from remote death broadcasts

**Status:** wire-format regression and Lua/UI checks passed; live two-client test pending.

- Found SerializeDeathData deliberately blanking the item field when an outgoing
  payload exceeded 250 bytes (255 including the realm-channel marker). Local
  deathlog storage happens before serialization, explaining the local/remote split.
- Oversized messages now shorten descriptive metadata and the visible item name;
  if the bonus-data payload still cannot fit, send a valid base-item hyperlink.
  Preserve count and reported ilvl. Base-item tooltips may lack variant bonuses.
- Existing message format and receiver compatibility retained; sender must update.
- tools/test-death-broadcast-items.lua exercises serialization and receiver parsing
  for normal links, oversized bonus payloads, long Unicode names and invalid links.
