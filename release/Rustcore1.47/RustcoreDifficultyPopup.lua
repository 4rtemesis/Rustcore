-- Rustcore: first-login "select your difficulty" popup
-- Shown once per character, the first time it logs in, unless already dismissed.

RustcoreDifficultyPopup = {}

local f

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local TITLE_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH  = Rustcore.GetAssetPath("Font/BPpong.otf")
local TITLE_COLOR = { 0.85, 0.15, 0.15 }
local HEADER_COLOR = { 1, 1, 1 }
local BODY_COLOR   = { 1, 1, 1 }

local FRAME_WIDTH, FRAME_HEIGHT = 560, 430
local PANEL_SIZE = 150
local PANEL_GAP  = 16
local PANEL_EDGE_SIZE = 12
local HEADER_FONT_SIZE = 20
local HEADER_LETTER_SPACING = 3
local HEADER_Y_OFFSET = 22
local BODY_FONT_SIZE = 15
local BORDER_COLOR_NORMAL   = { 0.25, 0.20, 0.16, 0.9 }
local BORDER_COLOR_SELECTED = { 1, 0.78, 0.25, 1 }
local HIGHLIGHT_COLOR = { 1, 0.82, 0.3, 0.30 }

-- index -> { difficulty value, background art, header text, body text }
local PANEL_DATA = {
    {
        value = 1,
        bg = "UI/background1 copy.tga",
        header = "LITE",
        body = "You can no longer repair items.",
    },
    {
        value = 2,
        bg = "UI/background2 copy.tga",
        header = "NORMAL",
        body = "You can no longer repair items, and one gear piece will break when you die.",
    },
    {
        value = 5,
        bg = "UI/background5 copy.tga",
        header = "EXTREME",
        body = "You can no longer repair items, and all gear will break when you die.",
    },
}

local DEFAULT_PANEL_INDEX = 2 -- Normal

-- WoW font strings have no letter-tracking control, so spaced headers are
-- laid out as individually positioned font strings (same approach used for
-- the DELETE/SELECT button label in RustcoreTheme.lua).
local function BuildSpacedHeader(panel, text)
    local widths, letters, totalWidth = {}, {}, 0
    for i = 1, #text do
        local fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetFont(BODY_FONT_PATH, HEADER_FONT_SIZE, "")
        fs:SetTextColor(unpack(HEADER_COLOR))
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetText(text:sub(i, i))
        local w = fs:GetStringWidth()
        widths[i] = w
        letters[i] = fs
        totalWidth = totalWidth + w + (i < #text and HEADER_LETTER_SPACING or 0)
    end

    local x = -totalWidth / 2
    for i = 1, #text do
        local fs = letters[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", panel, "TOP", x, -HEADER_Y_OFFSET)
        x = x + widths[i] + HEADER_LETTER_SPACING
    end
end

local function BuildPanel(parent, index, data)
    -- Cast-shadow plane, offset behind the panel.
    local shadow = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetSize(PANEL_SIZE, PANEL_SIZE)
    shadow:SetColorTexture(0, 0, 0, 0.55)

    local panel = CreateFrame("Button", nil, parent, backdropTemplate)
    panel:SetSize(PANEL_SIZE, PANEL_SIZE)
    panel:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = PANEL_EDGE_SIZE,
    })
    panel:SetBackdropBorderColor(unpack(BORDER_COLOR_NORMAL))

    shadow:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    bg:SetTexture(Rustcore.GetAssetPath(data.bg))

    local highlight = panel:CreateTexture(nil, "OVERLAY")
    highlight:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    highlight:SetBlendMode("ADD")
    highlight:SetVertexColor(unpack(HIGHLIGHT_COLOR))
    highlight:Hide()
    panel.highlight = highlight

    BuildSpacedHeader(panel, data.header)

    local body = panel:CreateFontString(nil, "OVERLAY")
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEADER_Y_OFFSET - 22)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    body:SetFont(BODY_FONT_PATH, BODY_FONT_SIZE, "")
    body:SetTextColor(unpack(BODY_COLOR))
    body:SetShadowColor(0, 0, 0, 1)
    body:SetShadowOffset(1, -1)
    body:SetJustifyH("CENTER")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetText(data.body)

    panel:SetScript("OnClick", function()
        RustcoreDifficultyPopup.SetSelected(index)
    end)

    return panel
end

local function MarkSeen()
    Rustcore.SetProfileValue("hasSeenDifficultyPopup", true)
end

local function BuildFrame()
    local frame = CreateFrame("Frame", "RustcoreDifficultyPopupFrame", UIParent, backdropTemplate)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    RustcoreTheme.ApplyFrameSkin(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -32)
    title:SetFont(TITLE_FONT_PATH, 30, "")
    title:SetTextColor(unpack(TITLE_COLOR))
    title:SetShadowColor(0, 0, 0, 0.6)
    title:SetShadowOffset(1, -1)
    title:SetText("Rustcore")

    local subtitle = frame:CreateFontString(nil, "OVERLAY")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -20)
    subtitle:SetFont(BODY_FONT_PATH, 18, "")
    subtitle:SetTextColor(1, 1, 1)
    subtitle:SetShadowColor(0, 0, 0, 1)
    subtitle:SetShadowOffset(1, -1)
    subtitle:SetText("Welcome! select your difficulty:")

    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function()
        MarkSeen()
        frame:Hide()
    end)
    RustcoreTheme.SkinExitButton(closeBtn)

    local panelRow = CreateFrame("Frame", nil, frame)
    panelRow:SetPoint("TOP", subtitle, "BOTTOM", 0, -26)
    panelRow:SetSize(PANEL_SIZE * 3 + PANEL_GAP * 2, PANEL_SIZE)

    frame.panels = {}
    for i, data in ipairs(PANEL_DATA) do
        local panel = BuildPanel(panelRow, i, data)
        panel:SetPoint("LEFT", panelRow, "LEFT", (i - 1) * (PANEL_SIZE + PANEL_GAP), 0)
        frame.panels[i] = panel
    end

    local selectBtn = CreateFrame("Button", "RustcoreDifficultySelectButton", frame)
    selectBtn:SetSize(150, 56)
    selectBtn:SetPoint("TOP", panelRow, "BOTTOM", 0, -30)
    local selectLabel = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectLabel:SetPoint("CENTER", selectBtn, "CENTER", 0, 0)
    selectBtn:SetFontString(selectLabel)
    RustcoreTheme.SkinDeleteButton(selectBtn)
    selectBtn:SetText("SELECT")
    selectBtn:SetScript("OnClick", function()
        local data = PANEL_DATA[frame.selectedIndex or DEFAULT_PANEL_INDEX]
        Rustcore.SetSetting("difficulty", data.value)
        PlaySoundFile(Rustcore.GetAssetPath("Audio/difficultysound.wav"), "Master")
        MarkSeen()
        frame:Hide()
    end)

    frame:Hide()
    return frame
end

function RustcoreDifficultyPopup.SetSelected(index)
    if not f then return end
    f.selectedIndex = index
    for i, panel in ipairs(f.panels) do
        local selected = (i == index)
        panel.highlight:SetShown(selected)
        panel:SetBackdropBorderColor(unpack(selected and BORDER_COLOR_SELECTED or BORDER_COLOR_NORMAL))
    end
end

function RustcoreDifficultyPopup.Show()
    if not f then f = BuildFrame() end
    RustcoreDifficultyPopup.SetSelected(DEFAULT_PANEL_INDEX)
    f:Show()
end

function RustcoreDifficultyPopup.MaybeShowOnLogin()
    if Rustcore.GetProfileValue("hasSeenDifficultyPopup") then return end
    RustcoreDifficultyPopup.Show()
end
