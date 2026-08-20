-- RustcoreSelfFoundComm: lets Rustcore users see each other's verified Self
-- Found status. Clicking (targeting/focusing) a player queries the shared
-- channel already joined by RustcoreBroadcast; if that player's own client
-- currently reports "verified" (Rustcore.GetSelfFoundIconState), it answers
-- back and we show a small icon on their portrait. Silence means "no" -
-- unverified/disabled status is never broadcast.
--
-- Message format: RCSF~Q~<name>   (query: "is <name> currently verified?")
--                 RCSF~R~<name>   (response: "<name> says yes")

RustcoreSelfFoundComm = {}

local PREFIX = "RCSF"
local DELIM = "~"
local QUERY_TTL = 120
local VERIFY_TTL = 120
local ICON_SIZE = 14

local queried = {}   -- normalized name -> last query time
local verified = {}  -- normalized name -> last verified-response time
local overlays = {}  -- frame -> overlay texture

local WATCHED_FRAMES = {
    { frame = "TargetFrame", unit = "target" },
    { frame = "FocusFrame", unit = "focus" },
    { frame = "PartyMemberFrame1", unit = "party1" },
    { frame = "PartyMemberFrame2", unit = "party2" },
    { frame = "PartyMemberFrame3", unit = "party3" },
    { frame = "PartyMemberFrame4", unit = "party4" },
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function NormalizeName(name)
    if not name then return nil end
    if Ambiguate then
        return Ambiguate(name, "short")
    end
    return name:match("^[^-]+") or name
end

local function SendMessage(msg)
    local channelNum = RustcoreBroadcast and RustcoreBroadcast.GetChannelNum and RustcoreBroadcast.GetChannelNum()
    if not channelNum then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "CHANNEL", channelNum)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, "CHANNEL", channelNum)
    end
end

local function IsVerifiedFresh(name)
    local t = verified[name]
    return t and (GetTime() - t) < VERIFY_TTL
end

-- ── Sending ───────────────────────────────────────────────────────────────────

local function RequestStatus(name)
    name = NormalizeName(name)
    if not name or name == NormalizeName(UnitName("player")) then return end
    local now = GetTime()
    if queried[name] and now - queried[name] < QUERY_TTL then return end
    queried[name] = now
    SendMessage(table.concat({ "Q", name }, DELIM))
end

local function HandleQuery(name)
    name = NormalizeName(name)
    local myName = NormalizeName(UnitName("player"))
    if name ~= myName then return end
    if Rustcore.GetSelfFoundIconState and Rustcore.GetSelfFoundIconState() == "verified" then
        SendMessage(table.concat({ "R", myName }, DELIM))
    end
end

local function HandleResponse(name)
    name = NormalizeName(name)
    if not name then return end
    verified[name] = GetTime()
    RustcoreSelfFoundComm.RefreshOverlays()
end

-- ── Portrait overlay ─────────────────────────────────────────────────────────

local function EnsureOverlay(frame)
    local existing = overlays[frame]
    if existing then return existing end
    if not frame.portrait then return nil end

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetSize(ICON_SIZE, ICON_SIZE)
    tex:SetPoint("BOTTOMRIGHT", frame.portrait, "BOTTOMRIGHT", 2, -2)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:Hide()
    overlays[frame] = tex
    return tex
end

local function UpdateFrameOverlay(frame, unit)
    if not frame then return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        local tex = overlays[frame]
        if tex then tex:Hide() end
        return
    end

    local tex = EnsureOverlay(frame)
    if not tex then return end

    local name = NormalizeName(UnitName(unit))
    if IsVerifiedFresh(name) then
        tex:SetTexture(Rustcore.GetSelfFoundIconTexture())
        tex:Show()
    else
        tex:Hide()
    end
end

function RustcoreSelfFoundComm.RefreshOverlays()
    for _, entry in ipairs(WATCHED_FRAMES) do
        local frame = _G[entry.frame]
        if frame then
            UpdateFrameOverlay(frame, entry.unit)
        end
    end
end

local function OnUnitChanged(unit)
    if UnitExists(unit) and UnitIsPlayer(unit) then
        RequestStatus(UnitName(unit))
    end
    RustcoreSelfFoundComm.RefreshOverlays()
end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        OnUnitChanged("target")

    elseif event == "PLAYER_FOCUS_CHANGED" then
        OnUnitChanged("focus")

    elseif event == "GROUP_ROSTER_UPDATE" then
        RustcoreSelfFoundComm.RefreshOverlays()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channelType = ...
        if prefix ~= PREFIX or channelType ~= "CHANNEL" then return end
        local kind, name = strsplit(DELIM, msg)
        if kind == "Q" then
            HandleQuery(name)
        elseif kind == "R" then
            HandleResponse(name)
        end
    end
end)
