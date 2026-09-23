-- RustcoreCompatModern: the retail / WoW Forever backend.
--
-- Built on the assumption that Forever ships the modern client. That is
-- not something Blizzard has confirmed, but it is what this build targets;
-- if it turns out to be a Classic-lineage client instead, RustcoreCompat's
-- SelectBackend will simply never choose this file and nothing here runs.
--
-- What actually differs from the classic lineage, and why each one needed
-- code rather than a rename:
--
--   Frame names   Blizzard nested the unit-frame regions in 10.0 and left
--                 no global aliases, so PlayerFrameTexture and
--                 TargetFrameTextureFrameTexture simply do not exist.
--   Auras         UnitAura was removed in 11.0. C_UnitAuras returns a
--                 table where the old API returned a tuple.
--   Combat        Hide/Show/SetPoint on a protected frame during combat is
--                 blocked outright and taints the calling path, so every
--                 Blizzard-frame mutation has to ask permission first.
--   Edit Mode     Owns BuffFrame and DurabilityFrame state and will fight
--                 anything that hides them the heavy-handed way, which is
--                 why suppression here is alpha-based rather than :Hide().
--   Temp enchants TempEnchant1..3 are not reliably global here, so they
--                 are resolved through candidate paths and skipped when
--                 absent instead of assumed.

local backend = {}

-- ── Protected frames ────────────────────────────────────────────────────

-- Callers ask this before touching anything of Blizzard's. Returning false
-- in combat is not a failure mode to work around - it is the correct
-- answer, and callers are expected to simply defer.
function backend.CanTouchBlizzardFrames()
    if InCombatLockdown and InCombatLockdown() then return false end
    return true
end

-- ── Portrait art ────────────────────────────────────────────────────────

-- Ordered most- to least-likely. The flat classic names are kept at the
-- end deliberately: if Forever turns out to be a modern client that still
-- exports them, this picks them up without another code change.
local PORTRAIT_TEXTURES = {
    player = {
        "PlayerFrame.PlayerFrameContainer.FrameTexture",
        "PlayerFrame.PlayerFrameContainer.PlayerPortraitCornerIcon",
        "PlayerFrameTexture",
    },
    target = {
        "TargetFrame.TargetFrameContainer.FrameTexture",
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.FrameTexture",
        "TargetFrameTextureFrameTexture",
    },
}

function backend.PortraitTexture(which)
    return RustcoreCompat.ResolveFirst(PORTRAIT_TEXTURES[which])
end

-- ── Native buff frame ───────────────────────────────────────────────────

-- Suppression is alpha-only. :Hide() would be both protected and a fight
-- with Edit Mode, which reasserts frame visibility on layout changes;
-- alpha is neither protected nor something Edit Mode tracks.
--
-- EnableMouse is gated on combat because it is protected on frames the
-- modern client considers secure, and BuffFrame's status there has moved
-- more than once across expansions. Alpha is applied unconditionally
-- because it never has been.
local TEMP_ENCHANT_PATHS = {}
for i = 1, 3 do
    TEMP_ENCHANT_PATHS[i] = {
        "TempEnchant" .. i,
        "TemporaryEnchantFrame.TempEnchant" .. i,
        "BuffFrame.TemporaryEnchantFrame.TempEnchant" .. i,
    }
end

local function SetBuffFrameShown(shown)
    local alpha = shown and 1 or 0
    local mayTouch = backend.CanTouchBlizzardFrames()

    local frame = _G.BuffFrame
    if frame then
        frame:SetAlpha(alpha)
        if mayTouch then frame:EnableMouse(shown) end
    end

    -- The aura container is a separate frame in the modern layout and can
    -- carry its own alpha, so dimming only the parent can leave icons up.
    local container = RustcoreCompat.ResolveRegion("BuffFrame.AuraContainer")
    if container then container:SetAlpha(alpha) end

    for i = 1, 3 do
        local enchantButton = RustcoreCompat.ResolveFirst(TEMP_ENCHANT_PATHS[i])
        if enchantButton then
            enchantButton:SetAlpha(alpha)
            if mayTouch then enchantButton:EnableMouse(shown) end
        end
    end
end

function backend.HideNativeBuffFrame()
    SetBuffFrameShown(false)
end

function backend.ShowNativeBuffFrame()
    SetBuffFrameShown(true)
end

-- ── Auras ───────────────────────────────────────────────────────────────

-- Flattens C_UnitAuras' table back into the classic tuple the rest of
-- Rustcore reads, so no call site had to learn the new shape. AuraUtil's
-- own unpacker is preferred where present because it tracks Blizzard's
-- field renames so this file doesn't have to.
function backend.GetAura(unit, index, filter)
    if RustcoreCompat.HasFunc(C_UnitAuras, "GetAuraDataByIndex") then
        local data = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not data then return nil end
        if RustcoreCompat.HasFunc(AuraUtil, "UnpackAuraData") then
            return AuraUtil.UnpackAuraData(data)
        end
        return data.name, data.icon, data.applications, data.dispelName,
            data.duration, data.expirationTime, data.sourceUnit,
            data.isStealable, data.nameplateShowPersonal, data.spellId
    end
    -- A modern client that still exports the old global.
    if UnitAura then return UnitAura(unit, index, filter) end
    return nil
end

-- SetUnitAura went the same way as UnitAura, but the filter-specific
-- SetUnitBuff/SetUnitDebuff survived, so fall through to those before
-- giving up. Returning false lets the caller leave the tooltip alone
-- rather than showing an empty one.
function backend.SetTooltipAura(tooltip, unit, index, filter)
    if tooltip.SetUnitAura then
        tooltip:SetUnitAura(unit, index, filter)
        return true
    end
    if filter == "HARMFUL" then
        if tooltip.SetUnitDebuff then
            tooltip:SetUnitDebuff(unit, index)
            return true
        end
    elseif tooltip.SetUnitBuff then
        tooltip:SetUnitBuff(unit, index)
        return true
    end
    return false
end

-- ── Containers ──────────────────────────────────────────────────────────

-- C_Container is the only form here; the flat globals were removed from
-- this lineage in 10.0.

-- NUM_TOTAL_EQUIPPED_BAG_SLOTS already counts the reagent bag where the
-- client has one. The additions are ordered most- to least-authoritative so
-- a client that renames the constant still lands on the right count rather
-- than quietly dropping a bag.
function backend.MaxBagIndex()
    if NUM_TOTAL_EQUIPPED_BAG_SLOTS then
        return NUM_TOTAL_EQUIPPED_BAG_SLOTS
    end
    local base = NUM_BAG_SLOTS or 4
    if NUM_REAGENTBAG_SLOTS then
        return base + NUM_REAGENTBAG_SLOTS
    end
    return base + 1
end

function backend.GetContainerNumSlots(bag)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerNumSlots") then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return 0
end

function backend.GetContainerItemLink(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerItemLink") then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return nil
end

function backend.GetContainerItemLinkAndCount(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerItemInfo") then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil, 0 end
        return info.hyperlink, info.stackCount or 1
    end
    return nil, 0
end

function backend.PickupContainerItem(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "PickupContainerItem") then
        return C_Container.PickupContainerItem(bag, slot)
    end
end

RustcoreCompat.RegisterBackend("modern", backend)
