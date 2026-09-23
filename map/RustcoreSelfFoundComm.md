# RustcoreSelfFoundComm.lua — 341 lines

Top-level definitions in `dist/forever/Rustcore/RustcoreSelfFoundComm.lua`.

```
42:local function NormalizeName(name)
50:local function GetUnitFullName(unit)
73:local function IsQueryable(unit)
81:local function SendMessage(msg, whisperTarget)
98:local function IsVerifiedFresh(name)
103:local function IsSeenFresh(name)
113:function RustcoreSelfFoundComm.GetKnownDifficulty(name)
119:function RustcoreSelfFoundComm.IsKnownSelfFound(name)
126:local function RequestStatus(fullName)
137:local function HandleQuery(name, sender)
157:local function HandleResponse(name, verifiedFlag, difficulty, sender)
185:local function EnsureOverlay(frame)
199:local function UpdateFrameOverlay(frame, unit)
235:function RustcoreSelfFoundComm.RefreshOverlays()
244:local function OnUnitChanged(unit)
264:local function OnMouseoverChanged()
272:local function RefreshWatchedUnits()
```
