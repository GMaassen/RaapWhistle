-- Mock WoW client for testing RaapWhistle.lua outside the game.
--
-- Each env installs a fresh set of globals, so a test can pick the API surface
-- it wants: "classic" (Wrath 3.4.x - GetQuestLogTitle/GetQuestLogSelection) or
-- "retail" (C_QuestLog). Options let a test drop C_Timer, drop LibStub, make
-- SetCVar fail, or cap the clutter ceiling the way a real client would.

local M = {}
M.ROOT = "."

-- Globals the addon creates; cleared between runs so each load starts clean.
local ADDON_GLOBALS = {
    "RaapWhistle_ToggleBinding", "BINDING_HEADER_RAAPWHISTLE",
    "BINDING_NAME_RAAPWHISTLE_TOGGLE", "SLASH_RAAPWHISTLE1",
}

function M.new(opts)
    opts = opts or {}
    local env = {
        frames = {},
        prints = {},
        timers = {},
        questLog = {},          -- array of questIDs, in log order
        zone = 100,
        cvars = { graphicsGroundClutter = "9" },
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
    _G.Settings = nil
    _G.InterfaceOptionsFrame_OpenToCategory = function() end

    _G.C_Map = (not opts.noMap) and
        { GetBestMapForUnit = function() return env.zone end } or nil

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
        _G.C_QuestLog = {
            GetNumQuestLogEntries = function() return #env.questLog end,
            GetInfo = function(i)
                local q = env.questLog[i]
                if not q then return nil end
                return { questID = q, isHeader = false, title = "Quest " .. q }
            end,
            GetSelectedQuest = function() return env.selected end,
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
    end

    if opts.ace then
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

    function env:fire(...)
        local f = self.frames[#self.frames]
        return f.scripts.OnEvent(f, ...)
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

    function env:clearPrints() self.prints = {} end

    function env:printCount() return #self.prints end

    return env
end

return M
