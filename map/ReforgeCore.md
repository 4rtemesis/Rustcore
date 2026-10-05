# Reforge/Core.lua — 328 lines

Top-level definitions in `dist/forever/Rustcore/Reforge/Core.lua`.

```
9:local function NewState(everRepaired)
14:function R.State()
26:function R.IsDebug() return debugState ~= nil end
27:function R.UnlockLevel() return debugLevel or R.REFORGE_UNLOCK_LEVEL end
28:function R.LiveVerified()
32:function R.Verified()
37:function R.AtUnlockLevel()
40:function R.UnlockReason()
51:function R.Unlocked()
54:function R.Changed()
59:function R.CheckRustbound()
72:function R.HasRustbound()
77:function R.NoteRepair()
90:function R.Source(item)
96:function R.SourceName(id)
99:function R.HasShard(item)
104:function R.AwardBoss(id)
129:function R.Find(guid)
132:function R.Threshold()
135:function R.Plan()
153:local function Complete(item, request)
179:function R.AcceptVerifiedRepair(was, now)
194:function R.Repair(guid, expectedCost)
228:function R.Execute(plan)
244:function R.Observe()
278:function R.LoadPending()
289:function R.DebugMode(enabled)
296:function R.DebugLevel(level)
306:function R.DebugSource(item, boss)
314:function R.DebugResetRustbound()
321:function R.DebugRestoreRustbound()
326:function R.DebugRemoveShard(item)
```
