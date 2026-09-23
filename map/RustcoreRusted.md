# RustcoreRusted.lua — 454 lines

Top-level definitions in `dist/forever/Rustcore/RustcoreRusted.lua`.

```
27:local function BagGetNumSlots(bag)
31:local function BagGetItemLink(bag, slot)
35:local function BagPickupItem(bag, slot)
41:local function GetItemID(link)
46:local function IsDismissed(itemID)
50:local function MarkDismissed(itemID)
55:local function IsAlreadyPending(itemID)
64:local function FindAndPickupItem(link)
91:local function UpdateSubLabel(f, count)
102:local function ClearRustedIcons()
113:local function PopulateRustedIcons(items, skipAnim)
271:local function BuildRustedFrame()
346:function RustcoreRusted.GetRustedFrame()
352:local function LayoutBothFrames()
365:function RustcoreRusted.ExecuteDeletion()
389:local function ScanAndQueue()
407:local function TryShowRustedFrame(hasNewItems)
429:local function ScanBrokenItems()
```
