-- Rustcore Verification: mail classification knowledge (plan section 22).
--
-- Data and matchers only. Mail.lua owns the decisions; this file owns what is
-- known about senders and subjects, and it is the one place to extend when a
-- locale or a client generation turns out to phrase something differently.
--
-- Localisation (section 22) is handled by reading Blizzard's own localised
-- global strings rather than by shipping a translation table. AUCTION_*_SUBJECT
-- are the exact format strings the server builds auction mail subjects from, so
-- matching against them is correct on every client and cannot drift out of date
-- the way a hand-maintained list would.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.NPCMailDB = V.NPCMailDB or {}
local DB = V.NPCMailDB

-- Lua pattern escaping ------------------------------------------------------

local function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Turn a printf-style global ("Auction expired: %s") into an anchored Lua
-- pattern ("^Auction expired: .-"). Every literal stretch is escaped, and each
-- placeholder becomes a lazy wildcard, so an item name containing a magic
-- character cannot break the match or make it match too much.
local function PatternFromFormat(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end

    local parts, pos = {}, 1
    while true do
        local s, e = fmt:find("%%[%d%.%-]*[sdfg]", pos)
        if not s then
            parts[#parts + 1] = EscapePattern(fmt:sub(pos))
            break
        end
        parts[#parts + 1] = EscapePattern(fmt:sub(pos, s - 1))
        parts[#parts + 1] = ".-"
        pos = e + 1
    end

    local pattern = table.concat(parts)
    if pattern == "" or pattern == ".-" then return nil end
    return "^" .. pattern
end

-- Auction house mail --------------------------------------------------------

-- Every subject the auction house sends under. Section 21 lists sales, expiries,
-- cancellations and returns as equally forbidden, and these are the globals the
-- server uses to build each of them.
local AUCTION_SUBJECT_GLOBALS = {
    "AUCTION_SOLD_MAIL_SUBJECT",     -- "Auction successful: %s"
    "AUCTION_EXPIRED_MAIL_SUBJECT",  -- "Auction expired: %s"
    "AUCTION_REMOVED_MAIL_SUBJECT",  -- "Auction cancelled: %s"
    "AUCTION_WON_MAIL_SUBJECT",      -- "Auction won: %s"
    "AUCTION_OUTBID_MAIL_SUBJECT",   -- "Outbid on %s"
    "AUCTION_INVOICE_MAIL_SUBJECT",  -- "Sale Pending: %s"
}

-- Senders known to be the auction house. The subject patterns above are the
-- authoritative test -- they are real mail globals and always match the client
-- locale -- so this is only a second line of defence for a client that phrases a
-- subject differently. Extend per locale as needed; a missing entry costs
-- nothing, because unrecognised mail is blocked anyway.
DB.AUCTION_SENDERS = {
    ["Auction House"] = true,
    ["Auktionshaus"]  = true,
}

local auctionPatterns

local function BuildAuctionPatterns()
    auctionPatterns = {}
    for _, name in ipairs(AUCTION_SUBJECT_GLOBALS) do
        local pattern = PatternFromFormat(_G[name])
        if pattern then auctionPatterns[#auctionPatterns + 1] = pattern end
    end
end

-- True when this subject is one the auction house sends.
function DB.IsAuctionSubject(subject)
    if type(subject) ~= "string" or subject == "" then return false end
    if not auctionPatterns then BuildAuctionPatterns() end
    for _, pattern in ipairs(auctionPatterns) do
        if subject:find(pattern) then return true end
    end
    return false
end

function DB.IsAuctionSender(sender)
    if type(sender) ~= "string" then return false end
    return DB.AUCTION_SENDERS[sender] == true
end

-- System senders ------------------------------------------------------------

-- Blizzard customer support. GM_EMAIL_NAME is localised by the client, so the
-- comparison works everywhere; the isGM flag on the mail header is checked
-- separately in Mail.lua and is the stronger signal of the two.
function DB.IsSystemSender(sender)
    if type(sender) ~= "string" or sender == "" then return false end
    local gm = _G.GM_EMAIL_NAME
    if type(gm) == "string" and gm ~= "" and sender == gm then return true end
    return false
end

-- Test seam: forget the cached patterns so the next query rebuilds them.
function DB.Reset()
    auctionPatterns = nil
end
