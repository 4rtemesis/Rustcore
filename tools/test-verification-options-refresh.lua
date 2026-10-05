local function read(path)
 local f=assert(io.open('dist/Forever/Rustcore/'..path,'rb'))
 local s=f:read('*a'):gsub('\r\n','\n'); f:close(); return s
end
local source=read('RustcoreOptions.lua')
local a=assert(source:find('    f:SetScript("OnShow", function(self)',1,true))
local b=assert(source:find('    f:SetScript("OnUpdate"',a,true))
local callbacks={}
local f={SetScript=function(_,event,fn) callbacks[event]=fn end}
local refreshed,requested,composed=0,0,0
RustcoreVerification={ComposeAll=function() composed=composed+1 end,
 Time={Request=function() requested=requested+1 end}}
f.refreshVerification=function() refreshed=refreshed+1 end
assert(loadstring('local f,RefreshAllControls,RefreshCombatLockState=...\n'..source:sub(a,b-1)))(f,function() end,function() end)
callbacks.OnShow(f); callbacks.OnShow(f)
assert(refreshed==2 and requested==2 and composed==2, 'reopening options skipped verification refresh')
-- Server replies are displayed after all reconciliation handlers have run.
source=read('Verification/UI.lua')
a=assert(source:find('    page:RegisterEvent("TIME_PLAYED_MSG")',1,true))
b=assert(source:find('\n    UI.Refresh()\n    return UI.Refresh',a,true))
local visible=true
local page={RegisterEvent=function() end,SetScript=f.SetScript,IsVisible=function() return visible end}
local queued
C_Timer={After=function(_,fn) queued=fn end}
local UI={Refresh=function() refreshed=refreshed+1 end}
assert(loadstring('local page,V,UI=...\n'..source:sub(a,b-1)))(page,RustcoreVerification,UI)
callbacks.OnEvent(); assert(refreshed==2); queued(); assert(refreshed==3)
visible=false; callbacks.OnEvent(); queued(); assert(refreshed==3)
print('Options reopen refreshes verification and requests played; visible page refreshes after the reply')
