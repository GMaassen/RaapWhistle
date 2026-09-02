-- Mock WoW client for testing RaapWhistle.lua outside the game.
--
-- Each env installs a fresh set of globals, so a test can pick the API surface
-- it wants: "classic" (Wrath 3.4.x - GetQuestLogTitle/GetQuestLogSelection) or
-- "retail" (C_QuestLog). Options let a test drop C_Timer, drop LibStub, make
-- SetCVar fail, cap the clutter ceiling the way a real client would, or start
-- the clutter CVar somewhere other than the client default.

local M = {}
M.ROOT = "."

-- Globals the addon creates; cleared between runs so each load starts clean.
local ADDON_GLOBALS = {
    "RaapWhistle_ToggleBinding", "RaapWhistle_PeekBinding",
    "BINDING_HEADER_RAAPWHISTLE", "BINDING_NAME_RAAPWHISTLE_TOGGLE",
    "BINDING_NAME_RAAPWHISTLE_PEEK", "SLASH_RAAPWHISTLE1",
}

function M.new(opts)
    opts = opts or {}
    local env = {
        frames = {},
        prints = {},
        timers = {},
        questLog = {},          -- array of questIDs, in log order
        -- questID -> array of objective type strings ("object", "item",
        -- "monster", ...). A quest absent from here has no objective data
        -- available yet, which is what a client looks like right after login.
        objectives = {},
        opened = {},            -- appNames AceConfigDialog:Open was called with
        zone = 100,
        -- The player's own setting, which need not be the client default. Kept
        -- distinct from cvarDefault so restore-to-remembered can be told apart
        -- from restore-to-a-constant.
        cvars = { graphicsGroundClutter = tostring(opts.cvarStart or 9) },
        cvarCeiling = opts.cvarCeiling,   -- client silently refuses above this
        cvarFail = opts.cvarFail or false,
    }

    for _, name in ipairs(ADDON_GLOBALS) do _G[name] = nil end
    _G.RaapWhistleDB = opts.savedVars or nil
    _G.SlashCmdList = {}

    function _G.CreateFrame()
        local f = { events = {}, scripts = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:RegisterUnitEvent(e, u) self.events[e] = u end
        function f:SetScript(n, fn) self.scripts[n] = fn end
        function f:GetScript(n) return self.scripts[n] end
        function f:Hide() end
        function f:Show() end
        function f:SetPoint() end
        function f:SetSize() end
        env.frames[#env.frames + 1] = f
        return f
    end

    function _G.print(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        env.prints[#env.prints + 1] = table.concat(parts, " ")
    end

    function _G.GetCVar(n) return env.cvars[n] end
    function _G.SetCVar(n, v)
        if env.cvarFail then error("SetCVar refused") end
        v = tonumber(v) or v
        if env.cvarCeiling and tonumber(v) and tonumber(v) > env.cvarCeiling then
            v = env.cvarCeiling -- client clamps silently, as some builds do
        end
        env.cvars[n] = tostring(v)
        return true
    end
    function _G.GetCVarDefault() return opts.cvarDefault or "9" end

    function _G.UnitName() return "Tester" end
    function _G.GetRealmName() return "TestRealm" end
    function _G.GetLocale() return "enUS" end
    function _G.GetAddOnMetadata(_, field)
        return field == "Version" and "0.2.0" or nil
    end
    -- version, build, date, interface number
    function _G.GetBuildInfo() return "12.0.0", "60000", "Jan 1 2026", 120000 end
    -- AceDB-3.0 reads these to build its profile keys.
    function _G.UnitClass() return "Warrior", "WARRIOR" end
    function _G.UnitRace() return "Orc", "Orc" end
    function _G.UnitFactionGroup() return "Horde", "Horde" end
    function _G.GetCurrentRegion() return 1 end
    function _G.geterrorhandler() return function(msg) error(msg) end end

    -- Monotonic fake clock so the scan throttle is deterministic.
    env.now = 0
    function _G.GetTime() return env.now end

    _G.C_CVar = nil
    if opts.api == "retail" then
        -- Modern retail has the Settings API and no InterfaceOptionsFrame_*,
        -- which is precisely why the options path needs a third fallback.
        _G.InterfaceOptionsFrame_OpenToCategory = nil
        _G.Settings = (opts.settingsOpens ~= nil)
            and { OpenToCategory = function() return opts.settingsOpens end } or nil
    else
        _G.Settings = nil
        _G.InterfaceOptionsFrame_OpenToCategory = function() end
    end

    _G.C_Map = (not opts.noMap) and {
        GetBestMapForUnit = function() return env.zone end,
        GetMapInfo = function(mapID) return { mapID = mapID, name = "Zone " .. mapID } end,
    } or nil

    if opts.noTimer then
        _G.C_Timer = nil
    else
        _G.C_Timer = { After = function(delay, fn)
            env.timers[#env.timers + 1] = { delay = delay, fn = fn }
        end }
    end

    if opts.api == "retail" then
        _G.GetQuestLogTitle = nil
        _G.GetQuestLogSelection = nil
        _G.GetNumQuestLogEntries = nil
        _G.GetNumQuestLeaderBoards = nil
        _G.GetQuestLogLeaderBoard = nil
        _G.C_QuestLog = {
            GetNumQuestLogEntries = function() return #env.questLog end,
            GetInfo = function(i)
                local q = env.questLog[i]
                if not q then return nil end
                return { questID = q, isHeader = false, title = "Quest " .. q }
            end,
            GetSelectedQuest = function() return env.selected end,
            GetQuestObjectives = function(questID)
                local list = env.objectives[questID]
                if not list then return nil end
                local out = {}
                for i, objectiveType in ipairs(list) do
                    out[i] = { type = objectiveType, finished = false }
                end
                return out
            end,
            IsOnQuest = function(id)
                for _, q in ipairs(env.questLog) do if q == id then return true end end
                return false
            end,
        }
    else
        -- Wrath 3.4.x surface: no C_QuestLog at all.
        _G.C_QuestLog = nil
        _G.GetNumQuestLogEntries = function() return #env.questLog end
        _G.GetQuestLogTitle = function(i)
            local q = env.questLog[i]
            if not q then return nil end
            -- title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
            return "Quest " .. q, 70, 0, false, false, false, 1, q
        end
        _G.GetQuestLogSelection = function() return env.selectedIndex or 0 end
        _G.GetNumQuestLeaderBoards = function(index)
            local list = env.objectives[env.questLog[index]]
            return list and #list or 0
        end
        _G.GetQuestLogLeaderBoard = function(objective, index)
            local list = env.objectives[env.questLog[index]]
            local objectiveType = list and list[objective]
            if not objectiveType then return nil end
            -- description, type, finished
            return "Objective " .. objective, objectiveType, false
        end
    end

    -- A minimal Ace3 stand-in: just enough for the options registration path,
    -- without dragging AceGUI and the whole widget tree into a headless test.
    if opts.fakeOptions then
        local libs = {
            ["AceConfig-3.0"] = { RegisterOptionsTable = function() end },
            ["AceConfigDialog-3.0"] = {
                AddToBlizOptions = function(_, appName) return { name = appName } end,
                Open = function(_, appName) env.opened[#env.opened + 1] = appName end,
            },
        }
        _G.LibStub = function(name, silent)
            local lib = libs[name]
            if not lib and not silent then error("library " .. tostring(name) .. " not found") end
            return lib
        end
    elseif opts.ace then
        dofile(M.ROOT .. "/Ace3/LibStub/LibStub.lua")
        dofile(M.ROOT .. "/Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua")
        dofile(M.ROOT .. "/Ace3/AceDB-3.0/AceDB-3.0.lua")
    else
        _G.LibStub = nil
    end

    -- Helpers -----------------------------------------------------------------

    function env:load()
        dofile(M.ROOT .. "/RaapWhistle.lua")
        return self
    end

    -- The addon may create other frames (the peek ticker), so find the one
    -- actually listening for events rather than assuming it was created last.
    function env:fire(...)
        for i = #self.frames, 1, -1 do
            local f = self.frames[i]
            if f.scripts.OnEvent then return f.scripts.OnEvent(f, ...) end
        end
        error("no frame is handling events")
    end

    function env:slash(msg) _G.SlashCmdList["RAAPWHISTLE"](msg) end

    function env:clutter() return self.cvars.graphicsGroundClutter end

    -- Advance the fake clock and run any timers that were scheduled.
    function env:flush(seconds)
        self.now = self.now + (seconds or 1)
        local pending = self.timers
        self.timers = {}
        for _, t in ipairs(pending) do t.fn() end
    end

    -- Advances the clock and runs OnUpdate handlers, for the code paths that
    -- fall back to a ticker when C_Timer is unavailable.
    function env:tick(seconds)
        seconds = seconds or 1
        self.now = self.now + seconds
        for _, f in ipairs(self.frames) do
            local fn = f.scripts.OnUpdate
            if fn then fn(f, seconds) end
        end
    end

    function env:clearPrints() self.prints = {} end

    function env:printCount() return #self.prints end

    return env
end

return M
