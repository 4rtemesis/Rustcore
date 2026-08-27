-- RustcoreDragon: replaces the native player/target frame face art with a
-- difficulty-tier dragon, using the same 5 "Dragon-<Tier>-Target.png" images
-- (edited copies of Blizzard's own target-frame face texture) for both
-- frames. The target-frame orientation is the source art's native
-- orientation; the player frame mirrors it horizontally, matching how
-- Blizzard's own PlayerFrame/TargetFrame textures relate to each other.
--
-- Player frame always shows the local player's own difficulty tier, gated
-- by the "dragonPlayerFrame" setting. Target frame shows either the local
-- player's own tier (when self-targeted, no comm needed) or another
-- Rustcore user's tier learned via RustcoreSelfFoundComm's query/response
-- protocol (see RustcoreSelfFoundComm.GetKnownDifficulty), gated by the
-- "dragonTargetFrame" setting.
--
-- The dragon is a full replacement, not a decoration layered on top - the
-- native PlayerFrameTexture/TargetFrameTextureFrameTexture is alpha-hidden
-- (never :Hide()'d, so Blizzard's own bookkeeping is left alone) whenever
-- our dragon is shown in its place, and restored the moment it isn't.

RustcoreDragon = RustcoreDragon or {}

local DRAGON_TEXTURES = {
    [1] = "Dragon-Rusted-Target.png",
    [2] = "Dragon-Broken-Target.png",
    [3] = "Dragon-Shattered-Target.png",
    [4] = "Dragon-Crumbling-Target.png",
    [5] = "Dragon-Dust-Target.png",
}

local NATIVE_TEXTURE_PLAYER = "PlayerFrameTexture"
local NATIVE_TEXTURE_TARGET = "TargetFrameTextureFrameTexture"

-- PlayerFrameTexture and TargetFrameTextureFrameTexture do not have the
-- same rendered dimensions, even though both replacement images use the
-- same 256x128 source canvas. Use one shared footprint so the mirrored
-- player dragon and target dragon always appear at exactly the same size.
-- This sits between the native-sized attempt and the earlier 280-wide art.
local DRAGON_WIDTH = 256
local DRAGON_HEIGHT = 128
local PLAYER_X_OFFSET = -5
local TARGET_X_OFFSET = -13
local PLAYER_Y_OFFSET = -18
local TARGET_Y_OFFSET = -14

-- Candidate globals for each frame's level-badge FontString, tried in order
-- since the exact name isn't confirmed on this client - the first one found
-- is raised above the dragon; if none exist this is a silent no-op.
local LEVEL_TEXT_CANDIDATES_PLAYER = { "PlayerLevelText" }
local LEVEL_TEXT_CANDIDATES_TARGET = { "TargetFrameTextureFrameLevelText", "TargetLevelText", "TargetFrameLevelText" }
local VALUE_TEXT_CANDIDATES_PLAYER = { "PlayerFrameHealthBarText", "PlayerFrameManaBarText" }
local VALUE_TEXT_CANDIDATES_TARGET = {
    "TargetFrameTextureFrameHealthBarText",
    "TargetFrameTextureFrameManaBarText",
    "TargetFrameHealthBarText",
    "TargetFrameManaBarText",
}
local VALUE_BAR_CANDIDATES_PLAYER = { "PlayerFrameHealthBar", "PlayerFrameManaBar" }
local VALUE_BAR_CANDIDATES_TARGET = { "TargetFrameHealthBar", "TargetFrameManaBar" }
local HIT_TEXT_CANDIDATES_PLAYER = { "PlayerHitIndicator", "PlayerFrameHitIndicator" }
local HIT_TEXT_CANDIDATES_TARGET = { "TargetFrameHitIndicator", "TargetHitIndicator" }

local playerDragon
local targetDragon
local playerDragonShown = false
local targetDragonShown = false
local playerValueTexts = {}
local targetValueTexts = {}

local function RaiseLevelText(candidates, holder)
    for _, levelTextName in ipairs(candidates) do
        local levelText = _G[levelTextName]
        if levelText then
            -- WoW always draws a frame's child frames above textures/regions
            -- painted on the parent itself, regardless of texture layer - so
            -- reparenting onto our (higher-level) holder is what lets this
            -- FontString draw above the dragon art. Its anchor is left
            -- completely untouched; it was never in the wrong spot, it just
            -- couldn't show through.
            levelText:SetParent(holder)
            levelText:SetDrawLayer("OVERLAY")
            return
        end
    end
end

local function RaiseValueTexts(textCandidates, barCandidates, holder)
    local texts = {}
    local seen = {}

    local function AddText(text)
        if not text or seen[text] then return end
        seen[text] = true
        text.rustcoreDragonOrigAlpha = text:GetAlpha()
        text:SetParent(holder)
        text:SetDrawLayer("OVERLAY", 7)
        texts[#texts + 1] = text
    end

    for _, textName in ipairs(textCandidates) do
        AddText(_G[textName])
    end
    for _, barName in ipairs(barCandidates) do
        local bar = _G[barName]
        if bar then
            AddText(bar.TextString)
            AddText(bar.text)
            local barNameGlobal = bar.GetName and bar:GetName()
            if barNameGlobal then AddText(_G[barNameGlobal .. "Text"]) end
        end
    end

    return texts
end

local function SetValueTextsVisible(texts, visible)
    for _, text in ipairs(texts) do
        if visible then
            text:SetAlpha(1)
        elseif text.rustcoreDragonOrigAlpha ~= nil then
            text:SetAlpha(text.rustcoreDragonOrigAlpha)
        end
    end
end

local function RaiseHitText(candidates, parent, holder)
    local seen = {}
    local function Raise(text)
        if not text or seen[text] then return end
        seen[text] = true
        text:SetParent(holder)
        text:SetDrawLayer("OVERLAY", 7)
    end

    for _, textName in ipairs(candidates) do
        Raise(_G[textName])
    end
    Raise(parent.HitIndicator)
    Raise(parent.hitIndicator)
end

-- Center on the corresponding native art to retain Blizzard's positioning,
-- while using the shared footprint above instead of inheriting the two
-- native texture regions' mismatched sizes.
local function EnsurePlayerDragon()
    if playerDragon then return playerDragon end
    local parent = _G.PlayerFrame
    local nativeTexture = _G[NATIVE_TEXTURE_PLAYER]
    if not parent or not nativeTexture then return nil end

    local holder = CreateFrame("Frame", "RustcoreDragonPlayerFrameHolder", parent)
    holder:SetFrameLevel(parent:GetFrameLevel() + 20)
    holder:SetSize(DRAGON_WIDTH, DRAGON_HEIGHT)
    holder:SetPoint("CENTER", nativeTexture, "CENTER", PLAYER_X_OFFSET, PLAYER_Y_OFFSET)

    local tex = holder:CreateTexture("RustcoreDragonPlayerFrame", "ARTWORK")
    tex:SetAllPoints(holder)
    tex:SetTexCoord(1, 0, 0, 1)
    tex:Hide()

    RaiseLevelText(LEVEL_TEXT_CANDIDATES_PLAYER, holder)
    playerValueTexts = RaiseValueTexts(VALUE_TEXT_CANDIDATES_PLAYER, VALUE_BAR_CANDIDATES_PLAYER, holder)
    RaiseHitText(HIT_TEXT_CANDIDATES_PLAYER, parent, holder)

    playerDragon = tex
    return playerDragon
end

local function EnsureTargetDragon()
    if targetDragon then return targetDragon end
    local parent = _G.TargetFrame
    local nativeTexture = _G[NATIVE_TEXTURE_TARGET]
    if not parent or not nativeTexture then return nil end

    local holder = CreateFrame("Frame", "RustcoreDragonTargetFrameHolder", parent)
    holder:SetFrameLevel(parent:GetFrameLevel() + 20)
    holder:SetSize(DRAGON_WIDTH, DRAGON_HEIGHT)
    holder:SetPoint("CENTER", nativeTexture, "CENTER", TARGET_X_OFFSET, TARGET_Y_OFFSET)

    local tex = holder:CreateTexture("RustcoreDragonTargetFrame", "ARTWORK")
    tex:SetAllPoints(holder)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:Hide()

    RaiseLevelText(LEVEL_TEXT_CANDIDATES_TARGET, holder)
    targetValueTexts = RaiseValueTexts(VALUE_TEXT_CANDIDATES_TARGET, VALUE_BAR_CANDIDATES_TARGET, holder)
    RaiseHitText(HIT_TEXT_CANDIDATES_TARGET, parent, holder)

    targetDragon = tex
    return targetDragon
end

local function SetNativeTextureHidden(globalName, hidden)
    local t = _G[globalName]
    if not t then return end
    if hidden then
        if t.rustcoreOrigAlpha == nil then t.rustcoreOrigAlpha = t:GetAlpha() end
        t:SetAlpha(0)
    elseif t.rustcoreOrigAlpha ~= nil then
        t:SetAlpha(t.rustcoreOrigAlpha)
    end
end

function RustcoreDragon.RefreshPlayerFrame()
    local tex = EnsurePlayerDragon()
    if not tex then return end

    if not Rustcore.GetSetting("dragonPlayerFrame") then
        tex:Hide()
        playerDragonShown = false
        SetNativeTextureHidden(NATIVE_TEXTURE_PLAYER, false)
        SetValueTextsVisible(playerValueTexts, false)
        return
    end

    local difficulty = Rustcore.GetSetting("difficulty") or 1
    tex:SetTexture(Rustcore.GetAssetPath("UI/" .. (DRAGON_TEXTURES[difficulty] or DRAGON_TEXTURES[1])))
    tex:Show()
    playerDragonShown = true
    SetNativeTextureHidden(NATIVE_TEXTURE_PLAYER, true)
    SetValueTextsVisible(playerValueTexts, true)
end

function RustcoreDragon.RefreshTargetFrame()
    local tex = EnsureTargetDragon()
    if not tex then return end

    local difficulty
    if Rustcore.GetSetting("dragonTargetFrame") and UnitExists("target") and UnitIsPlayer("target") then
        if UnitIsUnit("target", "player") then
            difficulty = Rustcore.GetSetting("difficulty")
        elseif RustcoreSelfFoundComm and RustcoreSelfFoundComm.GetKnownDifficulty then
            difficulty = RustcoreSelfFoundComm.GetKnownDifficulty(UnitName("target"))
        end
    end

    if not difficulty then
        tex:Hide()
        targetDragonShown = false
        SetNativeTextureHidden(NATIVE_TEXTURE_TARGET, false)
        SetValueTextsVisible(targetValueTexts, false)
        return
    end

    tex:SetTexture(Rustcore.GetAssetPath("UI/" .. (DRAGON_TEXTURES[difficulty] or DRAGON_TEXTURES[1])))
    tex:Show()
    targetDragonShown = true
    SetNativeTextureHidden(NATIVE_TEXTURE_TARGET, true)
    SetValueTextsVisible(targetValueTexts, true)
end

local eventFrame = CreateFrame("Frame")
local sinceRefresh = 0
local REFRESH_INTERVAL = 0.2

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Native frame textures may not have settled yet at this exact
        -- point; a short delay lets Blizzard finish its own first layout
        -- pass before we touch PlayerFrameTexture/TargetFrameTextureFrameTexture.
        C_Timer.After(0.5, function()
            pcall(RustcoreDragon.RefreshPlayerFrame)
            pcall(RustcoreDragon.RefreshTargetFrame)
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(RustcoreDragon.RefreshTargetFrame)
    end
end)

-- Self-heal on a short throttle: Blizzard's own frame code can reassert the
-- native texture's alpha on its own (e.g. combat state changes, Edit Mode),
-- fighting a one-time SetAlpha(0) the same way BuffFrame does in
-- RustcoreSelfFoundBuff.lua - so re-hide it every tick while our dragon is
-- meant to be showing in its place.
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh < REFRESH_INTERVAL then return end
    sinceRefresh = 0
    if playerDragonShown then
        SetNativeTextureHidden(NATIVE_TEXTURE_PLAYER, true)
        SetValueTextsVisible(playerValueTexts, true)
    end
    if targetDragonShown then
        SetNativeTextureHidden(NATIVE_TEXTURE_TARGET, true)
        SetValueTextsVisible(targetValueTexts, true)
    end
end)
