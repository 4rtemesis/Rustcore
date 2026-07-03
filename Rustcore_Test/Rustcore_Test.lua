-- Rustcore_Test: In-game test harness
-- /rctest        run all tests
-- /rctest dur    run durability tests only
-- /rctest set    run settings tests only

local RC_VERSION = select(4, GetBuildInfo())  -- numeric interface version

local suite = {}
local results = {}

-- ── Reporter ──────────────────────────────────────────────────────────────────

local function Pass(name)
    results[#results + 1] = { ok = true,  name = name }
end

local function Fail(name, reason)
    results[#results + 1] = { ok = false, name = name, reason = reason }
end

local function Assert(cond, name, reason)
    if cond then Pass(name) else Fail(name, reason or "assertion failed") end
end

local function Eq(a, b, name)
    if a == b then
        Pass(name)
    else
        Fail(name, "expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

local function Near(a, b, tolerance, name)
    tolerance = tolerance or 0.001
    if math.abs(a - b) <= tolerance then
        Pass(name)
    else
        Fail(name, string.format("expected ~%.4f, got %.4f", b, a))
    end
end

local function PrintResults()
    local passed, failed = 0, 0
    for _, r in ipairs(results) do
        if r.ok then
            passed = passed + 1
            print("|cff44ff44[PASS]|r " .. r.name)
        else
            failed = failed + 1
            print("|cffff4444[FAIL]|r " .. r.name .. " — " .. (r.reason or "?"))
        end
    end
    print(string.rep("─", 40))
    local col = failed == 0 and "|cff44ff44" or "|cffff4444"
    print(col .. "Results:|r " .. passed .. " passed, " .. failed .. " failed"
          .. "  |cffa0a0a0(interface " .. RC_VERSION .. ")|r")
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Replicate GetDurabilityColor logic from RustcoreDurability.lua
-- (function is local there, so we test by re-implementing and cross-checking
--  the documented spec: green@100%, yellow@50%, red@0%)
local function SimColor(current, maximum)
    if maximum == 0 or current == 0 then return 1, 0, 0 end
    local pct = math.min(1, current / maximum)
    if pct >= 0.5 then
        return 2 * (1 - pct), 1, 0
    else
        return 1, 2 * pct, 0
    end
end

-- ── Test suites ───────────────────────────────────────────────────────────────

suite.modules = function()
    Assert(Rustcore            ~= nil, "Rustcore core present")
    Assert(RustcoreUI          ~= nil, "RustcoreUI present")
    Assert(RustcoreOptions     ~= nil, "RustcoreOptions present")
    Assert(RustcoreDurability  ~= nil, "RustcoreDurability present")
    Assert(RustcoreTheme       ~= nil, "RustcoreTheme present")
    Assert(RustcoreBroadcast   ~= nil, "RustcoreBroadcast present")

    Assert(type(RustcoreDurability.Init)    == "function", "RustcoreDurability.Init callable")
    Assert(type(RustcoreDurability.Refresh) == "function", "RustcoreDurability.Refresh callable")
    Assert(type(RustcoreOptions.Toggle)     == "function", "RustcoreOptions.Toggle callable")
end

suite.settings = function()
    -- Defaults
    Eq(Rustcore.GetSetting("showDurabilityHUD"),   true,  "showDurabilityHUD default=true")
    Eq(Rustcore.GetSetting("showAllDurability"),   false, "showAllDurability default=false")
    Assert(Rustcore.GetSetting("difficulty") >= 1
        and Rustcore.GetSetting("difficulty") <= 5,       "difficulty in 1–5")

    -- Round-trip for showAllDurability
    local prev = Rustcore.GetSetting("showAllDurability")
    Rustcore.SetSetting("showAllDurability", true)
    Eq(Rustcore.GetSetting("showAllDurability"), true,  "showAllDurability set true")
    Rustcore.SetSetting("showAllDurability", false)
    Eq(Rustcore.GetSetting("showAllDurability"), false, "showAllDurability set false")
    Rustcore.SetSetting("showAllDurability", prev)      -- restore

    -- Round-trip for showDurabilityHUD
    local prevHUD = Rustcore.GetSetting("showDurabilityHUD")
    Rustcore.SetSetting("showDurabilityHUD", false)
    Eq(Rustcore.GetSetting("showDurabilityHUD"), false, "showDurabilityHUD set false")
    Rustcore.SetSetting("showDurabilityHUD", true)
    Eq(Rustcore.GetSetting("showDurabilityHUD"), true,  "showDurabilityHUD set true")
    Rustcore.SetSetting("showDurabilityHUD", prevHUD)   -- restore

    -- Old key should not survive migration
    Assert(RustcoreDB.showDurabilityTooltip == nil, "showDurabilityTooltip migrated away")
end

suite.durability = function()
    -- Color at 100%: expect green (r≈0, g=1, b=0)
    local r, g, b = SimColor(100, 100)
    Near(r, 0, 0.01, "color@100% r≈0")
    Near(g, 1, 0.01, "color@100% g=1")
    Near(b, 0, 0.01, "color@100% b=0")

    -- Color at 50%: expect yellow (r=1, g=1, b=0)
    r, g, b = SimColor(50, 100)
    Near(r, 1, 0.01, "color@50% r=1")
    Near(g, 1, 0.01, "color@50% g=1")
    Near(b, 0, 0.01, "color@50% b=0")

    -- Color at 0%: expect red (r=1, g=0, b=0)
    r, g, b = SimColor(0, 100)
    Near(r, 1, 0.01, "color@0% r=1")
    Near(g, 0, 0.01, "color@0% g=0")
    Near(b, 0, 0.01, "color@0% b=0")

    -- Color at 25%: r=1, g between 0 and 0.5
    r, g, b = SimColor(25, 100)
    Near(r, 1,   0.01, "color@25% r=1")
    Assert(g > 0 and g < 0.6, "color@25% g in yellow→red range")

    -- Broken item (max=0): should return red
    r, g, b = SimColor(0, 0)
    Near(r, 1, 0.01, "color max=0 r=1")
    Near(g, 0, 0.01, "color max=0 g=0")

    -- HUD frame should exist after Init (named frame)
    Assert(_G["RustcoreDurabilityHUD"] ~= nil, "RustcoreDurabilityHUD frame created")

    -- Refresh should not error
    local ok, err = pcall(function() RustcoreDurability.Refresh() end)
    Assert(ok, "RustcoreDurability.Refresh() no error", err)
end

suite.api = function()
    -- Core WoW APIs present in both Classic and TBC
    Assert(GetInventoryItemDurability ~= nil, "GetInventoryItemDurability available")
    Assert(GetInventoryItemLink       ~= nil, "GetInventoryItemLink available")
    Assert(GetItemInfo                ~= nil, "GetItemInfo available")
    Assert(UnitGUID                   ~= nil, "UnitGUID available")
    Assert(C_Timer                    ~= nil, "C_Timer available")

    -- Version-specific info (not pass/fail, just printed)
    if C_Container and C_Container.GetContainerNumSlots then
        print("|cffffff00[INFO]|r C_Container API present (TBC+ path active)")
    else
        print("|cffffff00[INFO]|r Legacy GetContainerNumSlots API active (Classic path)")
    end

    -- Addon asset path helper
    Assert(type(Rustcore.GetAssetPath("Font/BPpong.otf")) == "string",
           "Rustcore.GetAssetPath returns string")

    -- Character key available
    Assert(type(Rustcore.GetCharacterKey()) == "string", "GetCharacterKey returns string")
    Assert(#Rustcore.GetCharacterKey() > 0,              "GetCharacterKey non-empty")
end

-- ── Runner ────────────────────────────────────────────────────────────────────

local SUITE_MAP = {
    modules    = suite.modules,
    mod        = suite.modules,
    settings   = suite.settings,
    set        = suite.settings,
    durability = suite.durability,
    dur        = suite.durability,
    api        = suite.api,
}

local function RunSuites(filter)
    wipe(results)
    print("|cffff4444Rustcore Test|r ─── interface " .. RC_VERSION .. " ───")
    if filter and SUITE_MAP[filter] then
        print("Running suite: " .. filter)
        SUITE_MAP[filter]()
    else
        suite.modules()
        suite.settings()
        suite.durability()
        suite.api()
    end
    PrintResults()
end

SLASH_RCTEST1 = "/rctest"
SlashCmdList["RCTEST"] = function(arg)
    local sub = arg and arg:match("^%s*(%S+)") or nil
    RunSuites(sub)
end

-- Auto-run once everything has loaded (1s after Rustcore's ADDON_LOADED)
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(2, function()
        print("|cffff4444Rustcore Test|r loaded — /rctest to run tests")
    end)
end)
