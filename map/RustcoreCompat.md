# RustcoreCompat.lua — 377 lines

Top-level definitions in `dist/forever/Rustcore/RustcoreCompat.lua`.

```
55:local function DetectFlavor(toc)
75:local function HasFunc(namespace, key)
102:function RustcoreCompat.CanUseCombatLog()
133:function RustcoreCompat.RegisterBackend(name, backend)
139:local function Backend()
159:function RustcoreCompat.ResolveRegion(path)
173:function RustcoreCompat.ResolveFirst(candidates)
190:function RustcoreCompat.CanTouchBlizzardFrames()
201:function RustcoreCompat.PortraitTexture(which)
212:function RustcoreCompat.HideNativeBuffFrame()
217:function RustcoreCompat.ShowNativeBuffFrame()
227:function RustcoreCompat.GetAura(unit, index, filter)
236:function RustcoreCompat.SetTooltipAura(tooltip, unit, index, filter)
248:function RustcoreCompat.MaxBagIndex()
254:function RustcoreCompat.GetContainerNumSlots(bag)
258:function RustcoreCompat.GetContainerItemLink(bag, slot)
264:function RustcoreCompat.GetContainerItemLinkAndCount(bag, slot)
268:function RustcoreCompat.PickupContainerItem(bag, slot)
278:function RustcoreCompat.GetAddOnMetadata(addon, field)
286:function RustcoreCompat.SendAddonMessage(prefix, msg, channel, target)
295:function RustcoreCompat.RegisterAddonMessagePrefix(prefix)
304:function RustcoreCompat.GetSpellTexture(spell)
317:function RustcoreCompat.GetItemInfo(item)
325:function RustcoreCompat.GetItemIcon(item)
340:local function PrintCompatReport()
```
