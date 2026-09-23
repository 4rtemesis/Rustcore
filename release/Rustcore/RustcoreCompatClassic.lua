-- RustcoreCompatClassic: the Era 1.15.x / TBC Anniversary 2.5.x backend.
--
-- This is the lineage Rustcore was written against, so the job here is
-- preservation, not adaptation: every function below does exactly what the
-- corresponding inline code did before the compat split, and any behaviour
-- change on these clients would be a regression rather than a feature.
--
-- See RustcoreCompatModern.lua for the other half, and RustcoreCompat.lua
-- for how one of the two gets chosen.

local backend = {}

-- ── Protected frames ────────────────────────────────────────────────────

-- The classic clients do have combat lockdown, but Rustcore has always
-- touched Blizzard's frames here without incident and adding a gate now
-- would change working behaviour for no reason. The modern backend is
-- where this genuinely matters.
function backend.CanTouchBlizzardFrames()
    return true
end

-- ── Portrait art ────────────────────────────────────────────────────────

local PORTRAIT_TEXTURES = {
    player = { "PlayerFrameTexture" },
    target = { "TargetFrameTextureFrameTexture" },
}

function backend.PortraitTexture(which)
    return RustcoreCompat.ResolveFirst(PORTRAIT_TEXTURES[which])
end

-- ── Native buff frame ───────────────────────────────────────────────────

-- Weapon-enchant (poison/oil/stone) buffs aren't part of BuffFrame at all
-- in Classic/TBC FrameXML - there's no wrapping container, just three
-- standalone global buttons. Hiding BuffFrame alone left these visible,
-- showing Blizzard's own purple-bordered icon beside ours.
-- Suppression is alpha-only, and deliberately does not touch EnableMouse.
-- Alpha is not a protected operation on any client; EnableMouse is, on
-- frames the client considers secure, and on WoW Forever calling it
-- against BuffFrame raised the blocked-action dialog at login - out of
-- combat, so a lockdown gate would not have helped. An invisible frame
-- that still takes mouse input is not a problem worth that popup.
local function SetBuffFrameShown(shown)
    local alpha = shown and 1 or 0
    local frame = _G.BuffFrame
    if frame then
        frame:SetAlpha(alpha)
    end

    for i = 1, 3 do
        local enchantButton = _G["TempEnchant" .. i]
        if enchantButton then
            enchantButton:SetAlpha(alpha)
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

function backend.GetAura(unit, index, filter)
    if UnitAura then
        return UnitAura(unit, index, filter)
    end
    return nil
end

function backend.SetTooltipAura(tooltip, unit, index, filter)
    if tooltip.SetUnitAura then
        tooltip:SetUnitAura(unit, index, filter)
        return true
    end
    -- SetUnitAura is the only form on this lineage today, but a client
    -- that ships the modern tooltip methods under a classic-looking API
    -- surface would otherwise fall straight through to false and take
    -- every buff tooltip with it. Mirrors the modern backend.
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

-- C_Container was backported to the Classic lineage (1.14.4 / 3.4.1), so
-- both forms can be live on a client in this branch. Each check tests the
-- individual method rather than just the namespace, because a client that
-- ships the namespace before the method would otherwise call into nil.

-- No reagent bag on this lineage; four bags plus the backpack.
function backend.MaxBagIndex()
    return NUM_BAG_SLOTS or 4
end

function backend.GetContainerNumSlots(bag)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerNumSlots") then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

function backend.GetContainerItemLink(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerItemLink") then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
    return nil
end

function backend.GetContainerItemLinkAndCount(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "GetContainerItemInfo") then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil, 0 end
        return info.hyperlink, info.stackCount or 1
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        return link, count or 1
    end
    return nil, 0
end

function backend.PickupContainerItem(bag, slot)
    if RustcoreCompat.HasFunc(C_Container, "PickupContainerItem") then
        return C_Container.PickupContainerItem(bag, slot)
    end
    if PickupContainerItem then return PickupContainerItem(bag, slot) end
end

RustcoreCompat.RegisterBackend("classic", backend)
