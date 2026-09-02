-- RaapWhistle: lowers the graphicsGroundClutter CVar so ground-spawn quest
-- objects become visible, and restores it afterwards.
-- Manual toggle (minimap button, slash command, keybind) always works.
-- The automatic toggle is driven by a whitelist of quest IDs plus the zones
-- each of those quests has been seen in.

local ADDON_NAME = "RaapWhistle"

-- Every library is optional: the addon must load and stay usable without Ace3.
local function GetLib(name)
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, name, true)
    if ok then return lib end
    return nil
end

-- Fallback locale table, used when AceLocale is missing or has no locale registered.
local L = {
    ["RaapWhistle"] = "RaapWhistle",
    ["Ground clutter set to high."] = "Ground clutter set to high.",
    ["Ground clutter set to low."] = "Ground clutter set to low.",
    ["Quest objective complete, ground clutter restored."] = "Quest objective complete, ground clutter restored.",
    ["Quest objective started, ground clutter reduced."] = "Quest objective started, ground clutter reduced.",
    ["Could not change ground clutter."] = "Could not change ground clutter.",
    ["Options are unavailable (Ace3 is not loaded)."] = "Options are unavailable (Ace3 is not loaded).",
    ["Could not open the options panel."] = "Could not open the options panel.",
    ["Auto Clutter Toggle"] = "Auto Clutter Toggle",
    ["Automatically toggle ground clutter based on quest state"] = "Automatically toggle ground clutter based on quest state",
    ["Verbose"] = "Verbose",
    ["Announce automatic ground clutter changes in chat"] = "Announce automatic ground clutter changes in chat",
    ["Low Clutter Value"] = "Low Clutter Value",
    ["Value for reduced ground clutter"] = "Value for reduced ground clutter",
    ["High Clutter Value"] = "High Clutter Value",
    ["Value for restored ground clutter"] = "Value for restored ground clutter",
    ["Restore To"] = "Restore To",
    ["What ground clutter is restored to"] = "What ground clutter is restored to",
    ["Whatever it was before"] = "Whatever it was before",
    ["The High Clutter Value"] = "The High Clutter Value",
    ["Detect Search Quests"] = "Detect Search Quests",
    ["Track quests with an objective you have to click on the ground"] = "Track quests with an objective you have to click on the ground",
    ["Also Detect Collection Quests"] = "Also Detect Collection Quests",
    ["Much broader: matches every quest that counts items, including drops from kills"] = "Much broader: matches every quest that counts items, including drops from kills",
    ["Quest Whitelist"] = "Quest Whitelist",
    ["Comma-separated quest IDs to auto-toggle"] = "Comma-separated quest IDs to auto-toggle",
    ["Profiles"] = "Profiles",
    ["Toggle Ground Clutter"] = "Toggle Ground Clutter",
    ["Peek Ground Clutter"] = "Peek Ground Clutter",
    ["Peek Duration"] = "Peek Duration",
    ["How long a peek lasts, in seconds"] = "How long a peek lasts, in seconds",
    ["Ground clutter lowered for %d seconds."] = "Ground clutter lowered for %d seconds.",
    ["Peek ended, ground clutter restored."] = "Peek ended, ground clutter restored.",
}

do
    local AceLocale = GetLib("AceLocale-3.0")
    if AceLocale and AceLocale.GetLocale then
        local ok, locale = pcall(AceLocale.GetLocale, AceLocale, ADDON_NAME, true)
        if ok and type(locale) == "table" then
            L = locale
        end
    end
end

local function Print(msg)
    print("RaapWhistle: " .. tostring(msg))
end

-- GetTime is absent outside the game; 0 keeps the throttles harmlessly permissive.
local function Now()
    return (GetTime and GetTime()) or 0
end

-- CVar access -----------------------------------------------------------------

local CLUTTER_CVAR = "graphicsGroundClutter"
local CLUTTER_MIN = 0

local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar
local GetCVarDefaultValue = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault

-- graphicsGroundClutter is an index into the client's quality levels. Its real
-- maximum is unverified and may be lower than the 9 the sliders offer, so writes
-- are clamped and the ceiling is corrected from whatever the client accepts.
local clutterMax = 9

-- Assigned once the options table exists, so a corrected ceiling can be pushed
-- into the sliders instead of leaving them stale until the next /reload.
local ClutterMaxChanged

local function GetClutter()
    if not GetCVarValue then return nil end
    local ok, value = pcall(GetCVarValue, CLUTTER_CVAR)
    if not ok then return nil end
    return tonumber(value)
end

local function GetClutterDefault()
    if not GetCVarDefaultValue then return nil end
    local ok, value = pcall(GetCVarDefaultValue, CLUTTER_CVAR)
    if not ok then return nil end
    return tonumber(value)
end

do
    local default = GetClutterDefault()
    if default and default > clutterMax then
        clutterMax = default
    end
end

local function ClampClutter(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value + 0.5)
    if value < CLUTTER_MIN then value = CLUTTER_MIN end
    if value > clutterMax then value = clutterMax end
    return value
end

local function SetClutter(value)
    value = ClampClutter(value)
    if not value or not SetCVarValue then return nil end
    local ok = pcall(SetCVarValue, CLUTTER_CVAR, value)
    if not ok then return nil end
    local applied = GetClutter()
    if applied and applied < value then
        clutterMax = applied -- the client refused that level; remember the real ceiling
        if ClutterMaxChanged then ClutterMaxChanged() end
    end
    return applied or value
end

-- Client API shims ------------------------------------------------------------

local function GetCurrentZoneID()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then return mapID end
    end
    return nil
end

local function GetNumQuestEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return C_QuestLog.GetNumQuestLogEntries() or 0
    end
    if GetNumQuestLogEntries then
        return (GetNumQuestLogEntries()) or 0
    end
    return 0
end

local function GetQuestIDForIndex(index)
    index = tonumber(index)
    if not index or index < 1 then return nil end
    if C_QuestLog then
        if C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(index)
            if not info or info.isHeader then return nil end
            return info.questID
        end
        if C_QuestLog.GetQuestIDForLogIndex then
            return C_QuestLog.GetQuestIDForLogIndex(index)
        end
    end
    if GetQuestLogTitle then
        local title, _, _, isHeader = GetQuestLogTitle(index)
        if not title or isHeader then return nil end
        return select(8, GetQuestLogTitle(index))
    end
    return nil
end

local function GetQuestTitle(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        return info and info.title
    end
    if GetQuestLogTitle then
        return (GetQuestLogTitle(index))
    end
    return nil
end

local function GetSelectedQuestID()
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local questID = C_QuestLog.GetSelectedQuest()
        if questID and questID > 0 then return questID end
    end
    if GetQuestLogSelection then
        return GetQuestIDForIndex(GetQuestLogSelection())
    end
    return nil
end

local function IsQuestInLog(questID)
    if not questID then return false end
    if C_QuestLog then
        if C_QuestLog.IsOnQuest then
            return C_QuestLog.IsOnQuest(questID) and true or false
        end
        if C_QuestLog.GetLogIndexForQuestID then
            return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
        end
    end
    for i = 1, GetNumQuestEntries() do
        if GetQuestIDForIndex(i) == questID then return true end
    end
    return false
end

-- Quest objectives are typed, and one of the types is exactly what this addon
-- exists for: "object" means a world object you click, which is the buried crate
-- or half-hidden clicky the grass is hiding.
local function GetObjectiveTypes(index, questID)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        if not ok or type(objectives) ~= "table" or #objectives == 0 then return nil end
        local types = {}
        for _, objective in ipairs(objectives) do
            if type(objective) == "table" and objective.type then
                types[objective.type] = true
            end
        end
        return next(types) and types or nil
    end
    -- Classic keys objectives off the quest log index. Passing the index as the
    -- second argument avoids SelectQuestLogEntry, which would move the player's
    -- own quest log selection out from under them.
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local ok, count = pcall(GetNumQuestLeaderBoards, index)
        if not ok or not count or count < 1 then return nil end
        local types = {}
        for i = 1, count do
            local read, _, objectiveType = pcall(GetQuestLogLeaderBoard, i, index)
            if read and objectiveType then types[objectiveType] = true end
        end
        return next(types) and types or nil
    end
    return nil
end

-- Cached per quest, because scanning every objective of a full quest log on every
-- QUEST_LOG_UPDATE burst is wasteful. Only definitive answers are stored: quest
-- data is not always available straight after login, and a nil there has to be
-- retried rather than remembered as a no.
local objectiveTypeCache = {}

-- Saved variables -------------------------------------------------------------

local defaults = {
    profile = {
        autoClutter = true,
        -- Detection defaults to "object" objectives only. Ground spawns that count
        -- items report as "item", which would also match every "collect 8 murloc
        -- fins" kill-quest and dim the grass nearly everywhere, defeating the
        -- point - so the broader match is opt-in.
        autoDetect = true,
        detectItemObjectives = false,
        verbose = false,
        -- "remembered" restores whatever the player was running at before the
        -- addon lowered it; "fixed" restores clutterHigh. Restoring to a constant
        -- silently raises the graphics of anyone not already on the client
        -- default, so remembering is the default.
        restoreMode = "remembered",
        peekDuration = 20,
        clutterLow = CLUTTER_MIN,
        clutterHigh = GetClutterDefault() or clutterMax,
        questWhitelist = {},
        questIgnore = {},
        minimap = { hide = false },
    },
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(type(dst[k]) == "table" and dst[k] or {}, v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Placeholder so nothing indexes a nil profile before ADDON_LOADED; replaced by
-- the real (persistent) store in InitDB.
local db = { profile = CopyDefaults({}, defaults.profile) }
local dbReady = false

-- clutterLow must stay strictly below clutterHigh. If they meet, CurrentState()
-- reports "low" for every value and the toggle stops being able to tell the two
-- states apart. Called on load, where a hand-edited or older saved value could
-- be anything.
local function NormalizeClutterRange()
    local profile = db.profile
    local low = ClampClutter(profile.clutterLow) or CLUTTER_MIN
    local high = ClampClutter(profile.clutterHigh) or clutterMax
    if high <= low then
        if low < clutterMax then
            high = low + 1
        else
            low = math.max(CLUTTER_MIN, clutterMax - 1)
            high = clutterMax
        end
    end
    profile.clutterLow, profile.clutterHigh = low, high
    profile.savedClutter = ClampClutter(profile.savedClutter)
    if profile.restoreMode ~= "fixed" then profile.restoreMode = "remembered" end
end

-- Whitelist shape:
--   profile.questWhitelist[questID] = { zones = { [uiMapID] = true }, auto = true? }
-- auto marks an entry the addon added by itself; manual entries are never
-- touched by detection and survive it being switched off.
-- An empty zones table means "no zone learned yet"; the current zone is recorded
-- the first time the quest is accepted or seen in the quest log.
local function Whitelist()
    local profile = db.profile
    profile.questWhitelist = profile.questWhitelist or {}
    return profile.questWhitelist
end

local function Ignored()
    local profile = db.profile
    profile.questIgnore = profile.questIgnore or {}
    return profile.questIgnore
end

-- Rebuilds the whitelist into the shape above, converting the older
-- "= true" / "= zoneID" values that earlier versions stored.
local function NormalizeWhitelist()
    local old = Whitelist()
    local new = {}
    for questID, entry in pairs(old) do
        local id = tonumber(questID)
        if id then
            local zones = {}
            if type(entry) == "table" and type(entry.zones) == "table" then
                for zoneID in pairs(entry.zones) do
                    local zone = tonumber(zoneID)
                    if zone then zones[zone] = true end
                end
            elseif type(entry) == "number" then
                zones[entry] = true
            end
            new[id] = {
                zones = zones,
                auto = (type(entry) == "table" and entry.auto) or nil,
            }
        end
    end
    db.profile.questWhitelist = new

    local ignore = {}
    for questID in pairs(Ignored()) do
        local id = tonumber(questID)
        if id then ignore[id] = true end
    end
    db.profile.questIgnore = ignore
end

-- true / false / nil, where nil means "cannot tell yet, ask again".
local function QuestHasGroundObjective(index, questID)
    local types = objectiveTypeCache[questID]
    if not types then
        types = GetObjectiveTypes(index, questID)
        if not types then return nil end
        objectiveTypeCache[questID] = types
    end
    if types["object"] then return true end
    if db.profile.detectItemObjectives and types["item"] then return true end
    return false
end

local function AddToWhitelist(questID)
    local whitelist = Whitelist()
    if not whitelist[questID] then
        whitelist[questID] = { zones = {} }
    end
    return whitelist[questID]
end

-- A zone is only learned once the player is still there this many seconds later,
-- so flying over a zone on the way somewhere else never gets it tracked.
local ZONE_DWELL = 30
local MAX_ZONES = 8

-- questID -> { zone = uiMapID, since = timestamp }. Deliberately not persisted:
-- a candidate that did not ripen before a reload was not worth keeping.
local zoneCandidates = {}

local function CountZones(entry)
    local n = 0
    for _ in pairs(entry.zones) do n = n + 1 end
    return n
end

-- Explicit, user-initiated learning: /raapwhistle add means "track this quest
-- here", so it skips the dwell filter.
local function RememberZone(questID, zoneID)
    local entry = Whitelist()[questID]
    if not entry or not zoneID then return false end
    if entry.zones[zoneID] then return false end
    if CountZones(entry) >= MAX_ZONES then return false end
    entry.zones[zoneID] = true
    zoneCandidates[questID] = nil
    return true
end

-- Passive learning: records that questID was seen in zoneID, and promotes the
-- zone only on a later sighting at least ZONE_DWELL apart. Returns true if the
-- zone was learned, false while the candidate is still ripening.
local function NoteZone(questID, zoneID, now)
    local entry = Whitelist()[questID]
    if not entry or not zoneID then return false end
    if entry.zones[zoneID] then return true end
    local candidate = zoneCandidates[questID]
    if not candidate or candidate.zone ~= zoneID then
        zoneCandidates[questID] = { zone = zoneID, since = now }
        return false
    end
    if now - candidate.since < ZONE_DWELL then return false end
    zoneCandidates[questID] = nil
    if CountZones(entry) >= MAX_ZONES then return false end
    entry.zones[zoneID] = true
    return true
end

-- AceDB:New(..., true) stores everything in one shared "Default" profile; the
-- fallback store below uses the same key so both paths see the same settings.
local DEFAULT_PROFILE = "Default"

local function InitDB()
    if dbReady then return end
    dbReady = true

    local AceDB = GetLib("AceDB-3.0")
    if AceDB then
        local ok, store = pcall(AceDB.New, AceDB, "RaapWhistleDB", defaults, true)
        if ok and type(store) == "table" and type(store.profile) == "table" then
            db = store
            NormalizeWhitelist()
            NormalizeClutterRange()
            return
        end
    end

    -- No AceDB: keep persistence with a plain saved-variable table of the same
    -- shape, using the same shared "Default" profile AceDB:New(..., true) picks.
    if type(RaapWhistleDB) ~= "table" then RaapWhistleDB = {} end
    if type(RaapWhistleDB.profiles) ~= "table" then RaapWhistleDB.profiles = {} end
    if type(RaapWhistleDB.profileKeys) ~= "table" then RaapWhistleDB.profileKeys = {} end
    local charKey = ((UnitName and UnitName("player")) or "Unknown")
        .. " - " .. ((GetRealmName and GetRealmName()) or "Unknown")
    local key = RaapWhistleDB.profileKeys[charKey] or DEFAULT_PROFILE
    RaapWhistleDB.profileKeys[charKey] = key
    RaapWhistleDB.profiles[key] = CopyDefaults(RaapWhistleDB.profiles[key] or {}, defaults.profile)
    db = { profile = RaapWhistleDB.profiles[key] }
    NormalizeWhitelist()
    NormalizeClutterRange()
end

-- Clutter state ---------------------------------------------------------------

local activeQuests = {} -- questID -> true for whitelisted quests currently in the log
local appliedState      -- "low" / "high": last state this addon applied
local errorShown = false

-- Timestamp a running peek expires at, nil when no peek is running. Declared up
-- here because the automatic logic has to know to keep its hands off.
local peekUntil

local function PeekActive()
    return peekUntil ~= nil
end

local function CurrentState()
    local current = GetClutter()
    if not current then return appliedState end
    local low = ClampClutter(db.profile.clutterLow) or CLUTTER_MIN
    if current <= low then return "low" end
    return "high"
end

-- What "high" means. Restoring to a configured constant silently changes the
-- graphics of anyone whose clutter was not already sitting on that value, so by
-- default we hand back whatever was captured on the way down.
local function RestoreTarget()
    local profile = db.profile
    if profile.restoreMode ~= "fixed" then
        local saved = ClampClutter(profile.savedClutter)
        if saved then return saved end
    end
    return ClampClutter(profile.clutterHigh) or GetClutterDefault() or clutterMax
end

local function ApplyState(state, announce)
    local profile = db.profile
    local target
    if state == "low" then
        -- Capture only when not already low, or lowering twice would remember
        -- the low value as the thing to restore.
        if CurrentState() ~= "low" then
            local current = GetClutter()
            if current then profile.savedClutter = current end
        end
        target = ClampClutter(profile.clutterLow) or CLUTTER_MIN
    else
        target = RestoreTarget()
    end
    if SetClutter(target) == nil then
        -- always report a user-initiated failure, but only once for automatic ones
        if announce or not errorShown then
            Print(L["Could not change ground clutter."])
            errorShown = true
        end
        return false
    end
    errorShown = false
    appliedState = state
    if announce then
        Print(state == "low" and L["Ground clutter set to low."] or L["Ground clutter set to high."])
    end
    return true
end

-- User initiated: always allowed, always announced, ignores autoClutter.
local function ToggleGroundClutter()
    peekUntil = nil -- an explicit toggle takes over from any running peek
    ApplyState(CurrentState() == "low" and "high" or "low", true)
end

local function DesiredAutoState()
    local zoneID = GetCurrentZoneID()
    if zoneID then
        local whitelist = Whitelist()
        for questID in pairs(activeQuests) do
            local entry = whitelist[questID]
            if entry and entry.zones[zoneID] then
                return "low"
            end
        end
    end
    return "high"
end

local function UpdateAutoClutter()
    local profile = db.profile
    if not profile.autoClutter then return end
    if PeekActive() then return end -- a peek is explicit; do not fight it
    local desired = DesiredAutoState()
    if desired == CurrentState() then
        appliedState = desired -- already in the desired state; stay quiet
        return
    end
    if ApplyState(desired, false) and profile.verbose then
        Print(desired == "low" and L["Quest objective started, ground clutter reduced."]
            or L["Quest objective complete, ground clutter restored."])
    end
end

-- Peek ------------------------------------------------------------------------
-- The actual use case is "let me see for twenty seconds", not a sticky toggle,
-- and a peek that restores itself cannot leave the client stuck on low grass.

local PEEK_MIN, PEEK_MAX = 1, 600

local SchedulePeekExpiry, CheckPeek -- mutually recursive; see below
local peekFrame

local function EndPeek()
    if not peekUntil then return end
    peekUntil = nil
    -- Walking into a tracked quest zone mid-peek means low is now the correct
    -- state on its own merits, so end the peek without raising clutter again.
    if db.profile.autoClutter and DesiredAutoState() == "low" then
        appliedState = "low"
        return
    end
    if ApplyState("high", false) then
        Print(L["Peek ended, ground clutter restored."])
    end
end

-- No C_Timer on the oldest clients, so drive the expiry from OnUpdate instead.
-- Created on demand: every client that has C_Timer never needs this frame.
local function StartPeekTicker()
    if not peekFrame then
        if not CreateFrame then return end
        peekFrame = CreateFrame("Frame")
    end
    peekFrame:SetScript("OnUpdate", function(self)
        if not peekUntil then
            self:SetScript("OnUpdate", nil)
            return
        end
        if Now() >= peekUntil then
            self:SetScript("OnUpdate", nil)
            EndPeek()
        end
    end)
end

function SchedulePeekExpiry()
    if not peekUntil then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0.1, peekUntil - Now()), CheckPeek)
        return
    end
    StartPeekTicker()
end

-- A peek that was extended leaves an early timer behind, so re-check the clock
-- rather than trusting the timer to mean the peek is over.
function CheckPeek()
    if not peekUntil then return end
    if Now() >= peekUntil then
        EndPeek()
    else
        SchedulePeekExpiry()
    end
end

local function StartPeek(seconds)
    local profile = db.profile
    seconds = tonumber(seconds) or tonumber(profile.peekDuration) or 20
    seconds = math.floor(seconds)
    if seconds < PEEK_MIN then seconds = PEEK_MIN end
    if seconds > PEEK_MAX then seconds = PEEK_MAX end

    -- Do not start the clock until the CVar write has actually landed.
    if not PeekActive() and not ApplyState("low", false) then return end
    peekUntil = Now() + seconds
    Print(string.format(L["Ground clutter lowered for %d seconds."], seconds))
    SchedulePeekExpiry()
end

-- Quest tracking --------------------------------------------------------------

-- Returns true while at least one quest still has a zone candidate waiting out
-- its dwell time, so the caller knows another look is needed.
local function ScanQuestLog()
    local whitelist = Whitelist()
    local zoneID = GetCurrentZoneID()
    local now = Now()
    local seen = {}
    local ripening = false
    local profile = db.profile
    local ignore = Ignored()
    for i = 1, GetNumQuestEntries() do
        local questID = GetQuestIDForIndex(i)
        local entry = questID and whitelist[questID]
        if questID and not entry and profile.autoDetect and not ignore[questID] then
            if QuestHasGroundObjective(i, questID) then
                entry = AddToWhitelist(questID)
                entry.auto = true
                if profile.verbose then
                    Print(string.format("Tracking quest %d - it has a search objective.",
                        questID))
                end
            end
        end
        -- An auto entry stands down while detection is off, but is kept: its
        -- learned zones are worth having if detection is switched back on.
        if entry and not (entry.auto and not profile.autoDetect) then
            seen[questID] = true
            if zoneID and not NoteZone(questID, zoneID, now) then
                ripening = true
            end
        end
    end
    for questID in pairs(zoneCandidates) do
        if not seen[questID] then zoneCandidates[questID] = nil end
    end
    activeQuests = seen
    return ripening
end

local lastScan = 0
local scanPending = false
local dwellPending = false
local DoScan -- forward declaration: ScheduleDwellCheck calls back into it

-- A candidate ripens with nothing but the passage of time, and quest events may
-- never fire again while the player simply stands there, so look again later.
local function ScheduleDwellCheck()
    if dwellPending or not (C_Timer and C_Timer.After) then return end
    dwellPending = true
    C_Timer.After(ZONE_DWELL + 1, function()
        dwellPending = false
        DoScan()
    end)
end

function DoScan()
    lastScan = Now()
    local ripening = ScanQuestLog()
    UpdateAutoClutter()
    if ripening then ScheduleDwellCheck() end
end

-- QUEST_LOG_UPDATE / UNIT_QUEST_LOG_CHANGED fire in bursts, so throttle them.
local function RequestScan()
    local now = Now()
    if now - lastScan >= 1 then
        DoScan()
    elseif not scanPending and C_Timer and C_Timer.After then
        scanPending = true
        C_Timer.After(1, function()
            scanPending = false
            DoScan()
        end)
    end
end

local function OnQuestGone(questID)
    questID = tonumber(questID)
    if questID then
        activeQuests[questID] = nil
    end
    UpdateAutoClutter()
    RequestScan()
end

-- Broker / minimap button -----------------------------------------------------

local miniButton
do
    local LDB = GetLib("LibDataBroker-1.1")
    if LDB and LDB.NewDataObject then
        local ok, object = pcall(LDB.NewDataObject, LDB, ADDON_NAME, {
            type = "data source",
            text = L["RaapWhistle"],
            icon = "Interface\\ICONS\\Ability_hunter_beastcall",
            OnClick = function()
                ToggleGroundClutter()
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then return end
                tooltip:AddLine(L["RaapWhistle"])
                tooltip:AddLine(L["Toggle Ground Clutter"])
            end,
        })
        if ok then miniButton = object end
    end
end

local function RegisterMinimapIcon()
    if not miniButton then return end
    local icon = GetLib("LibDBIcon-1.0")
    if not icon or not icon.Register then return end
    local profile = db.profile
    if type(profile.minimap) ~= "table" then profile.minimap = { hide = false } end
    pcall(icon.Register, icon, ADDON_NAME, miniButton, profile.minimap)
end

-- Options ---------------------------------------------------------------------

local optionsFrame

local function OpenOptions()
    local AceConfigDialog = GetLib("AceConfigDialog-3.0")
    -- Ace3 genuinely absent is a different problem from a panel that will not
    -- open, and reporting them with the same message sends you hunting for the
    -- wrong thing.
    if not optionsFrame or not AceConfigDialog then
        Print(L["Options are unavailable (Ace3 is not loaded)."])
        return
    end

    if Settings and Settings.OpenToCategory then
        local category = optionsFrame.categoryID or optionsFrame.name or ADDON_NAME
        -- OpenToCategory returns false for an unknown category rather than
        -- erroring, so pcall succeeding is not the same as the panel opening.
        local ok, opened = pcall(Settings.OpenToCategory, category)
        if ok and opened ~= false then return end
    end

    if InterfaceOptionsFrame_OpenToCategory then
        -- Blizzard bug: the first call only expands the category list.
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        if pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame) then return end
    end

    -- Last resort, and the only one that does not depend on the client's own
    -- options frame: AceConfigDialog's standalone window. Everything the panel
    -- offers is reachable here too.
    if AceConfigDialog.Open
        and pcall(AceConfigDialog.Open, AceConfigDialog, ADDON_NAME) then
        return
    end

    Print(L["Could not open the options panel."])
end

local function RegisterOptions()
    local AceConfig = GetLib("AceConfig-3.0")
    local AceConfigDialog = GetLib("AceConfigDialog-3.0")
    if not AceConfig or not AceConfigDialog then return end

    local options = {
        name = ADDON_NAME,
        type = "group",
        args = {
            autoClutter = {
                order = 10,
                type = "toggle",
                name = L["Auto Clutter Toggle"],
                desc = L["Automatically toggle ground clutter based on quest state"],
                get = function() return db.profile.autoClutter end,
                set = function(_, val)
                    db.profile.autoClutter = val
                    if val then UpdateAutoClutter() end
                end,
            },
            autoDetect = {
                order = 15,
                type = "toggle",
                name = L["Detect Search Quests"],
                desc = L["Track quests with an objective you have to click on the ground"],
                get = function() return db.profile.autoDetect end,
                set = function(_, val)
                    db.profile.autoDetect = val
                    ScanQuestLog()
                    UpdateAutoClutter()
                end,
            },
            detectItemObjectives = {
                order = 17,
                type = "toggle",
                name = L["Also Detect Collection Quests"],
                desc = L["Much broader: matches every quest that counts items, including drops from kills"],
                disabled = function() return not db.profile.autoDetect end,
                get = function() return db.profile.detectItemObjectives end,
                set = function(_, val)
                    db.profile.detectItemObjectives = val
                    ScanQuestLog()
                    UpdateAutoClutter()
                end,
            },
            verbose = {
                order = 20,
                type = "toggle",
                name = L["Verbose"],
                desc = L["Announce automatic ground clutter changes in chat"],
                get = function() return db.profile.verbose end,
                set = function(_, val) db.profile.verbose = val end,
            },
            peekDuration = {
                order = 25,
                type = "range",
                name = L["Peek Duration"],
                desc = L["How long a peek lasts, in seconds"],
                min = PEEK_MIN, max = 120, step = 1,
                get = function() return db.profile.peekDuration end,
                set = function(_, val)
                    local seconds = math.floor(tonumber(val) or 20)
                    if seconds < PEEK_MIN then seconds = PEEK_MIN end
                    if seconds > PEEK_MAX then seconds = PEEK_MAX end
                    db.profile.peekDuration = seconds
                end,
            },
            clutterLow = {
                order = 30,
                type = "range",
                name = L["Low Clutter Value"],
                desc = L["Value for reduced ground clutter"],
                min = CLUTTER_MIN, max = clutterMax, step = 1,
                get = function() return db.profile.clutterLow end,
                set = function(_, val)
                    local profile = db.profile
                    local low = ClampClutter(val) or CLUTTER_MIN
                    if low >= profile.clutterHigh then
                        -- push high out of the way rather than refusing the edit
                        profile.clutterHigh = math.min(clutterMax, low + 1)
                        if profile.clutterHigh <= low then
                            low = math.max(CLUTTER_MIN, profile.clutterHigh - 1)
                        end
                    end
                    profile.clutterLow = low
                end,
            },
            clutterHigh = {
                order = 40,
                type = "range",
                name = L["High Clutter Value"],
                desc = L["Value for restored ground clutter"],
                min = CLUTTER_MIN, max = clutterMax, step = 1,
                get = function() return db.profile.clutterHigh end,
                set = function(_, val)
                    local profile = db.profile
                    local high = ClampClutter(val) or clutterMax
                    if high <= profile.clutterLow then
                        profile.clutterLow = math.max(CLUTTER_MIN, high - 1)
                        if profile.clutterLow >= high then
                            high = math.min(clutterMax, profile.clutterLow + 1)
                        end
                    end
                    profile.clutterHigh = high
                end,
                disabled = function() return db.profile.restoreMode ~= "fixed" end,
            },
            restoreMode = {
                order = 45,
                type = "select",
                name = L["Restore To"],
                desc = L["What ground clutter is restored to"],
                values = function()
                    return {
                        remembered = L["Whatever it was before"],
                        fixed = L["The High Clutter Value"],
                    }
                end,
                get = function() return db.profile.restoreMode end,
                set = function(_, val)
                    db.profile.restoreMode = (val == "fixed") and "fixed" or "remembered"
                end,
            },
            questWhitelist = {
                order = 50,
                type = "input",
                name = L["Quest Whitelist"],
                desc = L["Comma-separated quest IDs to auto-toggle"],
                get = function()
                    local ids = {}
                    for questID in pairs(Whitelist()) do ids[#ids + 1] = questID end
                    table.sort(ids)
                    return table.concat(ids, ", ")
                end,
                set = function(_, val)
                    local previous = Whitelist()
                    local new = {}
                    for id in string.gmatch(val or "", "%d+") do
                        local questID = tonumber(id)
                        if questID then
                            new[questID] = previous[questID] or { zones = {} }
                        end
                    end
                    db.profile.questWhitelist = new
                    ScanQuestLog()
                    UpdateAutoClutter()
                end,
            },
        },
    }

    local AceDBOptions = GetLib("AceDBOptions-3.0")
    if AceDBOptions and db.GetCurrentProfile then
        local ok, profileOptions = pcall(AceDBOptions.GetOptionsTable, AceDBOptions, db)
        if ok and type(profileOptions) == "table" then
            profileOptions.order = 90
            options.args.profiles = profileOptions
        end
    end

    -- AceConfigRegistry types min/max as plain numbers, so the sliders cannot
    -- read the ceiling through a function. It keeps our table by reference and
    -- re-reads it whenever the dialog opens, so update it in place instead.
    ClutterMaxChanged = function()
        options.args.clutterLow.max = clutterMax
        options.args.clutterHigh.max = clutterMax
        NormalizeClutterRange()
        local registry = GetLib("AceConfigRegistry-3.0")
        if registry and registry.NotifyChange then
            pcall(registry.NotifyChange, registry, ADDON_NAME)
        end
    end

    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    optionsFrame = AceConfigDialog:AddToBlizOptions(ADDON_NAME, ADDON_NAME)
    if options.args.profiles then
        AceConfigDialog:AddToBlizOptions(ADDON_NAME, L["Profiles"], ADDON_NAME, "profiles")
    end
end

-- Slash command ---------------------------------------------------------------

local function SlashAdd(arg)
    local questID
    local index = tonumber(arg)
    if index and index > 0 then
        questID = GetQuestIDForIndex(index)
    else
        questID = GetSelectedQuestID()
    end
    questID = tonumber(questID)
    if not questID then
        Print("Could not determine a quest ID. Select a quest in the quest log or pass its index.")
        return
    end
    Ignored()[questID] = nil -- adding it by hand overrides an earlier ignore
    AddToWhitelist(questID).auto = nil
    if IsQuestInLog(questID) then
        RememberZone(questID, GetCurrentZoneID())
    end
    Print("Added quest ID " .. questID .. " to the whitelist.")
    ScanQuestLog()
    UpdateAutoClutter()
end

local function SlashList()
    local whitelist = Whitelist()
    local ids = {}
    for questID in pairs(whitelist) do ids[#ids + 1] = questID end
    table.sort(ids)
    if #ids == 0 then
        Print("Whitelist is empty.")
        return
    end
    for _, questID in ipairs(ids) do
        local zones = {}
        for zoneID in pairs(whitelist[questID].zones) do zones[#zones + 1] = tostring(zoneID) end
        table.sort(zones)
        Print(string.format("%d%s - zones: %s%s", questID,
            whitelist[questID].auto and " (auto)" or "",
            #zones > 0 and table.concat(zones, ", ") or "none yet",
            activeQuests[questID] and " (in quest log)" or ""))
    end
end

-- A wrongly learned zone is otherwise unfixable without wiping the whole entry.
local function SlashZones(arg)
    local id, sub = tostring(arg or ""):match("^%s*(%d*)%s*(%S*)")
    local questID = tonumber(id)
    local entry = questID and Whitelist()[questID]
    if not entry then
        Print("Usage: /raapwhistle zones <questID> [clear]")
        return
    end
    if string.lower(sub or "") == "clear" then
        entry.zones = {}
        zoneCandidates[questID] = nil
        Print("Cleared learned zones for quest ID " .. questID .. ".")
        UpdateAutoClutter()
        return
    end
    local zones = {}
    for zoneID in pairs(entry.zones) do zones[#zones + 1] = tostring(zoneID) end
    table.sort(zones)
    Print(string.format("Quest %d zones: %s", questID,
        #zones > 0 and table.concat(zones, ", ") or "none yet"))
end

-- One shot dump of everything worth knowing when this misbehaves in game, so a
-- report is a single paste rather than a dozen /dump commands. Everything here
-- is defensive: the whole point is that it still prints on a client where the
-- thing being diagnosed is exactly what is missing.
local function SlashDebug()
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = "?"
    if metadata then
        local ok, value = pcall(metadata, ADDON_NAME, "Version")
        if ok and value then version = tostring(value) end
    end
    local build, interface = "?", "?"
    if GetBuildInfo then
        local ok, clientVersion, _, _, tocVersion = pcall(GetBuildInfo)
        if ok then build, interface = tostring(clientVersion), tostring(tocVersion) end
    end
    Print(string.format("%s %s | client %s (interface %s)", ADDON_NAME, version, build, interface))

    local current, default = GetClutter(), GetClutterDefault()
    if current == nil and default == nil then
        Print(string.format("CVar %s: MISSING - this client does not expose it", CLUTTER_CVAR))
    else
        Print(string.format("CVar %s = %s (default %s, ceiling %d)", CLUTTER_CVAR,
            tostring(current), tostring(default), clutterMax))
    end

    if not LibStub then
        Print("libs: none - LibStub did not load, running on the fallback paths")
    else
        local loaded = {}
        for _, name in ipairs({ "AceDB-3.0", "AceDBOptions-3.0", "AceLocale-3.0",
            "AceConfig-3.0", "AceConfigDialog-3.0", "AceConfigRegistry-3.0",
            "LibDataBroker-1.1", "LibDBIcon-1.0" }) do
            if GetLib(name) then loaded[#loaded + 1] = name end
        end
        Print("libs: " .. table.concat(loaded, " "))
    end

    local zoneID = GetCurrentZoneID()
    local zoneName
    if zoneID and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, zoneID)
        if ok and type(info) == "table" then zoneName = info.name end
    end
    Print(string.format("map: %s%s", tostring(zoneID),
        zoneName and (" (" .. tostring(zoneName) .. ")") or ""))

    local profile = db.profile
    Print(string.format("settings: auto=%s detect=%s item=%s restore=%s low=%s high=%s peek=%ss",
        tostring(profile.autoClutter), tostring(profile.autoDetect),
        tostring(profile.detectItemObjectives), tostring(profile.restoreMode),
        tostring(profile.clutterLow), tostring(profile.clutterHigh),
        tostring(profile.peekDuration)))
    Print(string.format("state: applied=%s reads-as=%s peek=%s saved=%s",
        tostring(appliedState), tostring(CurrentState()),
        PeekActive() and "running" or "no", tostring(profile.savedClutter)))

    local count = GetNumQuestEntries()
    Print(string.format("quest log (%d entries):", count))
    for i = 1, count do
        local questID = GetQuestIDForIndex(i)
        if questID then
            local types = GetObjectiveTypes(i, questID)
            local list = {}
            if types then
                for objectiveType in pairs(types) do list[#list + 1] = tostring(objectiveType) end
                table.sort(list)
            end
            local verdict = QuestHasGroundObjective(i, questID)
            Print(string.format("  %d %s | obj: %s | detect: %s", questID,
                tostring(GetQuestTitle(i) or "?"),
                #list > 0 and table.concat(list, ",") or "unavailable",
                verdict == nil and "unknown" or (verdict and "YES" or "no")))
        end
    end

    local whitelist = Whitelist()
    local ids = {}
    for questID in pairs(whitelist) do ids[#ids + 1] = questID end
    table.sort(ids)
    Print(string.format("whitelist: %s", #ids == 0 and "empty"
        or (#ids .. (#ids == 1 and " entry" or " entries"))))
    for _, questID in ipairs(ids) do
        local zones = {}
        for zoneEntry in pairs(whitelist[questID].zones) do
            zones[#zones + 1] = tostring(zoneEntry)
        end
        table.sort(zones)
        Print(string.format("  %d%s zones: %s", questID,
            whitelist[questID].auto and " (auto)" or "",
            #zones > 0 and table.concat(zones, ", ") or "none yet"))
    end

    local ignored = {}
    for questID in pairs(Ignored()) do ignored[#ignored + 1] = tostring(questID) end
    table.sort(ignored)
    Print("ignored: " .. (#ignored > 0 and table.concat(ignored, ", ") or "none"))
end

SLASH_RAAPWHISTLE1 = "/raapwhistle"
SlashCmdList["RAAPWHISTLE"] = function(msg)
    local cmd, arg = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" then
        OpenOptions()
    elseif cmd == "toggle" then
        ToggleGroundClutter()
    elseif cmd == "peek" then
        StartPeek(arg)
    elseif cmd == "add" then
        SlashAdd(arg)
    elseif cmd == "remove" or cmd == "del" then
        local questID = tonumber(arg)
        if questID and Whitelist()[questID] then
            Whitelist()[questID] = nil
            activeQuests[questID] = nil
            Print("Removed quest ID " .. questID .. " from the whitelist.")
            UpdateAutoClutter()
        else
            Print("Usage: /raapwhistle remove <questID>")
        end
    elseif cmd == "ignore" then
        local questID = tonumber(arg)
        if questID then
            Ignored()[questID] = true
            Whitelist()[questID] = nil
            activeQuests[questID] = nil
            Print("Ignoring quest ID " .. questID .. ".")
            UpdateAutoClutter()
        else
            Print("Usage: /raapwhistle ignore <questID>")
        end
    elseif cmd == "unignore" then
        local questID = tonumber(arg)
        if questID and Ignored()[questID] then
            Ignored()[questID] = nil
            Print("No longer ignoring quest ID " .. questID .. ".")
            ScanQuestLog()
            UpdateAutoClutter()
        else
            Print("Usage: /raapwhistle unignore <questID>")
        end
    elseif cmd == "list" then
        SlashList()
    elseif cmd == "debug" then
        SlashDebug()
    elseif cmd == "zones" then
        SlashZones(arg)
    else
        Print("Usage: /raapwhistle [add [quest log index] | remove <questID> | "
            .. "ignore <questID> | unignore <questID> | zones <questID> [clear] | "
            .. "list | toggle | peek [seconds] | debug]")
    end
end

-- Keybinding ------------------------------------------------------------------

BINDING_HEADER_RAAPWHISTLE = L["RaapWhistle"]
BINDING_NAME_RAAPWHISTLE_TOGGLE = L["Toggle Ground Clutter"]
BINDING_NAME_RAAPWHISTLE_PEEK = L["Peek Ground Clutter"]

function RaapWhistle_ToggleBinding()
    ToggleGroundClutter()
end

function RaapWhistle_PeekBinding()
    StartPeek()
end

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
else
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            RegisterMinimapIcon()
            RegisterOptions()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        -- Never leave the CVar low on the way out: it persists in the client
        -- config, so it would degrade every character, addon uninstalled or not.
        if appliedState == "low" then ApplyState("high", false) end
        return
    end

    InitDB() -- safety net: saved variables are loaded by the time these fire

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        DoScan() -- login-time restore, gated by the autoClutter profile setting
    elseif event == "QUEST_ACCEPTED" then
        -- Retail passes (questID); Classic passes (questLogIndex, questID).
        local questID = tonumber(arg2) or tonumber(arg1)
        if questID and Whitelist()[questID] and IsQuestInLog(questID) then
            RememberZone(questID, GetCurrentZoneID())
        end
        DoScan()
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        OnQuestGone(arg1)
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        RequestScan()
    else -- zone changes
        UpdateAutoClutter()
        RequestScan() -- open or ripen a zone candidate for the quests in the log
        if event == "ZONE_CHANGED_NEW_AREA" and C_Timer and C_Timer.After then
            C_Timer.After(1, UpdateAutoClutter) -- the map ID can lag the event
        end
    end
end)
