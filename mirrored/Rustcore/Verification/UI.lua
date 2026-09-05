-- Rustcore Verification: the Verification tab (plan sections 45 and 46).
--
-- What this page is for: telling the player how much of their certification
-- Rustcore can actually stand behind, in plain language.
--
-- Section 45 draws one hard line -- the raw hash chain and the internal event
-- history are not shown. They are machinery, they would mean nothing to a
-- player, and displaying them would invite exactly the kind of hand-editing the
-- chain exists to detect. What is shown is the conclusion and the evidence
-- behind it: the status, how much of the character's play Rustcore actually
-- watched, and anything it has flagged.
--
-- Section 28's tone applies to every string here. A lost certification is
-- reported as lost, never as an accusation.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.UI = V.UI or {}
local UI = V.UI

local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")

-- Status presentation -----------------------------------------------------------

-- Colour and wording per status. The word is what the player reads first, so it
-- says what Rustcore can vouch for rather than what the player may have done.
local STATUS_LOOK = {
    VERIFIED   = { 0.35, 0.9,  0.35, "Verified",     "Rustcore has detected no rule violations." },
    WARNING    = { 1.0,  0.82, 0.2,  "Verified",     "Something unexplained was noted. Certification still stands." },
    SUSPENDED  = { 0.55, 0.75, 0.95, "Paused",       "Not certified right now, but nothing is wrong. Keep playing and it comes back." },
    UNCERTAIN  = { 0.7,  0.7,  0.75, "Pending",      "Still being observed. Not certified yet." },
    UNVERIFIED = { 0.75, 0.55, 0.3,  "Not verified", "Rustcore cannot establish enough continuity to certify this." },
    FAILED     = { 0.9,  0.3,  0.3,  "Disqualified", "This run can no longer be certified." },
}

-- The line the player most wants: can this still be fixed, or is it over?
-- Kept separate from the status wording above because it is the one thing that
-- should never be ambiguous.
local function OutlookText(status)
    if status == "VERIFIED" or status == "WARNING" then
        return "This run is certified.", 0.5, 0.85, 0.5
    end
    if V.IsRecoverable(status) then
        return "This run is not disqualified. Playing on will restore it.", 0.55, 0.8, 0.95
    end
    return "This run has been disqualified and cannot be certified again.", 0.9, 0.45, 0.4
end

local function Look(status)
    return STATUS_LOOK[status or ""] or STATUS_LOOK.UNVERIFIED
end

local function FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
    return string.format("%dm", minutes)
end

local function ApplyFont(fontString, size)
    if not fontString then return end
    fontString:SetFont(BODY_FONT_PATH, size or 14, "")
end

-- Small builders ------------------------------------------------------------------

local function MakeText(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ApplyFont(fs, size)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

-- The certainty bar. The player asked to see how sure Rustcore is, and this is
-- the honest answer: continuity. Everything else on the page is a yes or a no,
-- but how much of the character's life Rustcore actually watched is a matter of
-- degree, and it is what every certification ultimately rests on.
local function MakeBar(parent, width)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 12)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0, 0, 0, 0.55)

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    fill:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bar.fill = fill
    bar.width = width

    -- 0 means nothing watched, 1 means fully within tolerance.
    function bar:SetFraction(fraction)
        fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
        self.fill:SetWidth(math.max(1, (self.width - 2) * fraction))
        if fraction >= 0.75 then
            self.fill:SetVertexColor(0.35, 0.85, 0.35, 1)
        elseif fraction >= 0.4 then
            self.fill:SetVertexColor(1, 0.8, 0.2, 1)
        else
            self.fill:SetVertexColor(0.9, 0.35, 0.3, 1)
        end
    end

    return bar
end

-- Page ------------------------------------------------------------------------------

-- Builds the tab's contents into `page` and returns a refresh function.
-- RustcoreOptions owns the tab and the page frame; everything inside is ours.
function UI.BuildPage(page)
    local PAD_L = 26
    local WIDTH = 380

    local scroll = CreateFrame("ScrollFrame", "RustcoreVerificationScrollFrame", page,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 42)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(410, 720)
    scroll:SetScrollChild(content)

    local scrollBar = scroll.ScrollBar or _G["RustcoreVerificationScrollFrameScrollBar"]
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if not scrollBar then return end
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local nextValue = scrollBar:GetValue() - (delta * 28)
        scrollBar:SetValue(math.max(minValue, math.min(maxValue, nextValue)))
    end)

    local widgets = {}

    -- Difficulty ------------------------------------------------------------
    local dHeader = MakeText(content, 19, 1, 0.82, 0)
    dHeader:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, -18)
    dHeader:SetText("Difficulty Certification")

    widgets.dTier = MakeText(content, 22)
    widgets.dTier:SetPoint("TOPLEFT", dHeader, "BOTTOMLEFT", 0, -8)

    widgets.dStatus = MakeText(content, 15)
    widgets.dStatus:SetPoint("TOPLEFT", widgets.dTier, "BOTTOMLEFT", 0, -4)

    widgets.dNote = MakeText(content, 13, 0.75, 0.75, 0.75)
    widgets.dNote:SetPoint("TOPLEFT", widgets.dStatus, "BOTTOMLEFT", 0, -4)
    widgets.dNote:SetWidth(WIDTH)
    widgets.dNote:SetWordWrap(true)

    widgets.dOutlook = MakeText(content, 13)
    widgets.dOutlook:SetPoint("TOPLEFT", widgets.dNote, "BOTTOMLEFT", 0, -4)
    widgets.dOutlook:SetWidth(WIDTH)
    widgets.dOutlook:SetWordWrap(true)

    widgets.dDetail = MakeText(content, 13, 0.85, 0.85, 0.85)
    widgets.dDetail:SetPoint("TOPLEFT", widgets.dOutlook, "BOTTOMLEFT", 0, -8)
    widgets.dDetail:SetWidth(WIDTH)
    widgets.dDetail:SetWordWrap(true)

    -- Tracking confidence ----------------------------------------------------
    local cHeader = MakeText(content, 19, 1, 0.82, 0)
    cHeader:SetPoint("TOPLEFT", widgets.dDetail, "BOTTOMLEFT", 0, -18)
    cHeader:SetText("Tracking Confidence")

    widgets.bar = MakeBar(content, WIDTH - 20)
    widgets.bar:SetPoint("TOPLEFT", cHeader, "BOTTOMLEFT", 0, -10)

    widgets.cDetail = MakeText(content, 13, 0.85, 0.85, 0.85)
    widgets.cDetail:SetPoint("TOPLEFT", widgets.bar, "BOTTOMLEFT", 0, -8)
    widgets.cDetail:SetWidth(WIDTH)
    widgets.cDetail:SetWordWrap(true)

    -- Self-Found -------------------------------------------------------------
    local sHeader = MakeText(content, 19, 1, 0.82, 0)
    sHeader:SetPoint("TOPLEFT", widgets.cDetail, "BOTTOMLEFT", 0, -18)
    sHeader:SetText("Self-Found")

    widgets.sStatus = MakeText(content, 15)
    widgets.sStatus:SetPoint("TOPLEFT", sHeader, "BOTTOMLEFT", 0, -8)

    widgets.sNote = MakeText(content, 13, 0.75, 0.75, 0.75)
    widgets.sNote:SetPoint("TOPLEFT", widgets.sStatus, "BOTTOMLEFT", 0, -4)
    widgets.sNote:SetWidth(WIDTH)
    widgets.sNote:SetWordWrap(true)

    widgets.sOutlook = MakeText(content, 13)
    widgets.sOutlook:SetPoint("TOPLEFT", widgets.sNote, "BOTTOMLEFT", 0, -4)
    widgets.sOutlook:SetWidth(WIDTH)
    widgets.sOutlook:SetWordWrap(true)

    widgets.sDetail = MakeText(content, 13, 0.85, 0.85, 0.85)
    widgets.sDetail:SetPoint("TOPLEFT", widgets.sOutlook, "BOTTOMLEFT", 0, -8)
    widgets.sDetail:SetWidth(WIDTH)
    widgets.sDetail:SetWordWrap(true)

    -- Transfer ---------------------------------------------------------------
    local tHeader = MakeText(content, 19, 1, 0.82, 0)
    tHeader:SetPoint("TOPLEFT", widgets.sDetail, "BOTTOMLEFT", 0, -18)
    tHeader:SetText("Move To Another PC")

    local tBlurb = MakeText(content, 13, 0.75, 0.75, 0.75)
    tBlurb:SetPoint("TOPLEFT", tHeader, "BOTTOMLEFT", 0, -8)
    tBlurb:SetWidth(WIDTH)
    tBlurb:SetWordWrap(true)
    tBlurb:SetText(
        "Rustcore stores your certification on this computer, so a second PC "
        .. "starts out knowing nothing about this character.\n\n"
        .. "Export writes everything Rustcore has tracked -- both certifications, "
        .. "your stats, and a fresh reading of your /played time -- into one line "
        .. "of text. Import it on the other PC to continue there.\n\n"
        .. "The /played reading is what makes it trustworthy: an import is only "
        .. "accepted within 10 minutes of the export, so an old string cannot be "
        .. "used later to undo something. Clean minutes you played before "
        .. "importing are kept, not discarded.")

    local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportBtn:SetSize(110, 24)
    exportBtn:SetPoint("TOPLEFT", tBlurb, "BOTTOMLEFT", 0, -12)
    exportBtn:SetText("Export")
    RustcoreTheme.SkinButton(exportBtn)
    ApplyFont(exportBtn:GetFontString(), 14)

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetSize(110, 24)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    importBtn:SetText("Import")
    RustcoreTheme.SkinButton(importBtn)
    ApplyFont(importBtn:GetFontString(), 14)

    -- The transfer string itself. One scrolling edit box used for both
    -- directions: export fills it and selects it for Ctrl+C (section 34),
    -- import reads whatever was pasted in.
    local boxFrame = CreateFrame("Frame", nil, content,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    boxFrame:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -10)
    boxFrame:SetSize(WIDTH - 10, 70)

    local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints(boxFrame)
    boxBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    boxBg:SetVertexColor(0, 0, 0, 0.6)

    local boxScroll = CreateFrame("ScrollFrame", "RustcoreTransferScroll", boxFrame,
        "UIPanelScrollFrameTemplate")
    boxScroll:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 6, -6)
    boxScroll:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, boxScroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    -- A scroll child needs a size of its own. The height is deliberately far
    -- taller than the visible window so a long transfer string has room to wrap
    -- and the scroll frame does the rest.
    edit:SetSize(WIDTH - 44, 400)
    -- Transfer strings run to several hundred characters. An edit box with a
    -- default cap would silently truncate one, and a truncated string fails its
    -- checksum on the far side with no obvious cause.
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    boxScroll:SetScrollChild(edit)
    widgets.edit = edit

    local status = MakeText(content, 13, 0.85, 0.85, 0.85)
    status:SetPoint("TOPLEFT", boxFrame, "BOTTOMLEFT", 0, -8)
    status:SetWidth(WIDTH)
    status:SetWordWrap(true)
    widgets.transferStatus = status

    local function SetStatus(text, r, g, b)
        status:SetText(text or "")
        status:SetTextColor(r or 0.85, g or 0.85, b or 0.85)
    end

    exportBtn:SetScript("OnClick", function()
        SetStatus("Reading your played time from the server...")
        V.Transfer.BeginExport(function(str, err)
            if not str then
                SetStatus(err or "Export failed.", 0.9, 0.4, 0.4)
                return
            end
            edit:SetText(str)
            edit:SetFocus()
            edit:HighlightText()
            SetStatus("Copy this with Ctrl+C, then paste it on the other PC and press Import.",
                0.5, 0.9, 0.5)
        end)
    end)

    importBtn:SetScript("OnClick", function()
        local text = edit:GetText()
        SetStatus("Checking the transfer against your played time...")
        V.Transfer.BeginImport(text, function(ok, message)
            if ok then
                SetStatus(message or "Verification imported.", 0.5, 0.9, 0.5)
                edit:SetText("")
                if UI.Refresh then UI.Refresh() end
            else
                SetStatus(message or "Import refused.", 0.9, 0.4, 0.4)
            end
        end)
    end)

    -- Refresh ---------------------------------------------------------------

    function UI.Refresh()
        local record = V.GetRecord()
        if not record then
            widgets.dTier:SetText("No record")
            widgets.dTier:SetTextColor(0.7, 0.7, 0.7)
            widgets.dStatus:SetText("")
            widgets.dNote:SetText("Rustcore has not started tracking this character yet.")
            widgets.dOutlook:SetText("")
            widgets.dDetail:SetText("")
            widgets.sStatus:SetText("")
            widgets.sNote:SetText("")
            widgets.sOutlook:SetText("")
            widgets.sDetail:SetText("")
            widgets.bar:SetFraction(0)
            widgets.cDetail:SetText("")
            return
        end

        local difficulty = record.difficulty or {}
        local selfFound  = record.selfFound or {}
        local timeState  = record.time or {}

        -- Difficulty.
        local dLook = Look(difficulty.status)
        local tier = difficulty.highestVerifiedTier or 0
        if V.IsCertified(difficulty.status) and tier >= 1 then
            widgets.dTier:SetText(V.GetTierName(tier))
            widgets.dTier:SetTextColor(dLook[1], dLook[2], dLook[3])
        else
            widgets.dTier:SetText("--")
            widgets.dTier:SetTextColor(0.6, 0.6, 0.6)
        end
        widgets.dStatus:SetText(dLook[4])
        widgets.dStatus:SetTextColor(dLook[1], dLook[2], dLook[3])
        widgets.dNote:SetText(dLook[5])

        local dText, dr, dg, db = OutlookText(difficulty.status)
        widgets.dOutlook:SetText(dText)
        widgets.dOutlook:SetTextColor(dr, dg, db)

        local dLines = {}
        local selected = V.GetCurrentTier()
        dLines[#dLines + 1] = "Playing: " .. V.GetTierName(selected)
        if difficulty.permanentCapTier then
            dLines[#dLines + 1] = "Capped at " .. V.GetTierName(difficulty.permanentCapTier)
                .. " by an earlier death under weaker rules."
        end
        dLines[#dLines + 1] = "Deaths recorded: " .. tostring(difficulty.deaths or 0)
        local repairWarn = V.GetWarningCount("difficulty", "unexplainedRepair")
        dLines[#dLines + 1] = "Repair warnings: " .. tostring(repairWarn)
            .. (difficulty.repairViolations and difficulty.repairViolations > 0
                and ("   repairs observed: " .. difficulty.repairViolations) or "")
        widgets.dDetail:SetText(table.concat(dLines, "\n"))

        -- Tracking confidence. The fraction is how much of the allowance is
        -- still unspent, so a full green bar means Rustcore watched essentially
        -- everything and an empty one means it lost the thread.
        local tracked = timeState.trackedSinceAnchor or 0
        local untracked = timeState.untrackedSeconds or 0
        local allowed = (V.Time and V.Time.GetAllowedGap and V.Time.GetAllowedGap()) or 1
        local remaining = 1 - (untracked / math.max(1, allowed))
        widgets.bar:SetFraction(remaining)

        local band = timeState.gapBand or "OK"
        local bandText =
            band == "OK" and "Rustcore has watched this character continuously."
            or band == "WARNING" and "Some play happened while Rustcore was not running."
            or "Too much play happened without Rustcore watching to certify this character."
        widgets.cDetail:SetText(string.format(
            "%s\nTracked: %s     Unwatched: %s of %s allowed",
            bandText, FormatDuration(tracked), FormatDuration(untracked), FormatDuration(allowed)))

        -- Self-Found.
        local claimed = selfFound.claimed
        if not claimed then
            widgets.sStatus:SetText("Not enabled")
            widgets.sStatus:SetTextColor(0.6, 0.6, 0.6)
            widgets.sNote:SetText("Turn on Self-Found under Gameplay to start a certified run.")
            widgets.sOutlook:SetText("")
            widgets.sDetail:SetText("")
        else
            local sLook = Look(selfFound.status)
            widgets.sStatus:SetText(sLook[4])
            widgets.sStatus:SetTextColor(sLook[1], sLook[2], sLook[3])
            widgets.sNote:SetText(sLook[5])

            local sText, sr, sg, sb = OutlookText(selfFound.status)
            -- A suspension can say something more useful than "keep playing":
            -- exactly what is standing in the way, and how much longer.
            if selfFound.status == V.STATUS.SUSPENDED and V.SelfFound and V.SelfFound.EvaluateRestore then
                local ok, why, remaining = V.SelfFound.EvaluateRestore()
                if ok then
                    sText = "Ready to be restored."
                elseif remaining then
                    sText = string.format(
                        "Not disqualified. About %s more clean play restores it.",
                        FormatDuration(remaining))
                elseif why then
                    sText = "Not disqualified, but held back: " .. why .. "."
                end
            end
            widgets.sOutlook:SetText(sText)
            widgets.sOutlook:SetTextColor(sr, sg, sb)

            local enforcing = V.SelfFoundRestrict and V.SelfFoundRestrict.IsEnforcing
                and V.SelfFoundRestrict.IsEnforcing()
            local sLines = {}
            sLines[#sLines + 1] = "Trading: " .. (enforcing and "blocked" or "not enforced")
            sLines[#sLines + 1] = "Auction House: " .. (enforcing and "blocked" or "not enforced")
            sLines[#sLines + 1] = "Player and auction mail: "
                .. ((V.Mail and V.Mail.IsEnforcing and V.Mail.IsEnforcing()) and "locked" or "not enforced")
            sLines[#sLines + 1] = "Gold anomalies: "
                .. tostring(V.GetWarningCount("selfFound", "goldDiscrepancy"))
            sLines[#sLines + 1] = "Item anomalies: "
                .. tostring(V.GetWarningCount("selfFound", "itemDiscrepancy"))
            if (selfFound.violations or 0) > 0 and selfFound.lastViolation then
                sLines[#sLines + 1] = "Lost after: " .. tostring(selfFound.lastViolation)
            end
            widgets.sDetail:SetText(table.concat(sLines, "\n"))
        end
    end

    UI.Refresh()
    return UI.Refresh
end
