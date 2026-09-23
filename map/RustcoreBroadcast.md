# RustcoreBroadcast.lua — 526 lines

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
124:local function IsValidItemLink(link)
129:local function EnsureRealmChannel()
142:local function FindHighestIlvlItem(items)
158:local function BuildDeathData(markedItems, deathSource)
186:local function SerializeDeathData(d)
244:local function QueueRealmMessage(msg)
254:local function FlushOneRealmMessage()
276:function RustcoreBroadcast.QueueChatMessage(message, chatType, target)
292:local function FlushOneQueuedChatMessage()
312:local function InstallInputHooks()
328:local function Send(d)
341:function RustcoreBroadcast.Announce(markedItems, deathSource)
357:local function Parse(msgStr)
381:local function IsFresh(d)
393:local function IsValidEntry(d)
404:local function SenderAllowed(transport, sender, minInterval)
413:local function Display(d)
503:function RustcoreBroadcast.Init()
```
