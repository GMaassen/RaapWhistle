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
    ["Auto Clutter Toggle"] = "Auto Clutter Toggle",
    ["Automatically toggle ground clutter based on quest state"] = "Automatically toggle ground clutter based on quest state",
    ["Verbose"] = "Verbose",
    ["Announce automatic ground clutter changes in chat"] = "Announce automatic ground clutter changes in chat",
    ["Low Clutter Value"] = "Low Clutter Value",
    ["Value for reduced ground clutter"] = "Value for reduced ground clutter",
    ["High Clutter Value"] = "High Clutter Value",
    ["Value for restored ground clutter"] = "Value for restored ground clutter",
    ["Quest Whitelist"] = "Quest Whitelist",
    ["Comma-separated quest IDs to auto-toggle"] = "Comma-separated quest IDs to auto-toggle",
    ["Profiles"] = "Profiles",
    ["Toggle Ground Clutter"] = "Toggle Ground Clutter",
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

-- Saved variables -------------------------------------------------------------

local defaults = {
    profile = {
        autoClutter = true,
        verbose = false,
        clutterLow = CLUTTER_MIN,
        clutterHigh = GetClutterDefault() or clutterMax,
        questWhitelist = {},
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

-- Whitelist shape: profile.questWhitelist[questID] = { zones = { [uiMapID] = true } }
-- An empty zones table means "no zone learned yet"; the current zone is recorded
-- the first time the quest is accepted or seen in the quest log.
local function Whitelist()
    local profile = db.profile
    profile.questWhitelist = profile.questWhitelist or {}
    return profile.questWhitelist
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
            new[id] = { zones = zones }
        end
    end
    db.profile.questWhitelist = new
end

local function AddToWhitelist(questID)
    local whitelist = Whitelist()
    if not whitelist[questID] then
        whitelist[questID] = { zones = {} }
    end
    return whitelist[questID]
end

local function RememberZone(questID, zoneID)
    local entry = Whitelist()[questID]
    if not entry or not zoneID then return false end
    if entry.zones[zoneID] then return false end
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
end

-- Clutter state ---------------------------------------------------------------

local activeQuests = {} -- questID -> true for whitelisted quests currently in the log
local appliedState      -- "low" / "high": last state this addon applied
local errorShown = false

local function CurrentState()
    local current = GetClutter()
    if not current then return appliedState end
    local low = ClampClutter(db.profile.clutterLow) or CLUTTER_MIN
    if current <= low then return "low" end
    return "high"
end

local function ApplyState(state, announce)
    local profile = db.profile
    local target = (state == "low") and profile.clutterLow or profile.clutterHigh
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

-- Quest tracking --------------------------------------------------------------

local function ScanQuestLog()
    local whitelist = Whitelist()
    local zoneID = GetCurrentZoneID()
    local seen = {}
    for i = 1, GetNumQuestEntries() do
        local questID = GetQuestIDForIndex(i)
        local entry = questID and whitelist[questID]
        if entry then
            seen[questID] = true
            if zoneID and not next(entry.zones) then
                entry.zones[zoneID] = true -- learn a zone for a quest that has none yet
            end
        end
    end
    activeQuests = seen
end

local lastScan = 0
local scanPending = false

local function DoScan()
    lastScan = (GetTime and GetTime()) or 0
    ScanQuestLog()
    UpdateAutoClutter()
end

-- QUEST_LOG_UPDATE / UNIT_QUEST_LOG_CHANGED fire in bursts, so throttle them.
local function RequestScan()
    local now = (GetTime and GetTime()) or 0
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
    if not optionsFrame then
        Print(L["Options are unavailable (Ace3 is not loaded)."])
        return
    end
    if Settings and Settings.OpenToCategory then
        local category = optionsFrame.categoryID or optionsFrame.name or ADDON_NAME
        if pcall(Settings.OpenToCategory, category) then return end
    end
    if InterfaceOptionsFrame_OpenToCategory then
        -- Blizzard bug: the first call only expands the category list.
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsFrame)
        return
    end
    Print(L["Options are unavailable (Ace3 is not loaded)."])
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
            verbose = {
                order = 20,
                type = "toggle",
                name = L["Verbose"],
                desc = L["Announce automatic ground clutter changes in chat"],
                get = function() return db.profile.verbose end,
                set = function(_, val) db.profile.verbose = val end,
            },
            clutterLow = {
                order = 30,
                type = "range",
                name = L["Low Clutter Value"],
                desc = L["Value for reduced ground clutter"],
                min = CLUTTER_MIN, max = clutterMax, step = 1,
                get = function() return db.profile.clutterLow end,
                set = function(_, val) db.profile.clutterLow = ClampClutter(val) or CLUTTER_MIN end,
            },
            clutterHigh = {
                order = 40,
                type = "range",
                name = L["High Clutter Value"],
                desc = L["Value for restored ground clutter"],
                min = CLUTTER_MIN, max = clutterMax, step = 1,
                get = function() return db.profile.clutterHigh end,
                set = function(_, val) db.profile.clutterHigh = ClampClutter(val) or clutterMax end,
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
    AddToWhitelist(questID)
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
        Print(string.format("%d - zones: %s%s", questID,
            #zones > 0 and table.concat(zones, ", ") or "none yet",
            activeQuests[questID] and " (in quest log)" or ""))
    end
end

SLASH_RAAPWHISTLE1 = "/raapwhistle"
SlashCmdList["RAAPWHISTLE"] = function(msg)
    local cmd, arg = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" then
        OpenOptions()
    elseif cmd == "toggle" then
        ToggleGroundClutter()
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
    elseif cmd == "list" then
        SlashList()
    else
        Print("Usage: /raapwhistle [add [quest log index] | remove <questID> | list | toggle]")
    end
end

-- Keybinding ------------------------------------------------------------------

BINDING_HEADER_RAAPWHISTLE = L["RaapWhistle"]
BINDING_NAME_RAAPWHISTLE_TOGGLE = L["Toggle Ground Clutter"]

function RaapWhistle_ToggleBinding()
    ToggleGroundClutter()
end

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
        if event == "ZONE_CHANGED_NEW_AREA" and C_Timer and C_Timer.After then
            C_Timer.After(1, UpdateAutoClutter) -- the map ID can lag the event
        end
    end
end)
