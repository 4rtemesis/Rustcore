-- RustcoreDiag: a /rcdiag readout of what this client actually exports.
--
-- The compat layer branches on a handful of APIs and then picks a backend
-- once, at first use. Everything downstream follows from that one choice:
-- which aura call is made, whether a tooltip can be filled, whether an
-- item lookup returns anything at all. On a client whose lineage Blizzard
-- has not published, that choice cannot be read out of the source, so this
-- asks the running client instead of guessing.
--
-- Nothing here mutates anything. Every line is a type() or a plain read,
-- so it is safe to run in combat, while dead, or mid-pull.

local function Line(label, value)
    DEFAULT_CHAT_FRAME:AddMessage("  " .. label .. ": |cffffff00"
        .. tostring(value) .. "|r")
end

-- Reading a field off a missing table is the common case here, not an
-- error case, so the absent container answers for itself.
local function TypeOf(container, name)
    if container == nil then return "-- no container --" end
    local ok, value = pcall(function() return container[name] end)
    if not ok then return "unreadable" end
    return type(value)
end

local function GlobalType(name)
    return type(rawget(_G, name))
end

local function Report()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Rustcore diagnostic|r")

    if not RustcoreCompat then
        Line("compat", "NOT LOADED")
        return
    end

    -- backendName is only populated once something has called a wrapper,
    -- so force the selection first rather than reporting "none" purely
    -- because nothing happened to need it yet this session.
    if RustcoreCompat.Backend then RustcoreCompat.Backend() end

    local _, build, _, iface = GetBuildInfo()
    Line("build", tostring(build) .. " interface " .. tostring(iface))
    Line("flavor", RustcoreCompat.flavor)
    Line("isModernUI", RustcoreCompat.isModernUI)
    Line("backend", RustcoreCompat.backendName)

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-- lineage tells --|r")
    Line("EditModeManagerFrame", GlobalType("EditModeManagerFrame"))
    Line("Menu.ModifyMenu", TypeOf(rawget(_G, "Menu"), "ModifyMenu"))
    Line("InCombatLockdown", GlobalType("InCombatLockdown"))

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-- items --|r")
    Line("GetItemInfo", GlobalType("GetItemInfo"))
    Line("C_Item.GetItemInfo", TypeOf(rawget(_G, "C_Item"), "GetItemInfo"))
    Line("C_Item.GetItemIconByID",
        TypeOf(rawget(_G, "C_Item"), "GetItemIconByID"))
    Line("GetInventoryItemTexture", GlobalType("GetInventoryItemTexture"))
    Line("GetWeaponEnchantInfo", GlobalType("GetWeaponEnchantInfo"))

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-- auras --|r")
    Line("UnitAura", GlobalType("UnitAura"))
    Line("C_UnitAuras.GetAuraDataByIndex",
        TypeOf(rawget(_G, "C_UnitAuras"), "GetAuraDataByIndex"))
    Line("GameTooltip.SetUnitAura", TypeOf(GameTooltip, "SetUnitAura"))
    Line("GameTooltip.SetUnitBuff", TypeOf(GameTooltip, "SetUnitBuff"))
    Line("GameTooltip.SetUnitDebuff", TypeOf(GameTooltip, "SetUnitDebuff"))
    Line("CancelUnitBuff", GlobalType("CancelUnitBuff"))

    -- The self-found buff row renders a flat colour block when a slot
    -- texture comes back nil, so print the literal return rather than a
    -- type: "nil" and a real path are the two answers that matter.
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-- weapon slot textures --|r")
    Line("mainhand(16)", RustcoreCompat.GetInventoryItemTexture("player", 16))
    Line("offhand(17)", RustcoreCompat.GetInventoryItemTexture("player", 17))
    Line("FALLBACK_ICON", RustcoreCompat.FALLBACK_ICON)

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-- frames --|r")
    Line("BuffFrame", GlobalType("BuffFrame"))
    Line("TempEnchant1", GlobalType("TempEnchant1"))
    Line("TargetFrameBuff1", GlobalType("TargetFrameBuff1"))
    Line("PlayerFrameTexture", GlobalType("PlayerFrameTexture"))
end

SLASH_RCDIAG1 = "/rcdiag"
SlashCmdList["RCDIAG"] = Report

Rustcore = Rustcore or {}
Rustcore.Diagnostic = Report
