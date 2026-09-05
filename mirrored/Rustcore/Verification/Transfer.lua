-- Rustcore Verification: character transfer between PCs
-- (plan sections 32 to 42).
--
-- Moving a character's verification to another machine is the one operation
-- that hands a player their whole certification as editable text, so almost all
-- of this file is about refusing to accept it.
--
-- What makes a transfer trustworthy is not the string; it is /played. The server
-- knows exactly how long the character has been played, an export records that
-- number, and an import compares it against the live one. That single comparison
-- is what stops the two attacks worth caring about:
--
--   rollback   (section 38) exporting at 50 hours, playing to 55, then importing
--              the old string to erase what happened in between. The live
--              /played is five hours past the export, so it is refused.
--   fabrication a hand-written string cannot know a /played the server will
--              agree with, and the checksum has to reconcile as well.
--
-- Section 40 is equally firm in the other direction: a few clean minutes played
-- on the new PC before importing must not be thrown away. Those minutes are
-- merged rather than discarded.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.Transfer = V.Transfer or {}
local X = V.Transfer

local floor = math.floor

-- Section 42: versioned from the beginning.
X.PREFIX = "RCV1"
X.SCHEMA = 1

-- Section 36: a transfer stays valid while the live /played is within ten
-- minutes of the exported one.
X.PLAYED_TOLERANCE = 600

-- How much of that difference may go unexplained by play this session tracked.
-- Covers the ordinary leak in a legitimate transfer: the seconds between
-- pressing Export and logging out, and any accrual lag around a loading screen.
-- Kept deliberately tight, because this is the number that decides how long a
-- window an old export could be used to undo something in.
X.UNACCOUNTED_ALLOWANCE = 90

-- How long to wait for the server's /played reply before giving up on an
-- import. The request is cheap and the reply is usually immediate.
X.PLAYED_TIMEOUT = 10

local function Hash(text)
    if V.Integrity and V.Integrity.Hash then return V.Integrity.Hash(text) end
    return "nohash"
end

-- Encoding ---------------------------------------------------------------------
--
-- A compact "key=value;key=value" body rather than a serialised Lua table, per
-- section 33. Every separator is escaped inside values, so splitting on ";" and
-- on the first "=" is unambiguous -- which matters because one of the values is
-- an item link, and those are full of "|".
--
-- Deliberately left as readable text rather than compressed and base64'd. There
-- is no deflate library in this addon, and base64 without compression would make
-- the string a third longer while section 33 asks for it to be short. The
-- checksum below is what protects it; section 30 already concedes that none of
-- this resists someone editing Rustcore's own Lua.

local function Esc(value)
    local text = tostring(value == nil and "" or value)
    text = text:gsub("\\", "\\b")
    text = text:gsub(";", "\\s")
    text = text:gsub("=", "\\e")
    text = text:gsub("|", "\\p")
    text = text:gsub("\n", "\\n")
    return text
end

local UNESCAPE = { b = "\\", s = ";", e = "=", p = "|", n = "\n" }

local function Unesc(text)
    return (tostring(text or ""):gsub("\\(.)", function(c)
        return UNESCAPE[c] or c
    end))
end

local function Serialize(fields)
    local keys = {}
    for key in pairs(fields) do keys[#keys + 1] = key end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        local value = fields[key]
        if value ~= nil then
            parts[#parts + 1] = key .. "=" .. Esc(value)
        end
    end
    return table.concat(parts, ";")
end

local function Deserialize(body)
    local fields = {}
    for pair in tostring(body or ""):gmatch("[^;]+") do
        local key, value = pair:match("^([^=]+)=(.*)$")
        if key then fields[key] = Unesc(value) end
    end
    return fields
end

local function Num(value, default)
    return tonumber(value) or default
end

-- Sub-table packing ------------------------------------------------------------

-- Typed warning counts, as "kind:count,kind:count".
local function PackWarnings(track)
    local warnings = type(track) == "table" and track.warnings or nil
    if type(warnings) ~= "table" then return "" end
    local parts = {}
    for kind, count in pairs(warnings) do
        parts[#parts + 1] = tostring(kind) .. ":" .. tostring(count or 0)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function UnpackWarnings(text)
    local warnings = {}
    for entry in tostring(text or ""):gmatch("[^,]+") do
        local kind, count = entry:match("^(.-):(%d+)$")
        if kind then warnings[kind] = tonumber(count) end
    end
    return warnings
end

-- Equipped durability, as "slot:cur:max:id,...". Carried because it is what an
-- unexplained-repair finding is measured against (section 14); without it the
-- first scan after an import would have nothing to compare to.
local function PackDurability(record)
    local state = record.durabilityState
    if type(state) ~= "table" or type(state.slots) ~= "table" then return "" end
    local parts = {}
    for slot, entry in pairs(state.slots) do
        if type(entry) == "table" then
            parts[#parts + 1] = string.format("%s:%s:%s:%s", tostring(slot),
                tostring(entry.cur or 0), tostring(entry.max or 0), tostring(entry.id or ""))
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function UnpackDurability(text)
    local slots = {}
    for entry in tostring(text or ""):gmatch("[^,]+") do
        local slot, cur, maximum, id = entry:match("^(%d+):(%d+):(%d+):(%d*)$")
        if slot then
            slots[tonumber(slot)] = {
                cur = tonumber(cur),
                max = tonumber(maximum),
                id  = tonumber(id),
            }
        end
    end
    return slots
end

-- Stats (plan section 41) --------------------------------------------------------

local function GetStatsTable()
    if not RustcoreDB then return nil end
    RustcoreDB.characterStats = RustcoreDB.characterStats or {}
    local key = Rustcore and Rustcore.GetCharacterKey and Rustcore.GetCharacterKey()
        or (UnitName and UnitName("player")) or "player"
    RustcoreDB.characterStats[key] = RustcoreDB.characterStats[key] or {}
    return RustcoreDB.characterStats[key]
end

-- Export (plan section 34) --------------------------------------------------------

-- Build the string from whatever state exists right now. Callers go through
-- X.BeginExport, which refreshes /played first so the anchor is never stale.
-- `freshPlayed`, when given, is the figure from the /played reply that prompted
-- this export. It overrides the stored copy because `tp` below is the number an
-- import measures rollback against, and it must be the newest one available.
function X.BuildString(freshPlayed)
    local record = V.GetRecord()
    if not record then return nil, "no verification record for this character" end

    local identity   = record.identity or {}
    local difficulty = record.difficulty or {}
    local selfFound  = record.selfFound or {}
    local timeState  = record.time or {}
    local economy    = record.economy or {}
    local money      = economy.money or {}
    local items      = economy.items or {}
    local chain      = record.chain or {}
    local stats      = GetStatsTable() or {}

    local fields = {
        v    = X.SCHEMA,
        av   = V.GetAddonVersion(),
        ts   = time and time() or 0,

        -- Identity (section 3). The GUID is what an import validates against.
        ig   = identity.guid or "",
        inm  = identity.name or "",
        ir   = identity.realm or "",
        ic   = identity.class or "",
        ira  = identity.race or "",

        org  = record.origin or "",
        cr   = floor(Num(record.createdAt, 0)),

        -- Difficulty track.
        ds   = difficulty.status or "",
        dt   = Num(difficulty.highestVerifiedTier, 0),
        dc   = difficulty.permanentCapTier and Num(difficulty.permanentCapTier, 0) or "",
        dp   = difficulty.pendingCapTier and Num(difficulty.pendingCapTier, 0) or "",
        dfl  = difficulty.deathFloorTier and Num(difficulty.deathFloorTier, 0) or "",
        dl   = difficulty.startedAtLevel and Num(difficulty.startedAtLevel, 0) or "",
        dd   = Num(difficulty.deaths, 0),
        drv  = Num(difficulty.repairViolations, 0),
        dw   = PackWarnings(difficulty),

        -- Self-Found track.
        ss   = selfFound.status or "",
        sl   = selfFound.startedAtLevel and Num(selfFound.startedAtLevel, 0) or "",
        scl  = selfFound.claimed and 1 or 0,
        sql  = selfFound.qualifyFromLevel and Num(selfFound.qualifyFromLevel, 0) or "",
        sal  = selfFound.claimedAtLevel and Num(selfFound.claimedAtLevel, 0) or "",
        slp  = selfFound.claimLapsed and 1 or 0,
        ssp  = selfFound.suspended and 1 or 0,
        srt  = selfFound.restoreAtTracked and Num(selfFound.restoreAtTracked, 0) or "",
        sv   = Num(selfFound.violations, 0),
        svr  = selfFound.lastViolation or "",
        sw   = PackWarnings(selfFound),

        -- Playtime anchor (sections 16 and 37).
        ta   = floor(Num(timeState.anchorPlayed, 0)),
        tp   = floor(freshPlayed or Num(timeState.lastServerPlayed, 0)),
        tt   = floor(Num(timeState.trackedSinceAnchor, 0)),
        tu   = floor(Num(timeState.untrackedSeconds, 0)),
        tb   = timeState.gapBand or "OK",

        -- Economy baselines (Phase 7).
        eml  = money.last and floor(Num(money.last, 0)) or "",
        emu  = floor(Num(money.unexplained, 0)),
        ema  = Num(money.anomalies, 0),
        eia  = Num(items.anomalies, 0),

        -- Durability baseline.
        du   = PackDurability(record),

        -- Chain continuity (section 30). The head and sequence travel so the
        -- imported record continues the same chain rather than starting a new
        -- one; the retained event window deliberately does not, per section 33.
        ch   = chain.head or "",
        cs   = Num(chain.sequence, 0),

        -- Stats (section 41).
        xd   = Num(stats.destroyedItems, 0),
        xr   = Num(stats.rustedItems, 0),
        xbi  = Num(stats.bestItemLostIlvl, 0),
        xbl  = stats.bestItemLostLink or "",
    }

    local body = Serialize(fields)
    return X.PREFIX .. ":" .. Hash(body) .. ":" .. body
end

-- Section 34: never export against a stale /played. The reply is asynchronous,
-- so the string is built in the callback.
function X.BeginExport(callback)
    local record = V.GetRecord()
    if not record then
        callback(nil, "no verification record for this character")
        return
    end

    local done = false
    -- See BeginImport: the played figure is taken from the event payload rather
    -- than from Time.lua's copy, because the two event handlers have no
    -- guaranteed order.
    local function finish(played)
        if done then return end
        done = true
        local str, err = X.BuildString(played)
        if str and V.Integrity and V.Integrity.Append then
            V.Integrity.Append("EXPORT", {
                played = floor(played or Num(V.Time and V.Time.GetLastServerPlayed(), 0)),
            })
        end
        callback(str, err)
    end

    X.pendingExport = finish
    if V.Time and V.Time.Request then V.Time.Request() end

    -- The reply normally lands within a frame or two; this is the fallback for
    -- a server that does not answer, and it exports against the last known
    -- figure rather than failing outright.
    if C_Timer and C_Timer.After then
        C_Timer.After(X.PLAYED_TIMEOUT, function()
            -- Only abandon the wait this call started; a second export begun in
            -- the meantime owns the slot now.
            if X.pendingExport ~= finish then return end
            X.pendingExport = nil
            finish()
        end)
    else
        finish()
    end
end

-- Import (plan sections 35 to 40) --------------------------------------------------

-- Parse and check everything that can be checked without the server.
-- Returns the field table, or nil plus a reason.
function X.Parse(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    -- Line breaks are stripped wherever they appear, not just at the ends: Esc
    -- turns every newline in the data into "\n", so any literal one left in the
    -- pasted text was introduced in transit by an editor or a chat client.
    -- Spaces are left alone, because item names contain them.
    text = text:gsub("[\r\n]", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "nothing to import" end

    local prefix, checksum, body = text:match("^(RCV%d+):(%x+):(.*)$")
    if not prefix then
        return nil, "this does not look like a Rustcore transfer string"
    end
    if prefix ~= X.PREFIX then
        return nil, "this transfer was created by an incompatible version of Rustcore"
    end
    if Hash(body) ~= checksum then
        return nil, "the transfer string is damaged or was edited"
    end

    local fields = Deserialize(body)
    if Num(fields.v, 0) ~= X.SCHEMA then
        return nil, "this transfer was created by an incompatible version of Rustcore"
    end

    -- Section 3: verification is bound to the character it was earned on.
    local currentGuid = UnitGUID and UnitGUID("player") or nil
    if fields.ig and fields.ig ~= "" and currentGuid and fields.ig ~= currentGuid then
        return nil, "this transfer belongs to a different character"
    end
    if (not fields.ig or fields.ig == "") and currentGuid then
        -- Exported before a GUID was available. Fall back to name and realm.
        local name = UnitName and UnitName("player") or nil
        local realm = GetRealmName and GetRealmName() or nil
        if fields.inm ~= name or (fields.ir ~= "" and realm and fields.ir ~= realm) then
            return nil, "this transfer belongs to a different character"
        end
    end

    return fields
end

-- Sections 37 and 38. `serverPlayed` is the live figure; `fields` is the parsed
-- transfer. Returns ok, reason, and the number of seconds to credit back.
function X.Reconcile(fields, serverPlayed)
    local exported = Num(fields.tp, 0)
    local difference = (serverPlayed or 0) - exported

    if difference < -60 then
        -- The live character has *less* played time than the transfer claims,
        -- which no amount of playing can produce.
        return false, "this transfer is from further ahead than this character"
    end

    if difference > X.PLAYED_TOLERANCE then
        -- Section 38: the gap is what an old export used to erase later play
        -- would look like.
        return false, string.format(
            "%d minutes have been played since this was exported (limit %d)",
            floor(difference / 60), floor(X.PLAYED_TOLERANCE / 60))
    end

    -- Section 40: whatever this session tracked cleanly is credited rather than
    -- discarded. Capped at the real difference so it can never manufacture time.
    local sessionTracked = 0
    if V.Time and V.Time.GetSessionTracked then
        sessionTracked = Num(V.Time.GetSessionTracked(), 0)
    end
    if sessionTracked > difference then sessionTracked = difference end
    if sessionTracked < 0 then sessionTracked = 0 end

    -- Section 37, the half that was missing: the elapsed played time has to be
    -- *explained* by play this session actually watched, not merely be small.
    --
    -- Without this, the ten-minute tolerance is a ten-minute window to do
    -- something prohibited and then undo it -- export, break a rule, relog,
    -- import. The relog is what the check catches: a fresh session has tracked
    -- almost nothing, while the server's clock kept running through whatever
    -- was done before it. Legitimate transfers look nothing like that, because
    -- the minutes between export and import were either spent logged out (which
    -- the server does not count either) or spent playing here, tracked.
    local unaccounted = difference - sessionTracked
    if unaccounted > X.UNACCOUNTED_ALLOWANCE then
        return false, string.format(
            "%d minutes of play since this was exported cannot be accounted for; "
            .. "export again from the computer you were playing on",
            floor(unaccounted / 60) + 1)
    end

    return true, nil, sessionTracked
end

-- Pessimising merge (plan sections 37 and 40) ------------------------------------
--
-- An import brings state from elsewhere; it must never be able to *improve* on
-- what this machine has already seen with its own eyes. Section 40 says local
-- activity is not simply overwritten, and until now only tracked time was
-- merged -- so a record could be exported, a rule broken, and the export
-- imported back over the evidence.
--
-- The rule is the same one V.SetStatus enforces everywhere else: certification
-- only ever moves downward. Every field below therefore takes whichever side is
-- worse for the player, so a transfer can restore a history without erasing a
-- finding.

local function WorseStatus(a, b)
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    return (V.StatusRank(a) >= V.StatusRank(b)) and a or b
end

local function LowerTier(a, b)
    if type(a) ~= "number" then return b end
    if type(b) ~= "number" then return a end
    return a < b and a or b
end

local function HigherCount(a, b)
    return math.max(tonumber(a) or 0, tonumber(b) or 0)
end

local GAP_RANK = { OK = 1, WARNING = 2, SEVERE = 3 }

local function WorseGapBand(a, b)
    local ra, rb = GAP_RANK[a or "OK"] or 1, GAP_RANK[b or "OK"] or 1
    return (ra >= rb) and (a or "OK") or (b or "OK")
end

local function MergeWarnings(target, localWarnings)
    if type(localWarnings) ~= "table" then return end
    target = target or {}
    for kind, count in pairs(localWarnings) do
        target[kind] = HigherCount(target[kind], count)
    end
end

-- Fold everything this machine already knows into the freshly imported record.
local function PessimiseAgainstLocal(record, previous)
    if type(previous) ~= "table" then return false end

    local changed = false
    local pd, pf = previous.difficulty or {}, previous.selfFound or {}
    local rd, rf = record.difficulty, record.selfFound

    local function noteStatus(track, localStatus)
        local worse = WorseStatus(track.status, localStatus)
        if worse ~= track.status then
            track.status = worse
            changed = true
        end
    end

    noteStatus(rd, pd.status)
    noteStatus(rf, pf.status)

    -- A cap earned here outranks a looser one in the transfer.
    rd.highestVerifiedTier = LowerTier(rd.highestVerifiedTier, pd.highestVerifiedTier)
    rd.permanentCapTier    = LowerTier(rd.permanentCapTier, pd.permanentCapTier)
    rd.deathFloorTier      = LowerTier(rd.deathFloorTier, pd.deathFloorTier)
    rd.pendingCapTier      = LowerTier(rd.pendingCapTier, pd.pendingCapTier)

    rd.deaths           = HigherCount(rd.deaths, pd.deaths)
    rd.repairViolations = HigherCount(rd.repairViolations, pd.repairViolations)
    rf.violations       = HigherCount(rf.violations, pf.violations)
    if not rf.lastViolation and pf.lastViolation then
        rf.lastViolation = pf.lastViolation
    end
    if (rf.violations or 0) > 0 or (rd.repairViolations or 0) > 0 then changed = true end

    MergeWarnings(rd.warnings, pd.warnings)
    MergeWarnings(rf.warnings, pf.warnings)

    -- A suspension observed here survives the import, so a paused run cannot be
    -- un-paused by restoring an older string.
    if pf.suspended then rf.suspended = true end
    if pf.claimLapsed then rf.claimLapsed = true end
    if type(pf.restoreAtTracked) == "number" then
        rf.restoreAtTracked = math.max(tonumber(rf.restoreAtTracked) or 0, pf.restoreAtTracked)
    end

    local pt = previous.time or {}
    record.time.untrackedSeconds = HigherCount(record.time.untrackedSeconds, pt.untrackedSeconds)
    record.time.gapBand = WorseGapBand(record.time.gapBand, pt.gapBand)

    local pe = previous.economy or {}
    local pem, pei = pe.money or {}, pe.items or {}
    record.economy.money.unexplained = HigherCount(record.economy.money.unexplained, pem.unexplained)
    record.economy.money.anomalies   = HigherCount(record.economy.money.anomalies, pem.anomalies)
    record.economy.items.anomalies   = HigherCount(record.economy.items.anomalies, pei.anomalies)

    -- Keep whichever chain has seen more. A local chain that is further along
    -- covers events the export never knew about, and discarding it would throw
    -- away the tamper evidence for exactly those events.
    local pc = previous.chain or {}
    if (tonumber(pc.sequence) or 0) > (tonumber(record.chain.sequence) or 0) then
        record.chain.head = pc.head or record.chain.head
        record.chain.sequence = pc.sequence
    end

    return changed
end

-- Overwrite this character's record from a validated transfer.
local function ApplyFields(fields, serverPlayed, creditSeconds)
    local key, previousRecord = V.FindRecordKey()
    if not key then
        key = (Rustcore and Rustcore.GetCharacterKey and Rustcore.GetCharacterKey())
            or (UnitGUID and UnitGUID("player")) or (UnitName and UnitName("player")) or "player"
    end

    local record = {
        schemaVersion = V.SCHEMA_VERSION,
        createdAt     = Num(fields.cr, time and time() or 0),
        addonVersion  = V.GetAddonVersion(),
        identity      = V.BuildIdentity(),
        origin        = fields.org ~= "" and fields.org or "IMPORT",
        migrationComplete = true,
        importedAt    = time and time() or 0,
    }

    record.difficulty = V.NewTrack(fields.ds ~= "" and fields.ds or V.STATUS.UNVERIFIED)
    record.difficulty.highestVerifiedTier = Num(fields.dt, 0)
    record.difficulty.permanentCapTier    = tonumber(fields.dc)
    record.difficulty.pendingCapTier      = tonumber(fields.dp)
    record.difficulty.deathFloorTier      = tonumber(fields.dfl)
    record.difficulty.startedAtLevel      = tonumber(fields.dl)
    record.difficulty.currentTier         = V.GetCurrentTier()
    record.difficulty.deaths              = Num(fields.dd, 0)
    record.difficulty.repairViolations    = Num(fields.drv, 0)
    record.difficulty.warnings            = UnpackWarnings(fields.dw)

    record.selfFound = V.NewTrack(fields.ss ~= "" and fields.ss or V.STATUS.UNCERTAIN)
    record.selfFound.startedAtLevel   = tonumber(fields.sl)
    record.selfFound.claimed          = Num(fields.scl, 0) == 1
    record.selfFound.qualifyFromLevel = tonumber(fields.sql)
    record.selfFound.claimedAtLevel   = tonumber(fields.sal)
    record.selfFound.claimLapsed      = Num(fields.slp, 0) == 1 or nil
    record.selfFound.suspended        = Num(fields.ssp, 0) == 1 or nil
    record.selfFound.restoreAtTracked = tonumber(fields.srt)
    record.selfFound.violations       = Num(fields.sv, 0)
    record.selfFound.lastViolation    = fields.svr ~= "" and fields.svr or nil
    record.selfFound.warnings         = UnpackWarnings(fields.sw)

    record.time = {
        anchorPlayed       = Num(fields.ta, 0),
        lastServerPlayed   = serverPlayed,
        -- Section 40: the imported history plus the clean minutes this PC
        -- watched since login.
        trackedSinceAnchor = Num(fields.tt, 0) + (creditSeconds or 0),
        untrackedSeconds   = Num(fields.tu, 0),
        gapBand            = fields.tb ~= "" and fields.tb or "OK",
        sessionTracked     = nil,
        lastPlayedCheck    = time and time() or nil,
    }

    record.economy = {
        money = {
            last        = tonumber(fields.eml),
            unexplained = Num(fields.emu, 0),
            anomalies   = Num(fields.ema, 0),
        },
        items = {
            anomalies = Num(fields.eia, 0),
        },
    }

    local slots = UnpackDurability(fields.du)
    if next(slots) then
        record.durabilityState = { slots = slots, established = true }
    end

    -- The chain continues from where the export left off rather than starting
    -- again, so the imported head still covers everything that came before.
    record.chain = {
        head     = fields.ch or "",
        sequence = Num(fields.cs, 0),
        events   = {},
    }

    -- Fold in anything this machine already observed, before the imported record
    -- becomes the live one. Nothing below this point can raise a certification.
    local keptLocal = PessimiseAgainstLocal(record, previousRecord)
    record.importKeptLocalFindings = keptLocal or nil

    V.GetStore()[key] = record

    -- Stats (section 41). Merged the same way as everything else rather than
    -- replaced: these only ever count upward during play, so taking the higher
    -- of the two sides restores a history from another PC without letting an old
    -- string quietly undo losses recorded here since it was written.
    local stats = GetStatsTable()
    if stats then
        stats.destroyedItems   = HigherCount(stats.destroyedItems, Num(fields.xd, 0))
        stats.rustedItems      = HigherCount(stats.rustedItems, Num(fields.xr, 0))
        local importedIlvl = Num(fields.xbi, 0)
        if importedIlvl > (tonumber(stats.bestItemLostIlvl) or 0) then
            stats.bestItemLostIlvl = importedIlvl
            stats.bestItemLostLink = fields.xbl ~= "" and fields.xbl or nil
        end
    end

    if V.Integrity and V.Integrity.Append then
        V.Integrity.Append("IMPORT", {
            played  = floor(serverPlayed or 0),
            credit  = floor(creditSeconds or 0),
            from    = fields.av or "",
        })
    end
    if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end

    return record
end

-- Section 35. Parses, then waits for a fresh /played before committing.
function X.BeginImport(text, callback)
    local fields, err = X.Parse(text)
    if not fields then
        callback(false, err)
        return
    end

    local done = false
    -- `played` comes straight from the TIME_PLAYED_MSG payload rather than from
    -- Time.lua's stored figure: both modules listen for that event and the order
    -- the two frames are called in is not defined, so reading Time's copy could
    -- pick up the previous poll's value instead of the reply just received.
    local function finish(played)
        if done then return end
        done = true

        local serverPlayed = played or (V.Time and V.Time.GetLastServerPlayed()) or 0
        local ok, reason, credit = X.Reconcile(fields, serverPlayed)
        if not ok then
            callback(false, reason)
            return
        end

        ApplyFields(fields, serverPlayed, credit)

        -- The imported money figure belongs to the other PC's last reading, so
        -- the next PLAYER_MONEY here would otherwise measure a delta against a
        -- number that was never this session's. Adopt the real balance instead.
        if V.Money and V.Money.Rebase then V.Money.Rebase() end
        if V.Inventory and V.Inventory.Rebase then V.Inventory.Rebase() end

        -- Repaint everything the imported state could have changed.
        if RustcoreDragon then
            if RustcoreDragon.RefreshPlayerFrame then RustcoreDragon.RefreshPlayerFrame() end
            if RustcoreDragon.RefreshTargetFrame then RustcoreDragon.RefreshTargetFrame() end
        end
        if RustcoreSelfFoundBuff and RustcoreSelfFoundBuff.Refresh then
            RustcoreSelfFoundBuff.Refresh()
        end
        if RustcoreStats and RustcoreStats.Refresh then RustcoreStats.Refresh() end

        local record = V.GetRecord()
        local message = string.format("Verification imported. %d clean minute(s) on this PC kept.",
            floor((credit or 0) / 60))
        if record and record.importKeptLocalFindings then
            -- Said plainly, because otherwise a player would see "imported" and
            -- reasonably expect the imported status to be the one they now have.
            message = message .. " This computer had already recorded something "
                .. "the transfer did not, so that was kept."
        end
        callback(true, message)
    end

    X.pendingImport = finish
    if V.Time and V.Time.Request then V.Time.Request() end

    if C_Timer and C_Timer.After then
        C_Timer.After(X.PLAYED_TIMEOUT, function()
            if X.pendingImport ~= finish then return end
            X.pendingImport = nil
            callback(false, "the server did not report played time; try again")
            done = true
        end)
    else
        finish()
    end
end

-- The /played reply both flows are waiting on. `totalPlayed` is the payload
-- figure, forwarded so neither flow has to read Time.lua's copy.
function X.OnTimePlayed(totalPlayed)
    local exportCallback = X.pendingExport
    local importCallback = X.pendingImport
    X.pendingExport, X.pendingImport = nil, nil
    if exportCallback then exportCallback(totalPlayed) end
    if importCallback then importCallback(totalPlayed) end
end

function X.Init()
    if X.initialized then return end
    X.initialized = true

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("TIME_PLAYED_MSG")
    frame:SetScript("OnEvent", function(_, _, totalPlayed)
        local ok, err = pcall(X.OnTimePlayed, totalPlayed)
        if not ok then
            print("|cffff4444Rustcore ERROR:|r transfer: " .. tostring(err))
        end
    end)
    X.frame = frame
end
