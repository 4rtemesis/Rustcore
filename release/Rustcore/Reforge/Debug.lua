local R, A = RustcoreReforge, RustcoreReforgeAPI
local function Say(message) print("Rustcore Reforge: " .. tostring(message)) end
local function ReportEligibility()
    local eligible, reason = R.CheckRustbound()
    Say(eligible and "Rustbound earned (developer test)." or ("Rustbound unavailable: " .. tostring(reason)))
end
local function Item(kind, first, second)
    if kind == "equip" then return A.Read(nil, tonumber(first)) end
    if kind == "bag" then return A.Read(tonumber(first), tonumber(second)) end
end
SLASH_RUSTCOREREFORGE1 = "/rcreforge"
SlashCmdList.RUSTCOREREFORGE = function(message)
    local args = {}
    for word in message:gmatch("%S+") do args[#args + 1] = word:lower() end
    local cmd = args[1]
    if cmd == "dev" then
        if args[2] ~= "on" and args[2] ~= "off" then Say("Use dev on or dev off."); return end
        local ok, reason = R.DebugMode(args[2] == "on")
        Say(ok and ("Developer mode " .. args[2] .. ". Test state lasts until reload; repairs spend real gold and affect real gear.") or reason)
        if ok and R.IsDebug() then
            Say("Using test eligibility. Live difficulty verification is unchanged. Set the test unlock level with /rcreforge level 14.")
        end
        return
    end
    if not R.IsDebug() then Say("Developer commands require /rcreforge dev on."); return end
    if cmd == "level" then
        local level = tonumber(args[2])
        if args[2] == "production" then R.DebugLevel(nil)
        elseif level and level >= 1 and level <= R.REFORGE_UNLOCK_LEVEL then R.DebugLevel(math.floor(level))
        else Say("Use level 14 or level production."); return end
        Say("Unlock level: " .. R.UnlockLevel())
        ReportEligibility()
    elseif cmd == "check" or cmd == "grant" then
        ReportEligibility()
    elseif cmd == "rustbound" and (args[2] == "reset" or args[2] == "restore") then
        local restore = args[2] == "restore"
        local ok, reason
        if restore then ok, reason = R.DebugRestoreRustbound()
        else ok, reason = R.DebugResetRustbound() end
        Say(ok and (restore and "Test Rustbound restored." or "Test Rustbound history reset.") or reason)
    elseif cmd == "status" then
        local state = R.State()
        Say("ever repaired=" .. tostring(state.everRepaired) .. " earned=" .. tostring(state.rustboundEarned)
            .. " permanently lost=" .. tostring(state.rustboundLost))
        Say("level=" .. tostring(RustcoreVerification.GetPlayerLevel()) .. " unlock=" .. R.UnlockLevel()
            .. " test eligibility=" .. tostring(R.Verified()) .. " live verified=" .. tostring(R.LiveVerified()))
        if R.UnlockReason() then Say(R.UnlockReason()) end
    elseif cmd == "boss" then
        local count, reason = R.AwardBoss(tonumber(args[2]))
        Say("Reforge Shards awarded: " .. count)
        if reason then Say(reason) end
    elseif cmd == "source" or cmd == "inspect" or cmd == "remove" then
        local item = Item(args[2], args[3], args[4])
        if not item then Say("No readable physical item. Use equip SLOT or bag BAG SLOT."); return end
        if cmd == "source" then
            local boss = tonumber(args[args[2] == "equip" and 4 or 5])
            if not boss then Say("Provide an encounter ID, for example 672."); return end
            R.DebugSource(item, boss)
        elseif cmd == "remove" then R.DebugRemoveShard(item) end
        Say(item.guid .. " item=" .. item.id .. " source=" .. tostring(R.Source(item)) .. " Reforge Shard=" .. tostring(R.HasShard(item)))
    elseif cmd == "reset" then
        local ok, reason = R.DebugMode(true); Say(ok and "Test data reset. Set the test level again." or reason)
    elseif cmd == "api" then A.Diagnose()
    else
        Say("dev on|off; level 14|production; check; grant; rustbound reset|restore; status; boss ID; reset; api")
        Say("source equip SLOT BOSS; source bag BAG SLOT BOSS; inspect equip SLOT; inspect bag BAG SLOT; remove equip SLOT")
    end
    R.Refresh()
end
