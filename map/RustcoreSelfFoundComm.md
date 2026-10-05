# RustcoreSelfFoundComm.lua — 351 lines

Top-level definitions in `dist/forever/Rustcore/RustcoreSelfFoundComm.lua`.

```
43:local function NormalizeName(name)
51:local function GetUnitFullName(unit)
74:local function IsQueryable(unit)
82:local function SendMessage(msg, whisperTarget)
99:local function IsVerifiedFresh(name)
104:local function IsSeenFresh(name)
114:function RustcoreSelfFoundComm.GetKnownDifficulty(name)
120:function RustcoreSelfFoundComm.IsKnownSelfFound(name)
125:function RustcoreSelfFoundComm.IsKnownRustbound(name)
132:local function RequestStatus(fullName)
143:local function HandleQuery(name, sender)
166:local function HandleResponse(name, verifiedFlag, difficulty, sender, rustboundFlag)
195:local function EnsureOverlay(frame)
209:local function UpdateFrameOverlay(frame, unit)
245:function RustcoreSelfFoundComm.RefreshOverlays()
254:local function OnUnitChanged(unit)
274:local function OnMouseoverChanged()
282:local function RefreshWatchedUnits()
```
