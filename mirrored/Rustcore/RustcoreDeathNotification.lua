-- Rustcore: center-screen death notification banner, replaces the native
-- raid warning for "another Rustcore player died" events (RustcoreBroadcast.Display).

RustcoreDeathNotification = {}

local notifFrame

local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local ART_PATH = Rustcore.GetAssetPath("UI/DeathNotification2 copy.tga")
local SOUND_PATH = Rustcore.GetAssetPath("Audio/MetalDrum.wav")

-- Texture is 2075x465; keep the banner's own aspect ratio at any display size.
local TEXTURE_WIDTH, TEXTURE_HEIGHT = 2075, 465
local FRAME_WIDTH = 540
local FRAME_HEIGHT = FRAME_WIDTH * (TEXTURE_HEIGHT / TEXTURE_WIDTH)

-- Frame's top edge sits this far down from the top of the screen (0 = top,
-- 1 = bottom).
local TOP_ANCHOR_FRACTION = 0.14

-- The item-icon socket cut into the art (measured directly from the source
-- texture: transparent square spanning roughly x[956,1119] y[53,211] out of
-- the full 2075x465 canvas), expressed as fractions so it scales with FRAME_WIDTH/HEIGHT.
local SOCKET_LEFT_FRAC, SOCKET_RIGHT_FRAC = 956 / TEXTURE_WIDTH, 1119 / TEXTURE_WIDTH
local SOCKET_TOP_FRAC, SOCKET_BOTTOM_FRAC = 53 / TEXTURE_HEIGHT, 211 / TEXTURE_HEIGHT

-- Vertical placement of the two text lines within the banner, as a fraction
-- of FRAME_HEIGHT, tuned to sit in the flat part of the banner below the socket.
local LINE1_Y_FRACTION = 0.58
local LINE2_Y_FRACTION = 0.78
local TEXT_SIDE_PADDING = 30
local TEXT_Y_OFFSET = 2
local LINE1_FONT_SIZE = 17
local LINE2_FONT_SIZE = 17

local DISPLAY_DURATION = 7.5
local FADE_DURATION = 1.2

local function ClassColorCode(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Shadow copies must not inherit the real text's embedded color escapes
-- (class color, item rarity color) or they'd render in that color instead
-- of solid black - strip them down to the plain visible characters.
local function StripColorCodes(text)
    if not text then return text end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|H.-|h", "")
    text = text:gsub("|h", "")
    text = text:gsub("|r", "")
    return text
end

-- Native SetShadowColor/SetShadowOffset doesn't render on this client (see
-- RustcoreDifficultyPopup.lua's BuildSpacedHeader), so the shadow is faked
-- with a second, black, offset copy of the text drawn underneath the real one.
local function CreateShadowedFontString(parent, fontSize)
    local shadow = parent:CreateFontString(nil, "OVERLAY")
    shadow:SetFont(BODY_FONT_PATH, fontSize, "")
    shadow:SetTextColor(0, 0, 0, 0.75)
    shadow:SetJustifyH("CENTER")
    shadow:SetWordWrap(true)

    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(BODY_FONT_PATH, fontSize, "")
    fs:SetTextColor(1, 1, 1)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(true)

    fs.shadow = shadow
    return fs
end

local function SetShadowedText(fs, text)
    fs:SetText(text)
    fs.shadow:SetText(StripColorCodes(text))
end

local function SetShadowedShown(fs, shown)
    if shown then
        fs:Show()
        fs.shadow:Show()
    else
        fs:Hide()
        fs.shadow:Hide()
    end
end

local function BuildFrame()
    local f = CreateFrame("Frame", "RustcoreDeathNotificationFrame", UIParent)
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetPoint("TOP", UIParent, "TOP", 0, -(UIParent:GetHeight() * TOP_ANCHOR_FRACTION))

    -- Icon sits on ARTWORK (below the art's OVERLAY layer) so the banner's
    -- frame renders on top and the icon only shows through the transparent socket.
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local socketLeft = FRAME_WIDTH * SOCKET_LEFT_FRAC
    local socketTop = FRAME_HEIGHT * SOCKET_TOP_FRAC
    local socketWidth = FRAME_WIDTH * (SOCKET_RIGHT_FRAC - SOCKET_LEFT_FRAC)
    local socketHeight = FRAME_HEIGHT * (SOCKET_BOTTOM_FRAC - SOCKET_TOP_FRAC)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", socketLeft, -socketTop)
    icon:SetSize(socketWidth, socketHeight)
    f.icon = icon

    local itemHitbox = CreateFrame("Frame", nil, f)
    itemHitbox:SetAllPoints(icon)
    itemHitbox:SetFrameLevel(f:GetFrameLevel() + 5)
    itemHitbox:EnableMouse(true)
    itemHitbox:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    itemHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.itemHitbox = itemHitbox

    local art = f:CreateTexture(nil, "OVERLAY")
    art:SetAllPoints(f)
    art:SetTexture(ART_PATH)
    f.art = art

    local textWidth = FRAME_WIDTH - TEXT_SIDE_PADDING * 2

    local line1 = CreateShadowedFontString(f, LINE1_FONT_SIZE)
    line1:SetWidth(textWidth)
    line1:SetPoint("TOP", f, "TOP", 0, -(FRAME_HEIGHT * LINE1_Y_FRACTION) + TEXT_Y_OFFSET)
    line1.shadow:SetWidth(textWidth)
    line1.shadow:SetPoint("TOP", f, "TOP", 1, -(FRAME_HEIGHT * LINE1_Y_FRACTION) + TEXT_Y_OFFSET - 1)
    f.line1 = line1

    local line2 = CreateShadowedFontString(f, LINE2_FONT_SIZE)
    line2:SetWidth(textWidth)
    line2:SetPoint("TOP", f, "TOP", 0, -(FRAME_HEIGHT * LINE2_Y_FRACTION) + TEXT_Y_OFFSET)
    line2.shadow:SetWidth(textWidth)
    line2.shadow:SetPoint("TOP", f, "TOP", 1, -(FRAME_HEIGHT * LINE2_Y_FRACTION) + TEXT_Y_OFFSET - 1)
    f.line2 = line2

    f:Hide()
    return f
end

local function EnsureFrame()
    if not notifFrame then
        notifFrame = BuildFrame()
    end
    return notifFrame
end

function RustcoreDeathNotification.Show(d)
    if not d or not d.name then return end
    local f = EnsureFrame()

    if f.fadeInfo then f.fadeInfo.finishedFunc = nil end
    if f.hideTimer then f.hideTimer:Cancel() end

    local srcStr = (d.source and d.source ~= "" and d.source ~= "Unknown") and d.source or "unknown"
    local hasLoss = d.count and d.count > 0

    SetShadowedText(f.line1, ClassColorCode(d.class) .. d.name .. "|r was slain by " .. srcStr)

    if hasLoss then
        local itemStr = (d.link and d.link ~= "") and d.link or "an item"
        local countStr = d.count .. (d.count == 1 and " item" or " items")
        SetShadowedText(f.line2, "they lost " .. countStr .. ", including " .. itemStr .. ".")
        SetShadowedShown(f.line2, true)
    else
        SetShadowedShown(f.line2, false)
    end

    if hasLoss and d.link then
        f.icon:SetTexture(GetItemIcon(d.link))
        f.icon:Show()
        f.itemHitbox:Show()
        f.itemHitbox.link = d.link
    else
        f.icon:Hide()
        f.itemHitbox:Hide()
        f.itemHitbox.link = nil
    end

    f:SetAlpha(1)
    f:Show()

    if Rustcore.GetSetting("showDeathWarningSound") then
        PlaySoundFile(SOUND_PATH, "Master")
    end

    f.hideTimer = C_Timer.NewTimer(DISPLAY_DURATION, function()
        UIFrameFadeOut(f, FADE_DURATION, 1, 0)
        f.fadeInfo.finishedFunc = function() f:Hide() end
    end)
end
