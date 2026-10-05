# RustcoreBroadcast.lua — 547 lines

Top-level definitions in `dist/forever/Rustcore/RustcoreBroadcast.lua`.

```
48:local function GetActiveChatTypes()
62:function RustcoreBroadcast.SendAddonMessage(prefix, msg)
74:local function ClassColorCode(class)
80:local function IsValidClass(class)
86:local function GetChannelIndex()
93:local function HideChannelFromChatFrames()
102:local function NormalizeName(name)
112:local function SanitizeField(value, maxBytes)
123:local function NormalizeItemLink(link)
142:local function EnsureRealmChannel()
155:local function FindHighestIlvlItem(items)
176:local function BuildDeathData(markedItems, deathSource)
204:local function SerializeDeathData(d)
266:local function QueueRealmMessage(msg)
276:local function FlushOneRealmMessage()
298:function RustcoreBroadcast.QueueChatMessage(message, chatType, target)
314:local function FlushOneQueuedChatMessage()
334:local function InstallInputHooks()
350:local function Send(d)
363:function RustcoreBroadcast.Announce(markedItems, deathSource)
379:local function Parse(msgStr)
402:local function IsFresh(d)
414:local function IsValidEntry(d)
425:local function SenderAllowed(transport, sender, minInterval)
434:local function Display(d)
524:function RustcoreBroadcast.Init()
```
