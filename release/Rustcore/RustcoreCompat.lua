-- RustcoreCompat: the client-abstraction seam.
--
-- Rustcore runs on two genuinely different FrameXML lineages:
--
--   classic  Era 1.15.x and TBC Anniversary 2.5.x - flat global frame
--            names, UnitAura, UIDropDownMenu, TempEnchant1..3.
--   modern   Retail and (as of this build, on the assumption stated
--            below) WoW Forever - nested frame members with no global
--            aliases, C_UnitAuras instead of UnitAura, no UIDropDownMenu
--            at all, Edit Mode owning Blizzard frame state, and combat
--            lockdown on protected frames.
--
-- Those are too far apart to paper over with `if X then` at each call
-- site, so each lineage gets one backend file - RustcoreCompatClassic.lua
-- and RustcoreCompatModern.lua - and this file picks between them once and
-- forwards to the winner. Everything else in the addon calls
-- RustcoreCompat.* and never learns which client it is on.
--
-- WOW FOREVER: Blizzard has not published Forever's client lineage or its
-- interface number. This build assumes MODERN. If that turns out wrong the
-- fix is not a rewrite - SelectBackend below will pick the classic backend
-- on its own as soon as it sees UnitAura present and Edit Mode absent.
--
-- Both backends always ship and always load. Selection is at runtime, not
-- at packaging time, specifically because Forever's TOC flavor suffix is
-- unknown: if it falls back to Rustcore.toc rather than a flavor-specific
-- one, runtime selection still lands on the right backend.

RustcoreCompat = RustcoreCompat or {}
RustcoreCompat.backends = RustcoreCompat.backends or {}

-- ── Client identification ───────────────────────────────────────────────

-- select(4, GetBuildInfo()) is the interface/TOC number: 11509 on Era
-- 1.15.9, 20506 on TBC Anniversary 2.5.6, 110000+ on modern retail.
local interfaceVersion, buildNumber, clientVersion = 0, 0, "unknown"
if GetBuildInfo then
    local version, build, _, toc = GetBuildInfo()
    clientVersion = version or "unknown"
    buildNumber = tonumber(build) or 0
    interfaceVersion = tonumber(toc) or 0
end

-- Upper bound (exclusive) -> flavor name. Retail has used a five- then
-- six-digit interface number since 6.0, so anything at or above 60000 is
-- the modern lineage; the Classic re-releases sit in bands below that.
local FLAVOR_BY_INTERFACE = {
    { 20000, "vanilla" },
    { 30000, "tbc" },
    { 40000, "wrath" },
    { 50000, "cata" },
    { 60000, "mists" },
}

local function DetectFlavor(toc)
    if toc <= 0 then return "unknown" end
    for i = 1, #FLAVOR_BY_INTERFACE do
        if toc < FLAVOR_BY_INTERFACE[i][1] then return FLAVOR_BY_INTERFACE[i][2] end
    end
    return "retail"
end

RustcoreCompat.clientVersion = clientVersion
RustcoreCompat.buildNumber = buildNumber
RustcoreCompat.interfaceVersion = interfaceVersion
RustcoreCompat.flavor = DetectFlavor(interfaceVersion)

-- Recorded, never used for a decision. It is here so a beta tester can
-- read Forever's real value back out with /rccompat and report it, which
-- is how the constant will actually become known.
RustcoreCompat.projectID = WOW_PROJECT_ID

-- ── Capabilities ────────────────────────────────────────────────────────

local function HasFunc(namespace, key)
    return type(namespace) == "table" and type(namespace[key]) == "function"
end
RustcoreCompat.HasFunc = HasFunc

local caps = {
    containerAPI   = HasFunc(C_Container, "GetContainerNumSlots"),
    auraGlobals    = type(UnitAura) == "function",
    auraDataAPI    = HasFunc(C_UnitAuras, "GetAuraDataByIndex"),
    addonsAPI      = HasFunc(C_AddOns, "GetAddOnMetadata"),
    chatInfoAPI    = HasFunc(C_ChatInfo, "SendAddonMessage"),
    spellAPI       = HasFunc(C_Spell, "GetSpellTexture"),
    itemAPI        = HasFunc(C_Item, "GetItemGUID"),
    editMode       = _G.EditModeManagerFrame ~= nil,
    menuAPI        = HasFunc(Menu, "ModifyMenu"),
    uiDropDownMenu = type(UIDropDownMenu_Initialize) == "function"
        and type(ToggleDropDownMenu) == "function",
}
RustcoreCompat.caps = caps

-- Which lineage is this? Four independent tells, any one of which is
-- decisive, because no single one is guaranteed to survive a client the
-- addon has never seen:
--
--   EditModeManagerFrame  mainline only, since 10.0
--   Menu.ModifyMenu       mainline only, since 11.0
--   C_UnitAuras but no UnitAura  the 11.0 aura removal
--   interface number >= 60000    the numeric band
--
-- Forever is expected to trip at least the first two. If it trips none of
-- them it is a Classic-lineage client whatever its marketing says, and the
-- classic backend is genuinely the correct choice.
RustcoreCompat.isModernUI = caps.editMode
    or caps.menuAPI
    or (caps.auraDataAPI and not caps.auraGlobals)
    or RustcoreCompat.flavor == "retail"

-- ── Backend selection ───────────────────────────────────────────────────

-- Backends register themselves as they load. Selection is deferred to
-- first use rather than done here, because this file loads before either
-- backend does and nothing calls a wrapper until well after ADDON_LOADED.
function RustcoreCompat.RegisterBackend(name, backend)
    backend.name = name
    RustcoreCompat.backends[name] = backend
end

local activeBackend
local function Backend()
    if not activeBackend then
        local preferred = RustcoreCompat.isModernUI and "modern" or "classic"
        activeBackend = RustcoreCompat.backends[preferred]
            or RustcoreCompat.backends.classic
            or RustcoreCompat.backends.modern
            or {}
        RustcoreCompat.backendName = activeBackend.name or "none"
    end
    return activeBackend
end
RustcoreCompat.Backend = Backend

-- ── Frame lookup (lineage-independent) ──────────────────────────────────

-- Rustcore reaches into Blizzard's frames by name. Those names are flat
-- globals on the classic lineage and nested members with no global alias
-- on the modern one, so every lookup goes through a path that may be
-- either: a bare name is read from _G, a dotted path is walked one field
-- at a time, and anything missing returns nil instead of erroring.
function RustcoreCompat.ResolveRegion(path)
    if type(path) ~= "string" then return nil end
    if not path:find("%.", 1, false) then return _G[path] end
    local node = _G
    for segment in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[segment]
        if node == nil then return nil end
    end
    return node
end

-- First candidate that resolves wins. Also returns the path that produced
-- it, which is what /rccompat prints for bug reports.
function RustcoreCompat.ResolveFirst(candidates)
    if type(candidates) ~= "table" then return nil end
    for i = 1, #candidates do
        local region = RustcoreCompat.ResolveRegion(candidates[i])
        if region then return region, candidates[i] end
    end
    return nil
end

-- ── Protected-frame safety ──────────────────────────────────────────────

-- The modern client blocks Hide/Show/SetPoint on protected frames while in
-- combat, and an addon that tries anyway gets ADDON_ACTION_BLOCKED and a
-- tainted execution path. Callers that touch Blizzard frames ask this
-- first. The classic backend answers true unconditionally: Rustcore has
-- always done this there without incident and this is not the change to
-- start altering that behaviour in.
function RustcoreCompat.CanTouchBlizzardFrames()
    local b = Backend()
    if b.CanTouchBlizzardFrames then return b.CanTouchBlizzardFrames() end
    return true
end

-- ── Portrait art ────────────────────────────────────────────────────────

-- which is "player" or "target". Returns the frame's portrait-border
-- texture, or nil on a client whose layout this build doesn't know - in
-- which case the dragon overlay declines to draw rather than erroring.
function RustcoreCompat.PortraitTexture(which)
    local b = Backend()
    if b.PortraitTexture then return b.PortraitTexture(which) end
    return nil
end

-- ── Native buff frame ───────────────────────────────────────────────────

-- Rustcore draws its own Self-Found aura bar and suppresses Blizzard's.
-- How you suppress it differs sharply by lineage, which is most of why
-- the backend split exists at all - see each backend for the details.
function RustcoreCompat.HideNativeBuffFrame()
    local b = Backend()
    if b.HideNativeBuffFrame then return b.HideNativeBuffFrame() end
end

function RustcoreCompat.ShowNativeBuffFrame()
    local b = Backend()
    if b.ShowNativeBuffFrame then return b.ShowNativeBuffFrame() end
end

-- ── Auras ───────────────────────────────────────────────────────────────

-- Classic-tuple aura read: name, icon, count, dispelType, duration,
-- expirationTime, ... Both backends return this shape regardless of what
-- the underlying client offers, so call sites never changed.
function RustcoreCompat.GetAura(unit, index, filter)
    local b = Backend()
    if b.GetAura then return b.GetAura(unit, index, filter) end
    return nil
end

-- Point a tooltip at aura `index` on `unit`. Split out because the modern
-- client prefers aura-instance IDs over indices and the classic one has
-- only SetUnitAura.
function RustcoreCompat.SetTooltipAura(tooltip, unit, index, filter)
    local b = Backend()
    if b.SetTooltipAura then return b.SetTooltipAura(tooltip, unit, index, filter) end
    return false
end

-- ── Containers ──────────────────────────────────────────────────────────

-- Highest bag index to walk, inclusive of 0 (the backpack). Retail added a
-- reagent bag after the four normal ones and it holds real items, so a
-- hardcoded 0..4 silently skips it - a hole in exactly what this addon
-- exists to verify.
function RustcoreCompat.MaxBagIndex()
    local b = Backend()
    if b.MaxBagIndex then return b.MaxBagIndex() end
    return NUM_BAG_SLOTS or 4
end

function RustcoreCompat.GetContainerNumSlots(bag)
    return Backend().GetContainerNumSlots(bag)
end

function RustcoreCompat.GetContainerItemLink(bag, slot)
    return Backend().GetContainerItemLink(bag, slot)
end

-- Returns link, count - the only two fields Rustcore has ever wanted out
-- of GetContainerItemInfo, normalised across the tuple and table forms.
function RustcoreCompat.GetContainerItemLinkAndCount(bag, slot)
    return Backend().GetContainerItemLinkAndCount(bag, slot)
end

function RustcoreCompat.PickupContainerItem(bag, slot)
    return Backend().PickupContainerItem(bag, slot)
end

-- ── Lineage-independent wrappers ────────────────────────────────────────

-- Nothing below this line needs to know which backend is active: each
-- wrapper picks its own form from whatever the client actually exports,
-- so duplicating them into the two backends would gain nothing.

function RustcoreCompat.GetAddOnMetadata(addon, field)
    if HasFunc(C_AddOns, "GetAddOnMetadata") then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    if GetAddOnMetadata then return GetAddOnMetadata(addon, field) end
    return nil
end

function RustcoreCompat.SendAddonMessage(prefix, msg, channel, target)
    if HasFunc(C_ChatInfo, "SendAddonMessage") then
        return C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    end
    if SendAddonMessage then
        return SendAddonMessage(prefix, msg, channel, target)
    end
end

function RustcoreCompat.RegisterAddonMessagePrefix(prefix)
    if HasFunc(C_ChatInfo, "RegisterAddonMessagePrefix") then
        return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    end
    if RegisterAddonMessagePrefix then
        return RegisterAddonMessagePrefix(prefix)
    end
end

function RustcoreCompat.GetSpellTexture(spell)
    if HasFunc(C_Spell, "GetSpellTexture") then
        return C_Spell.GetSpellTexture(spell)
    end
    if GetSpellTexture then return GetSpellTexture(spell) end
    return nil
end

-- ── Items and inventory ─────────────────────────────────────────────────

-- These were bare global calls until WoW Forever proved they could not
-- stay that way: the modern client moved item lookups into C_Item and
-- dropped the flat forms, so Rustcore.lua's GetItemInfo(link) threw
-- "attempt to call a nil value" the instant the player entered combat -
-- which also silently emptied the combat snapshot, so death then had
-- nothing to take.
--
-- The GetInventoryItem* family has not moved on any client Rustcore
-- targets. They are wrapped anyway so that every call site has one habit
-- instead of three, and so a future removal is a change here rather than
-- a hunt through fourteen files.
--
-- None of these can throw. A missing API returns nil, which callers
-- already handle: GetItemInfo returns nil for an item the client has not
-- cached yet, so "no data" was always a reachable answer.

-- Used wherever an icon is required and the item cannot supply one.
RustcoreCompat.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function RustcoreCompat.GetItemInfo(item)
    if HasFunc(C_Item, "GetItemInfo") then
        return C_Item.GetItemInfo(item)
    end
    if GetItemInfo then return GetItemInfo(item) end
    return nil
end

-- GetItemIconByID is the modern name and takes an ID, link or name just
-- as the flat form did, so callers need no conversion.
function RustcoreCompat.GetItemIcon(item)
    if HasFunc(C_Item, "GetItemIconByID") then
        return C_Item.GetItemIconByID(item)
    end
    if GetItemIcon then return GetItemIcon(item) end
    return nil
end

-- Falls back to white rather than nil: callers feed this straight into
-- SetTextColor, and three nils there is an error, not a dim colour.
function RustcoreCompat.GetItemQualityColor(quality)
    if HasFunc(C_Item, "GetItemQualityColor") then
        return C_Item.GetItemQualityColor(quality)
    end
    if GetItemQualityColor then return GetItemQualityColor(quality) end
    return 1, 1, 1
end

function RustcoreCompat.GetInventoryItemLink(unit, slot)
    if GetInventoryItemLink then return GetInventoryItemLink(unit, slot) end
    return nil
end

function RustcoreCompat.GetInventoryItemDurability(slot)
    if GetInventoryItemDurability then
        return GetInventoryItemDurability(slot)
    end
    return nil
end

function RustcoreCompat.GetInventoryItemTexture(unit, slot)
    if GetInventoryItemTexture then
        return GetInventoryItemTexture(unit, slot)
    end
    return nil
end

function RustcoreCompat.GetInventoryItemID(unit, slot)
    if GetInventoryItemID then return GetInventoryItemID(unit, slot) end
    return nil
end

-- Temporary weapon enchants (poisons, oils, sharpening stones). Still a
-- flat global everywhere Rustcore runs today, but it feeds the same buff
-- row as the item lookups above and has no business being the one bare
-- call left in that path. Returns "no enchant" rather than throwing.
function RustcoreCompat.GetWeaponEnchantInfo()
    if GetWeaponEnchantInfo then return GetWeaponEnchantInfo() end
    return false, nil, nil, false, nil, nil
end

-- ── Diagnostics ─────────────────────────────────────────────────────────

-- /rccompat exists for one job: the first time someone logs into a WoW
-- Forever realm with Rustcore installed, this prints everything needed to
-- decide what the addon must do differently - without a debugger and
-- without a second addon. The interface number on the first line is the
-- value that needs to go into the TOC.
local function PrintCompatReport()
    local b = Backend()
    print("|cffffcc00Rustcore compat|r  client " .. tostring(clientVersion)
        .. "  build " .. tostring(buildNumber)
        .. "  interface " .. tostring(interfaceVersion))
    print("  flavor: " .. tostring(RustcoreCompat.flavor)
        .. "   projectID: " .. tostring(RustcoreCompat.projectID)
        .. "   backend: |cff44ff44" .. tostring(b.name or "none") .. "|r")

    local names = {}
    for name in pairs(caps) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        print("  " .. (caps[names[i]] and "|cff44ff44yes|r" or "|cffff4444NO |r")
            .. "  " .. names[i])
    end

    -- The frames Rustcore does surgery on. A "missing" line here is the
    -- single most useful thing a beta report can contain.
    local FRAMES = {
        "PlayerFrame", "TargetFrame", "BuffFrame", "DurabilityFrame",
        "MerchantFrame",
        "PlayerFrameTexture",
        "PlayerFrame.PlayerFrameContainer.FrameTexture",
        "TargetFrameTextureFrameTexture",
        "TargetFrame.TargetFrameContainer.FrameTexture",
        "TempEnchant1",
        "BuffFrame.AuraContainer",
        "TemporaryEnchantFrame",
    }
    for i = 1, #FRAMES do
        print("  " .. (RustcoreCompat.ResolveRegion(FRAMES[i])
            and "|cff44ff44found  |r" or "|cffff4444missing|r") .. " " .. FRAMES[i])
    end
end

SLASH_RCCOMPAT1 = "/rccompat"
SlashCmdList["RCCOMPAT"] = PrintCompatReport
