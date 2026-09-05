-- Rustcore Verification: Self-Found mail rules (plan sections 20, 21 and 22).
--
-- Phase 6. The mailbox is the one prohibited channel that cannot simply be shut,
-- because legitimate NPC and quest mail arrives through it and section 52 says
-- that must keep working normally. So instead of hiding the mailbox, every mail
-- is classified and only the forbidden ones are made unavailable.
--
-- Three layers, in order of authority:
--
--   prevention   TakeInboxItem, TakeInboxMoney and AutoLootMailItem are wrapped
--                so a blocked mail's contents cannot be collected at all. This
--                is the real enforcement.
--   presentation blocked rows are greyed, given a lock and a tooltip that says
--                why (section 20 is explicit that they stay visible).
--   backstop     if a blocked mail loses attachments anyway, a warning is
--                recorded for Phase 7 to weigh.
--
-- Why the wrappers replace the globals rather than hooking them: hooksecurefunc
-- runs *after* the original, which is too late to stop anything. Replacing them
-- also means a mail addon calling TakeInboxItem is held to the same rule, which
-- is the point -- otherwise the block would only apply to Blizzard's own UI.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.Mail = V.Mail or {}
local M = V.Mail

local DB = function() return V.NPCMailDB end

-- Section 20's five classes.
M.CLASS = {
    ALLOWED_NPC    = "ALLOWED_NPC",
    ALLOWED_SYSTEM = "ALLOWED_SYSTEM",
    BLOCKED_PLAYER = "BLOCKED_PLAYER",
    BLOCKED_AH     = "BLOCKED_AH",
    UNKNOWN        = "UNKNOWN",
}

local BLOCKED_REASON = {
    BLOCKED_PLAYER = "Player mail. Blocked by Rustcore Self-Found.",
    BLOCKED_AH     = "Auction House mail. Blocked by Rustcore Self-Found.",
    UNKNOWN        = "Sender could not be verified. Blocked by Rustcore Self-Found.",
}

local INBOX_ROWS = 7  -- INBOXITEMS_TO_DISPLAY

local function Setting(key)
    if Rustcore and Rustcore.GetSetting then return Rustcore.GetSetting(key) end
    return nil
end

-- Enforcement follows the setting, matching SelfFoundRestrict: a player who
-- switched Self-Found on is held to it whatever their certification says.
function M.IsEnforcing()
    return Setting("selfFound") and true or false
end

local lastNotice = 0
local function Notice(message)
    local now = GetTime and GetTime() or 0
    if now - lastNotice < 2 then return end
    lastNotice = now
    print("|cffff4444Rustcore:|r " .. message)
end

-- Classification (plan sections 21 and 22) -----------------------------------

function M.IsBlockedClass(class)
    return class == M.CLASS.BLOCKED_PLAYER
        or class == M.CLASS.BLOCKED_AH
        or class == M.CLASS.UNKNOWN
end

-- Classify the mail at `index`.
--
-- Ordered most-certain first, so a mail that satisfies several tests is decided
-- by the strongest one. Section 22 asks for several signals rather than
-- canReply alone, and the tests above canReply are exactly the cases where
-- canReply would give the wrong answer: auction mail and returned mail are both
-- non-replyable, and neither is ordinary NPC mail.
--
-- The final rule deserves saying out loud. Mail that is not replyable, carries
-- no invoice, no COD and no auction subject is treated as NPC mail and allowed.
-- Section 22 says unknown non-replyable mail should default to blocked, but in
-- Classic every player-sent mail is replyable, so after the auction and COD
-- tests above there is nothing left for that rule to catch except legitimate
-- quest and vendor mail -- which section 52 requires to keep working. Blocking
-- it would break normal solo play to guard against a case that cannot occur.
function M.Classify(index)
    local db = DB()
    local CLASS = M.CLASS

    local _, _, sender, subject, money, codAmount, _, hasItem,
          _, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(index)

    -- An auction invoice is proof, whatever the subject says.
    if GetInboxInvoiceInfo then
        local invoiceType = GetInboxInvoiceInfo(index)
        if invoiceType then return CLASS.BLOCKED_AH end
    end

    -- Auction returns (expired, cancelled, won) carry no invoice, so the
    -- localised subject globals are what identifies them.
    if db then
        if db.IsAuctionSubject(subject) or db.IsAuctionSender(sender) then
            return CLASS.BLOCKED_AH
        end
    end

    -- Cash on delivery is a player-to-player mechanic.
    if (codAmount or 0) > 0 then return CLASS.BLOCKED_PLAYER end

    -- Blizzard staff.
    if isGM then return CLASS.ALLOWED_SYSTEM end
    if db and db.IsSystemSender(sender) then return CLASS.ALLOWED_SYSTEM end

    -- Mail the player sent that came back. The contents were already theirs, so
    -- taking them is not an acquisition. Checked before canReply because
    -- returned mail is replyable and would otherwise read as player mail.
    if wasReturned then return CLASS.ALLOWED_SYSTEM end

    -- Replyable means a character on this realm sent it.
    if canReply then return CLASS.BLOCKED_PLAYER end

    -- Nothing identifies a sender at all: no name, and none of the tests above
    -- matched. Section 21's default.
    if type(sender) ~= "string" or sender == "" then return CLASS.UNKNOWN end

    return CLASS.ALLOWED_NPC
end

-- Cached per inbox refresh: InboxFrame_Update runs on every mail action and the
-- tooltip handlers ask again on every mouseover.
local classCache = {}

local function ClassOf(index)
    if type(index) ~= "number" then return nil end
    local cached = classCache[index]
    if cached then return cached end

    local numItems = GetInboxNumItems and GetInboxNumItems() or 0
    if index < 1 or index > numItems then return nil end

    local ok, class = pcall(M.Classify, index)
    if not ok or not class then return nil end
    classCache[index] = class
    return class
end

local function InvalidateCache()
    classCache = {}
end

M.GetClass = ClassOf

-- Prevention (plan section 21) -----------------------------------------------

local originals = {}

local function Refuse(index)
    if not M.IsEnforcing() then return false end
    local class = ClassOf(index)
    if not class or not M.IsBlockedClass(class) then return false end
    Notice(BLOCKED_REASON[class] or BLOCKED_REASON.UNKNOWN)
    return true
end

-- What, if anything, is attached to the outgoing mail right now: "items",
-- "money", "items and money", or nil when the letter carries neither.
local function OutgoingPayload()
    local hasItem = false
    local maxSend = _G.ATTACHMENTS_MAX_SEND or 12
    if type(_G.GetSendMailItem) == "function" then
        for slot = 1, maxSend do
            if GetSendMailItem(slot) then hasItem = true; break end
        end
    end

    local money = 0
    if type(_G.GetSendMailMoney) == "function" then
        money = GetSendMailMoney() or 0
    elseif type(_G.MoneyInputFrame_GetCopper) == "function" and _G.SendMailMoney then
        -- Older clients expose the amount only through the money input widget.
        money = MoneyInputFrame_GetCopper(_G.SendMailMoney) or 0
    end

    if hasItem and money > 0 then return "items and money" end
    if hasItem then return "items" end
    if money > 0 then return "money" end
    return nil
end

local function InstallWrappers()
    if originals.installed then return end
    originals.installed = true

    if type(_G.TakeInboxItem) == "function" then
        originals.TakeInboxItem = _G.TakeInboxItem
        _G.TakeInboxItem = function(index, attachIndex, ...)
            if Refuse(index) then return end
            return originals.TakeInboxItem(index, attachIndex, ...)
        end
    end

    if type(_G.TakeInboxMoney) == "function" then
        originals.TakeInboxMoney = _G.TakeInboxMoney
        _G.TakeInboxMoney = function(index, ...)
            if Refuse(index) then return end
            return originals.TakeInboxMoney(index, ...)
        end
    end

    -- Takes money and every attachment in one call, so it has to be covered
    -- separately or it would be the way around the two above.
    if type(_G.AutoLootMailItem) == "function" then
        originals.AutoLootMailItem = _G.AutoLootMailItem
        _G.AutoLootMailItem = function(index, ...)
            if Refuse(index) then return end
            return originals.AutoLootMailItem(index, ...)
        end
    end

    -- Outgoing mail. Blocking only what arrives leaves the other half of the
    -- channel open: mail is two-way, and a Self-Found character funding or
    -- equipping someone else -- an alt most obviously -- is the same channel
    -- being used, just in the other direction.
    --
    -- Only attachments and money are refused. A letter with no items and no
    -- gold moves nothing and is left alone.
    if type(_G.SendMail) == "function" then
        originals.SendMail = _G.SendMail
        _G.SendMail = function(recipient, subject, body, ...)
            if M.IsEnforcing() then
                local what = OutgoingPayload()
                if what then
                    Notice("Sending " .. what .. " by mail is blocked by Self-Found.")
                    return
                end
            end
            return originals.SendMail(recipient, subject, body, ...)
        end
    end
end

-- Presentation (plan section 20) ---------------------------------------------

-- Blocked mail stays in the list. It is greyed, marked with a lock, and says
-- why on hover; section 20 is explicit that hiding it silently is wrong.
local function EnsureLock(button)
    if button.rustcoreLock then return button.rustcoreLock end
    local lock = button:CreateTexture(nil, "OVERLAY")
    lock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    -- Corner rather than centre: the mail still has to be identifiable, so the
    -- lock marks the row without covering the stationery icon.
    lock:SetSize(16, 16)
    lock:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    lock:Hide()
    button.rustcoreLock = lock
    return lock
end

local function HookRowTooltip(button)
    if button.rustcoreTooltipHooked then return end
    button.rustcoreTooltipHooked = true

    button:HookScript("OnEnter", function(self)
        if not M.IsEnforcing() then return end
        local class = ClassOf(self.index)
        if not class or not M.IsBlockedClass(class) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Rustcore Self-Found")
        GameTooltip:AddLine(BLOCKED_REASON[class] or BLOCKED_REASON.UNKNOWN, 1, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Runs after Blizzard has laid the inbox out, because InboxFrame_Update resets
-- every colour and texture it owns on each refresh.
function M.StyleInbox()
    local numItems = GetInboxNumItems and GetInboxNumItems() or 0
    local page = (_G.InboxFrame and _G.InboxFrame.pageNum) or 1
    local enforcing = M.IsEnforcing()

    for row = 1, INBOX_ROWS do
        local button = _G["MailItem" .. row .. "Button"]
        if button then
            HookRowTooltip(button)

            -- Blizzard stamps the absolute mail index on the button; the page
            -- arithmetic is the fallback for a client that does not.
            local index = button.index
            if type(index) ~= "number" then
                index = ((page - 1) * INBOX_ROWS) + row
            end

            local lock = EnsureLock(button)
            local class = enforcing and index <= numItems and ClassOf(index) or nil
            local blocked = class ~= nil and M.IsBlockedClass(class)

            lock:SetShown(blocked)

            local icon = _G["MailItem" .. row .. "ButtonIcon"]
            if icon and SetDesaturation then SetDesaturation(icon, blocked and 1 or nil) end

            if blocked then
                local sender = _G["MailItem" .. row .. "Sender"]
                local subject = _G["MailItem" .. row .. "Subject"]
                if sender then sender:SetTextColor(0.5, 0.5, 0.5) end
                if subject then subject:SetTextColor(0.5, 0.5, 0.5) end
            end
        end
    end
end

-- Backstop (plan sections 21 and 47) -----------------------------------------
--
-- The wrappers above are the enforcement, so this only matters if something
-- bypassed them -- a mail addon that captured the original function before
-- Rustcore loaded, for instance.
--
-- Recorded as a warning rather than a failure on purpose. Mail indices shift as
-- mail is deleted or returned, so "this blocked mail has fewer attachments than
-- it did" is strong evidence but not proof, and section 51 sends evidence that
-- could have another explanation to a warning. Phase 7 weighs the money and
-- item baselines that would confirm it.
local watched = {}

local function RememberBlocked()
    local numItems = GetInboxNumItems and GetInboxNumItems() or 0
    local seen = {}
    for index = 1, numItems do
        local class = ClassOf(index)
        if class and M.IsBlockedClass(class) then
            local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(index)
            seen[index] = {
                sender  = sender,
                subject = subject,
                money   = money or 0,
                items   = hasItem or 0,
            }
        end
    end
    return seen
end

local function CheckBlockedDrain()
    if not M.IsEnforcing() then watched = {}; return end

    local current = RememberBlocked()
    for index, before in pairs(watched) do
        local now = current[index]
        -- Only compared when it is unmistakably the same mail still sitting at
        -- the same index; anything else is an index shift, not a withdrawal.
        if now and now.sender == before.sender and now.subject == before.subject then
            local lostItems = (before.items or 0) - (now.items or 0)
            local lostMoney = (before.money or 0) - (now.money or 0)
            if lostItems > 0 or lostMoney > 0 then
                local track = V.GetTrack("selfFound")
                if track and track.claimed and track.status ~= V.STATUS.FAILED then
                    V.AddWarning("selfFound", "mailAcquisition",
                        string.format("blocked mail lost %d item(s) and %d copper",
                            lostItems > 0 and lostItems or 0,
                            lostMoney > 0 and lostMoney or 0))
                    if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
                    if RustcoreSelfFoundBuff and RustcoreSelfFoundBuff.Refresh then
                        RustcoreSelfFoundBuff.Refresh()
                    end
                end
            end
        end
    end
    watched = current
end

-- Events ---------------------------------------------------------------------

function M.OnEvent(event)
    if event == "MAIL_SHOW" then
        InvalidateCache()
        if M.IsEnforcing() then
            watched = RememberBlocked()
            Notice("Self-Found: player and Auction House mail is locked.")
        end

    elseif event == "MAIL_INBOX_UPDATE" then
        InvalidateCache()
        CheckBlockedDrain()
        M.StyleInbox()

    elseif event == "MAIL_CLOSED" then
        InvalidateCache()
        watched = {}
    end
end

-- Diagnostic readout ---------------------------------------------------------

-- /rcmail lists how every mail currently in the inbox classifies. Read-only,
-- and the way to walk the section 50 mail test matrix without guessing.
SLASH_RCMAIL1 = "/rcmail"
SlashCmdList["RCMAIL"] = function()
    local numItems = GetInboxNumItems and GetInboxNumItems() or 0
    if numItems == 0 then
        print("|cffff4444Rustcore:|r no mail in the inbox (open a mailbox first).")
        return
    end

    print(string.format("|cffff4444Rustcore mail|r  %d message(s), enforcement %s",
        numItems, M.IsEnforcing() and "on" or "off"))

    for index = 1, numItems do
        local _, _, sender, subject, money, cod, _, hasItem,
              _, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(index)
        local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index) or nil
        local class = ClassOf(index) or "?"
        local blocked = M.IsBlockedClass(class)
        print(string.format("  %2d %s%-14s|r %s / %s", index,
            blocked and "|cffff4444" or "|cff44ff44", class,
            tostring(sender), tostring(subject)))
        print(string.format("       items=%s money=%s cod=%s reply=%s gm=%s returned=%s invoice=%s",
            tostring(hasItem or 0), tostring(money or 0), tostring(cod or 0),
            canReply and "y" or "n", isGM and "y" or "n",
            wasReturned and "y" or "n", tostring(invoice)))
    end
end

function M.Init()
    if M.initialized then return end
    M.initialized = true

    InstallWrappers()

    -- Restyle after Blizzard repaints the list, which it does on every mail
    -- action as well as on every inbox event.
    if type(_G.InboxFrame_Update) == "function" then
        hooksecurefunc("InboxFrame_Update", function()
            local ok, err = pcall(M.StyleInbox)
            if not ok then
                print("|cffff4444Rustcore ERROR:|r mail styling: " .. tostring(err))
            end
        end)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("MAIL_SHOW")
    frame:RegisterEvent("MAIL_INBOX_UPDATE")
    frame:RegisterEvent("MAIL_CLOSED")
    frame:SetScript("OnEvent", function(_, event)
        -- A fault in verification must never break the game session.
        local ok, err = pcall(M.OnEvent, event)
        if not ok then
            print("|cffff4444Rustcore ERROR:|r mail verification: " .. tostring(err))
        end
    end)
    M.frame = frame
end
