# Boss Reforging prototype

Implemented in `dist/forever/Rustcore` and mirrored selectively into the packaging
source, `release/Rustcore`. Existing unrelated differences between those trees
were preserved. This prototype has automated Lua 5.1 coverage; it has not been
executed inside a logged-in Forever client.

## Gameplay

Production unlock is `RustcoreReforge.REFORGE_UNLOCK_LEVEL = 60`. The existing
difficulty certification must be valid, and Allow Item Repair must be off.
Rustbound uses the existing verified repair history plus the new persistent
history. It is an addon prestige indicator, not a server spell/aura. Historical
repairs that older addon versions never observed cannot be reconstructed.

Only durable equipment and normal carried bags are scanned. GUIDs are required;
there is no item-ID or slot-based identity fallback. Banked items keep their saved
state but are neither scanned nor awarded Shards. Moving, banking, and retrieving
the same GUID preserves its state. Unsupported/unreadable items cannot be reforged.

Initial curated source: Ragnaros (encounter 672), Perdition's Blade (18816),
Crown of Destruction (18817), and Spinal Reaper (17104). Source mappings live in
`Reforge/Sources.lua`. Encounter IDs are distinct from creature/NPC IDs.

At a repair vendor, the **Boss Reforging** panel opens automatically beside the
merchant window, aligned to its top edge, after the client finishes showing it. It uses the same frame art,
fonts, title panel, and button skins as the options UI.
Each charged item has a **Reforge** button. Scroll the panel for more items.
Manual Reforge ignores durability thresholds. The ordinary Blizzard repair cursor
stays blocked: the prototype uses explicit item buttons to guarantee that the GUID
and Shard are validated before invoking the normal individual-repair API.

**Reforge All** snapshots qualifying items, their exact repair costs, and the
threshold. A confirmation describes the Shards, gold, and skipped items. Confirming
revalidates the snapshot before issuing individual repairs in that click handler.
No delayed timer attempts protected repair actions. If the client rejects bulk
actions, use individual Reforge buttons. A failed or unconfirmed repair retains its
Shard; pending requests cannot be retried for eight seconds. Partial bulk success
consumes only the Shards for items actually observed at full durability.

The **Options → Reforge** tab shows only an explanation before the unlock level.
After unlock (including a developer level override), it shows the threshold slider
and **Glow on Reforge Ready Counters** toggle. The threshold defaults to 50%,
inclusive, with a 10–90% range. The glow defaults to on and uses the standard spell hover highlight on the
item icon, tinted bright yellow-orange, aligned to the icon edges and behind the counter artwork; there is no anvil overlay. Switching the glow off preserves the Shard
and its tooltip. Reforge tooltips show only the source and Shard availability, and remain hidden until reforging is unlocked. Rustbound uses the INV_Helmet_01 icon beside
Self-Found at the buff bar, followed by the normal buffs. Either prestige icon
can appear alone; native anchor changes are deferred during combat. Durability
counter tooltips suppress redundant equipment comparisons, including Shift
comparisons, and restore normal tooltip behavior when dismissed.

## Level-14 beta test

Keep Allow Item Repair off. Developer mode supplies session-only eligible test
conditions, so missing gameplay for real verification does not block the beta
loop. It never certifies or rewrites the live difficulty track, invents item GUIDs,
grants gold, or simulates repairs. Production still requires real certification.
Setting the test unlock level immediately runs the real Rustbound eligibility
function; a separate check command is optional. Status prints test eligibility
and live verification separately. Failed awards now explain the blocker.

```text
/rcreforge dev on
/rcreforge level 14
/rcreforge check
/rcreforge status
/rcreforge source equip 16 672
/rcreforge boss 672
/rcreforge inspect equip 16
```

Slot 16 is the main hand. For the first backpack slot instead:

```text
/rcreforge source bag 0 1 672
/rcreforge inspect bag 0 1
```

Assign test sources to additional carried items before repeating `boss 672`.
This uses the exact same award function as the real `BOSS_KILL` event. `check`
and `grant` both run the real Rustbound eligibility function.

At a repair vendor, run `/rcreforge api` to print build, capabilities, GUIDs,
durability, and per-item repair costs. Reforge a damaged item using its button.
Verify actual gold deduction, full durability, consumed Shard, removed Rustbound,
and unchanged difficulty certification. Test two copies of one item, slot/bag
moves, and full bags. Test Reforge All with durability below, equal to, and above
the selected threshold. Cancel a confirmation, then test insufficient funds,
closing the merchant, moving items during confirmation, and a failed API action.

Additional developer commands:

```text
/rcreforge remove equip 16
/rcreforge remove bag 0 1
/rcreforge rustbound reset
/rcreforge rustbound restore
/rcreforge reset
/rcreforge level production
/rcreforge dev off
```

`reset` clears the session's test state and level override; set `level 14` again.
`rustbound reset` resets only the session's test prestige history.
`rustbound restore` also immediately runs eligibility to show test Rustbound again,
without removing test item sources or changing their Shards. Both commands wait
for in-flight repairs and never erase production repair history. Developer mode,
test sources, and test Shards are session-only and disappear on reload. In-flight
real repair evidence persists across reload so test mode cannot erase actual repairs. Disabling
developer mode immediately returns to production data and the production level.
Real test repairs spend real gold and mark production repair/prestige history;
resetting test data cannot make the production character claim it never repaired.
Existing production Shards are not used by test awards or test reset commands.

## Integration and persistence

- `Reforge/API.lua`: Forever-dependent item scanning, cost, and repair dispatch.
  Loads before existing repair wrappers so native functions remain private.
- `Reforge/Core.lua`: eligibility, Rustbound lifecycle, GUID state, awards,
  confirmation plans, pending repairs, and exact successful-repair receipts.
- `Reforge/UI.lua`: tooltips, durability indicator, prestige indicator, merchant
  controls, and event routing.
- `Reforge/Debug.lua`: developer conditions using production functions.
- Existing `Rustcore.lua`: default threshold and guild Repair All button blocking.
- Existing `Verification/Durability.lua`: exempts only an exact authorized GUID
  and durability transition; unrelated repairs in the same scan remain violations.
- Existing `Verification/Difficulty.lua`: records observed repair history.
- Existing `Verification/Integrity.lua`: seals Reforge history, GUID state, and
  pending production transactions. Existing seal-schema migration remains in use.
- Existing durability HUD/options modules: indicator and threshold slider.

State lives at the existing character verification record's `reforge` field,
inside the existing RustcoreDB SavedVariables architecture. Persistent fields
include `everRepaired`, `rustboundEarned`, `rustboundLost`, GUID-keyed `items`, and
pending production transactions. Rustbound loss does not change difficulty status.
An authorized repair is confirmed by the same GUID and maximum durability rising
from its recorded damaged value to full durability; the native API handles gold.

## Forever API audit

Inspected the Forever branch of Blizzard's extracted UI source at commit
`966519cf0ad2c10301ea011a88c14b25697c9687` on 2026-10-01. This is source-level
verification, not a claim that secure actions have been tested on the user's build.

| Dependency | Evidence and behavior |
| --- | --- |
| Physical identity | [`C_Item.GetItemGUID(ItemLocation)`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua); runtime checks reject missing/secret GUIDs. Movement/relog stability needs client acceptance testing. |
| Equipped items | Camelot [`PaperDollFrame.lua`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua) uses equipment ItemLocations and `PickupInventoryItem`. Existing Rustcore uses `GetInventoryItemDurability`. |
| Bags | [`ContainerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua) supplies bag counts, durability and `C_Container.PickupContainerItem`. Only bags 0 through NUM_BAG_SLOTS are queried. |
| Boss completion | [`EncounterInfoDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterInfoDocumentation.lua) documents `BOSS_KILL(encounterID, encounterName)`. Only this event is used, avoiding duplicate awards through ENCOUNTER_END. No combat-log assumption. |
| Tooltip identity and hooks | [`TooltipUtil.lua`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua) uses tooltip GUIDs. `TooltipDataProcessor.AddTooltipPostCall` attaches the item section; hyperlinks without a carried physical GUID never inherit another copy's Shard. |
| Cost | [`TooltipDataRules.lua`](https://github.com/Gethe/wow-ui-source/blob/966519cf0ad2c10301ea011a88c14b25697c9687/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataRules.lua) reads `tooltipData.repairCost`. Adapter queries C_TooltipInfo first, with a hidden-tooltip fallback. No item-value-based estimate. |
| Merchant repair | Blizzard's merchant/paper-doll code uses `CanMerchantRepair`, repair cursor mode, and individual pickup functions. Adapter checks merchant, combat, cursor, cost, GUID and Shard, briefly enters repair mode, then always closes it. |
| Multiple actions per click | No source-level guarantee of server/secure-action acceptance. Prototype attempts selected individual actions synchronously in the confirmed hardware-click handler. Protected failures retain Shards and support manual retry. This remains an in-client acceptance check. |

## Automated validation

Run `lua tools/test-boss-reforging.lua` with Lua 5.1; an optional first argument
selects another addon tree, for example `release/Rustcore`. Coverage includes
unlock and prestige lifecycle, independent identical copies, bank exclusion,
movement, saturation, inclusive thresholds, stale confirmations, failed/deferred
repairs, funds/cost checks, reload reconciliation, debug isolation, actual
verification comparison, and adapter dispatch/refusal behavior.

Also run `lua tools/test-boss-reforging-ui.lua` for event routing, late merchant
loading, exact-GUID tooltips, HUD state, confirmation, and manual-button tests.
The core suite currently contains 57 assertions.

Run `lua tools/test-reforge-followup.lua` for 22 regression assertions covering the
reported unverified level-14 command sequence, diagnostic messages, unlock-gated
options, and comparison-tooltip restoration.

Run `lua tools/test-reforge-buff-layout.lua` to verify shared buff ordering,
Rustbound-only display, releasing reserved slots, no anchor drift, combat deferral,
and Edit Mode anchor changes. It also accepts an alternate addon directory.

Rustbound also appears beside Self-Found on the target frame (or on its own), governed by Target Verification. Both players need the updated addon. The existing status exchange carries Rustbound independently of Self-Found, refreshes within its 15-second query interval, and expires stale responses after 120 seconds. Older peers omit this flag and show no Rustbound. Developer-test prestige is never advertised to peers.
