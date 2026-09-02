-- Offline test suite for RaapWhistle. Run from the addon root:
--     lua tests/run_tests.lua
-- These exercise the addon against a mock client (tests/wow_env.lua). They are
-- not a substitute for testing in game, but they cover the logic that does not
-- depend on real Blizzard event payloads.

local say = print  -- the mock client replaces _G.print, so keep the real one

local env_module = dofile("tests/wow_env.lua")
env_module.ROOT = "."

local passed, failed, skipped = 0, 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        say(string.format("  ok   %s", name))
    else
        failed = failed + 1
        say(string.format("  FAIL %s", name))
        say(string.format("       %s", tostring(err)))
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
            what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- Boots an env, loads the addon, and runs ADDON_LOADED + PLAYER_LOGIN.
local function boot(opts)
    local e = env_module.new(opts)
    e:load()
    e:fire("ADDON_LOADED", "RaapWhistle")
    e:fire("PLAYER_LOGIN")
    return e
end

say("")
say("RaapWhistle offline tests")
say("")

-- The API surface that actually runs on Wrath Classic 3.4.x ------------------

test("classic: loads and stays quiet with an empty whitelist", function()
    local e = boot({ api = "classic" })
    eq(e:clutter(), "9", "clutter untouched at login")
    eq(e:printCount(), 0, "print count")
end)

test("classic: add learns the current zone and drops clutter", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.zone = 100
    e:fire("QUEST_ACCEPTED", 1, 1234)
    eq(e:clutter(), "9", "non-whitelisted quest ignored")
    e:slash("add 1")
    eq(e:clutter(), "0", "clutter lowered in the learned zone")
end)

test("classic: leaving and re-entering the tracked zone flips clutter", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "low in tracked zone")
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "9", "restored outside tracked zone")
    e.zone = 100
    e:fire("ZONE_CHANGED")
    eq(e:clutter(), "0", "lowered again on return")
end)

test("classic: turn-in restores clutter but keeps the whitelist entry", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    e.questLog = {}
    e:fire("QUEST_TURNED_IN", 1234)
    eq(e:clutter(), "9", "restored after turn-in")
    e.questLog = { 1234 }
    e:fire("QUEST_ACCEPTED", 1, 1234)
    eq(e:clutter(), "0", "still whitelisted when re-accepted")
end)

test("classic: quest ID resolves from the quest log selection", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234, 5678 }
    e.selectedIndex = 2
    e:slash("add")
    eq(e:clutter(), "0", "selected quest whitelisted and active here")
end)

-- Retail surface -------------------------------------------------------------

test("retail: add and zone tracking work through C_QuestLog", function()
    local e = boot({ api = "retail" })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "low in tracked zone")
    e.zone = 999
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "9", "restored elsewhere")
end)

test("retail: QUEST_ACCEPTED single-arg payload is handled", function()
    local e = boot({ api = "retail" })
    e.questLog = { 4242 }
    e:slash("add 1")
    e.questLog = {}
    e:fire("QUEST_REMOVED", 4242)
    eq(e:clutter(), "9", "restored on removal")
    e.questLog = { 4242 }
    e.zone = 555
    e:fire("QUEST_ACCEPTED", 4242)
    eq(e:clutter(), "0", "new zone learned from single-arg payload")
end)

-- Settings behaviour ---------------------------------------------------------

test("autoClutter=false suppresses automatic changes", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "low to begin with")
    e:slash("toggle")
    eq(e:clutter(), "9", "manual toggle wins")
    RaapWhistleDB.profiles["Default"].autoClutter = false
    e.zone = 300
    e:fire("ZONE_CHANGED_NEW_AREA")
    e.zone = 100
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "9", "auto toggle stayed off")
end)

test("manual toggle works even with autoClutter off", function()
    local e = boot({ api = "classic" })
    RaapWhistleDB.profiles["Default"].autoClutter = false
    e:slash("toggle")
    eq(e:clutter(), "0", "manual toggle ignores autoClutter")
    e:slash("toggle")
    eq(e:clutter(), "9", "and toggles back")
end)

test("repeated zone events produce no chat spam", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    e:clearPrints()
    for _ = 1, 20 do
        e:fire("ZONE_CHANGED_INDOORS")
        e:fire("ZONE_CHANGED")
    end
    eq(e:printCount(), 0, "silent while state is unchanged")
    eq(e:clutter(), "0", "still low")
end)

test("verbose=false stays silent even when the state really changes", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "low in the tracked zone")
    e:clearPrints()
    e.zone = 700
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "9", "state actually changed")
    eq(e:printCount(), 0, "but nothing was announced")
end)

test("verbose=true announces automatic changes", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    RaapWhistleDB.profiles["Default"].verbose = true
    e:clearPrints()
    e.zone = 700
    e:fire("ZONE_CHANGED_NEW_AREA")
    if e:printCount() < 1 then error("expected an announcement when verbose") end
end)

-- Persistence ----------------------------------------------------------------

test("legacy whitelist values are migrated on load", function()
    local saved = {
        profileKeys = { ["Tester - TestRealm"] = "Default" },
        profiles = { Default = { questWhitelist = { [1234] = true, [5678] = 200 } } },
    }
    boot({ api = "classic", savedVars = saved })
    local wl = saved.profiles.Default.questWhitelist
    if type(wl[1234]) ~= "table" then error("1234 not migrated to a table") end
    eq(next(wl[1234].zones), nil, "no zone learned for the boolean entry")
    eq(wl[5678].zones[200], true, "zoneID value became a zones entry")
end)

test("whitelist survives a reload", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    local saved = RaapWhistleDB
    local e2 = boot({ api = "classic", savedVars = saved })
    e2.questLog = { 1234 }
    e2.zone = 100
    e2:fire("QUEST_LOG_UPDATE")
    e2:flush(2)
    eq(e2:clutter(), "0", "whitelist and learned zone persisted")
end)

-- Degraded environments ------------------------------------------------------

test("works with no LibStub at all", function()
    local e = boot({ api = "classic" })
    if _G.LibStub ~= nil then error("expected no LibStub in this env") end
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "core behaviour intact without Ace3")
    e:slash("")
end)

test("real AceDB-3.0 is used when present", function()
    local e = boot({ api = "classic", ace = true })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "AceDB path behaves the same")
end)

test("a failing SetCVar does not error and reports once", function()
    local e = boot({ api = "classic", cvarFail = true })
    e:clearPrints()
    e:slash("toggle")
    if e:printCount() < 1 then error("expected a failure message") end
end)

test("the clutter ceiling is corrected when the client clamps", function()
    local e = boot({ api = "classic", cvarCeiling = 3 })
    e:slash("toggle")
    eq(e:clutter(), "0", "low applied")
    e:slash("toggle")
    eq(e:clutter(), "3", "client ceiling respected")
end)

test("a missing map ID does not break anything", function()
    local e = boot({ api = "classic", noMap = true })
    e.questLog = { 1234 }
    e:slash("add 1")
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "9", "no zone means no automatic lowering")
end)

test("works without C_Timer", function()
    local e = boot({ api = "classic", noTimer = true })
    e.questLog = { 1234 }
    e:slash("add 1")
    e:fire("QUEST_LOG_UPDATE")
    eq(e:clutter(), "0", "scan still ran without a timer")
end)

-- Restore behaviour ----------------------------------------------------------

test("restore hands back the player's own value, not the client default", function()
    local e = boot({ api = "classic", cvarStart = 4, cvarDefault = 9 })
    e:slash("toggle")
    eq(e:clutter(), "0", "lowered")
    e:slash("toggle")
    eq(e:clutter(), "4", "restored to what the player was running at")
end)

test("the remembered value survives a reload", function()
    local e = boot({ api = "classic", cvarStart = 4 })
    e:slash("toggle")
    eq(e:clutter(), "0", "lowered")
    local saved = RaapWhistleDB
    -- The CVar persists in the client config, so the next session starts low.
    -- The login scan should hand back the remembered value, not the default.
    local e2 = boot({ api = "classic", cvarStart = 0, cvarDefault = 9, savedVars = saved })
    eq(e2:clutter(), "4", "login restored the remembered value across the reload")
end)

test("restoreMode=fixed uses the configured high value", function()
    local saved = {
        profileKeys = { ["Tester - TestRealm"] = "Default" },
        profiles = { Default = { restoreMode = "fixed", clutterLow = 0, clutterHigh = 7 } },
    }
    local e = boot({ api = "classic", cvarStart = 4, savedVars = saved })
    e:slash("toggle")
    eq(e:clutter(), "0", "lowered")
    e:slash("toggle")
    eq(e:clutter(), "7", "restored to the configured value")
end)

test("logout restores clutter instead of leaving the client low", function()
    local e = boot({ api = "classic", cvarStart = 6 })
    e:slash("toggle")
    eq(e:clutter(), "0", "lowered")
    e:fire("PLAYER_LOGOUT")
    eq(e:clutter(), "6", "restored on the way out")
end)

test("an inverted low/high pair is repaired on load", function()
    local saved = {
        profileKeys = { ["Tester - TestRealm"] = "Default" },
        profiles = { Default = { clutterLow = 9, clutterHigh = 0 } },
    }
    boot({ api = "classic", savedVars = saved })
    local profile = saved.profiles.Default
    if profile.clutterLow >= profile.clutterHigh then
        error(string.format("low %s is not below high %s",
            tostring(profile.clutterLow), tostring(profile.clutterHigh)))
    end
end)

-- Peek -----------------------------------------------------------------------

test("peek lowers clutter and puts it back on its own", function()
    local e = boot({ api = "classic", cvarStart = 7 })
    if type(_G.RaapWhistle_PeekBinding) ~= "function" then
        error("the peek keybinding global was never created")
    end
    e:slash("peek 10")
    eq(e:clutter(), "0", "lowered for the peek")
    e:flush(10)
    eq(e:clutter(), "7", "restored when the peek expired")
end)

test("peek restores without C_Timer, through the OnUpdate fallback", function()
    local e = boot({ api = "classic", cvarStart = 7, noTimer = true })
    e:slash("peek 10")
    eq(e:clutter(), "0", "lowered")
    e:tick(4)
    eq(e:clutter(), "0", "still peeking")
    e:tick(6)
    eq(e:clutter(), "7", "restored by the ticker")
end)

test("a second peek extends rather than stacking", function()
    local e = boot({ api = "classic", cvarStart = 7 })
    e:slash("peek 10")
    e:flush(5)
    e:slash("peek 10")           -- expires at 15 now, not 10
    e:flush(6)                   -- clock at 11
    eq(e:clutter(), "0", "extended peek still running")
    e:flush(5)                   -- clock at 16
    eq(e:clutter(), "7", "restored once the extension expired")
end)

test("the automatic toggle does not fight a running peek", function()
    local e = boot({ api = "classic", cvarStart = 7 })
    e.questLog = { 1234 }
    e:slash("add 1")             -- tracked in zone 100
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "7", "restored outside the tracked zone")
    e:slash("peek 10")
    eq(e:clutter(), "0", "peeking")
    e:fire("ZONE_CHANGED")       -- the automatic logic would want high here
    eq(e:clutter(), "0", "peek held")
    e:flush(10)
    eq(e:clutter(), "7", "and released afterwards")
end)

test("a peek ending inside a tracked zone stays low", function()
    local e = boot({ api = "classic", cvarStart = 7 })
    e.questLog = { 1234 }
    e:slash("add 1")             -- zone 100 tracked
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "7", "high outside the tracked zone")
    e:slash("peek 10")
    e.zone = 100                 -- walked back in mid-peek
    e:flush(10)
    eq(e:clutter(), "0", "stayed low, because the quest wants it low anyway")
end)

test("a manual toggle cancels a running peek", function()
    local e = boot({ api = "classic", cvarStart = 7 })
    e.questLog = { 1234 }
    e:slash("add 1")             -- tracked in zone 100
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "7", "high outside the tracked zone")
    e:slash("peek 60")
    eq(e:clutter(), "0", "peeking")
    e:slash("toggle")
    eq(e:clutter(), "7", "toggled back up")
    -- Restoring the same value the peek would have restored proves nothing, so
    -- check the thing a leftover peek would still be blocking: automatic control.
    e.zone = 100
    e:fire("ZONE_CHANGED_NEW_AREA")
    eq(e:clutter(), "0", "the automatic toggle is live again straight away")
    e:flush(60)
    eq(e:clutter(), "0", "and the abandoned peek does not disturb it later")
end)

-- Automatic detection --------------------------------------------------------
-- "object" objectives are world objects you click: the buried crate, the pile of
-- bones, "search the wreckage". Those are exactly what the grass hides.

local function profileOf()
    return RaapWhistleDB.profiles["Default"]
end

-- Detection happens on a scan, and the zone still has to ripen afterwards.
local function settle(e)
    e:fire("QUEST_LOG_UPDATE")
    e:flush(1)
    e:flush(31)
end

test("a quest with an object objective is tracked without being added", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.objectives[1234] = { "object" }
    settle(e)
    eq(e:clutter(), "0", "detected and lowered")
    eq(profileOf().questWhitelist[1234].auto, true, "marked as an auto entry")
end)

test("a collection objective is not detected by default", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.objectives[1234] = { "item", "monster" }
    settle(e)
    eq(e:clutter(), "9", "left alone")
    eq(profileOf().questWhitelist[1234], nil, "not whitelisted")
end)

test("collection objectives are detected once opted in", function()
    local saved = {
        profileKeys = { ["Tester - TestRealm"] = "Default" },
        profiles = { Default = { detectItemObjectives = true } },
    }
    local e = boot({ api = "classic", savedVars = saved })
    e.questLog = { 1234 }
    e.objectives[1234] = { "item" }
    settle(e)
    eq(e:clutter(), "0", "detected with the broader setting on")
end)

test("an ignored quest is never auto-tracked", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.objectives[1234] = { "object" }
    e:slash("ignore 1234")
    settle(e)
    eq(e:clutter(), "9", "stayed out of the way")
end)

test("unknown objective data is retried, not remembered as a no", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }         -- objective data not available yet
    e:fire("QUEST_LOG_UPDATE")
    e:flush(1)
    eq(profileOf().questWhitelist[1234], nil, "nothing to detect yet")
    e.objectives[1234] = { "object" }  -- the data arrives
    settle(e)
    eq(e:clutter(), "0", "picked up once the data was there")
end)

test("detection off stands auto entries down without deleting them", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.objectives[1234] = { "object" }
    settle(e)
    eq(e:clutter(), "0", "auto-tracked")
    local profile = profileOf()
    profile.autoDetect = false
    e:fire("QUEST_LOG_UPDATE")
    e:flush(2)
    eq(e:clutter(), "9", "stood down with detection off")
    if not profile.questWhitelist[1234] then
        error("the auto entry was deleted rather than stood down")
    end
    eq(profile.questWhitelist[1234].zones[100], true, "and its learned zone survived")
end)

test("a manual entry is unaffected by detection being off", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    profileOf().autoDetect = false
    e:fire("QUEST_LOG_UPDATE")
    e:flush(2)
    eq(e:clutter(), "0", "manual entries still track")
end)

test("retail: detection works through C_QuestLog.GetQuestObjectives", function()
    local e = boot({ api = "retail" })
    e.questLog = { 4242 }
    e.objectives[4242] = { "object" }
    settle(e)
    eq(e:clutter(), "0", "detected on the retail surface too")
end)

test("slash: ignore drops a tracked quest, unignore lets it come back", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e.objectives[1234] = { "object" }
    settle(e)
    eq(e:clutter(), "0", "auto-tracked")
    e:slash("ignore 1234")
    eq(e:clutter(), "9", "dropped on ignore")
    e:slash("unignore 1234")
    settle(e)
    eq(e:clutter(), "0", "detected again after unignore")
end)

-- Zone learning --------------------------------------------------------------

local function zonesOf(questID)
    return RaapWhistleDB.profiles["Default"].questWhitelist[questID].zones
end

test("a zone flown over is not learned", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")             -- learns zone 100 explicitly
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    e:flush(1)                   -- a candidate opens on 200
    e.zone = 300                 -- moved on well inside the dwell time
    e:fire("ZONE_CHANGED_NEW_AREA")
    e:flush(2)
    eq(zonesOf(1234)[200], nil, "flyover zone not learned")
    eq(zonesOf(1234)[100], true, "the explicit zone is still there")
end)

-- The flyover test above only proves two sightings are needed. This one is what
-- proves the dwell *time* matters: same zone twice, but far too close together.
test("two quick sightings of the same zone are not enough", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    e:flush(1)                   -- first sighting opens the candidate
    e:fire("QUEST_LOG_UPDATE")
    e:flush(2)                   -- seen again, but only seconds later
    eq(zonesOf(1234)[200], nil, "still well inside the dwell window")
    e:flush(31)
    eq(zonesOf(1234)[200], true, "learned once the dwell time really passes")
end)

test("a zone stayed in is learned once the dwell time passes", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    e.zone = 200
    e:fire("ZONE_CHANGED_NEW_AREA")
    e:flush(1)
    eq(zonesOf(1234)[200], nil, "not learned on first sighting")
    e:flush(31)                  -- still there well past the dwell time
    eq(zonesOf(1234)[200], true, "second zone learned")
    eq(e:clutter(), "0", "and it lowers clutter here now")
end)

test("zone learning stops at the cap", function()
    local zones = {}
    for i = 1, 8 do zones[i] = true end
    local saved = {
        profileKeys = { ["Tester - TestRealm"] = "Default" },
        profiles = { Default = { questWhitelist = { [1234] = { zones = zones } } } },
    }
    local e = boot({ api = "classic", savedVars = saved })
    e.questLog = { 1234 }
    e.zone = 500
    e:fire("ZONE_CHANGED_NEW_AREA")
    e:flush(1)
    e:flush(31)
    eq(zonesOf(1234)[500], nil, "ninth zone refused")
end)

-- Slash command surface ------------------------------------------------------

test("slash: zones lists and clears the learned zones", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    eq(e:clutter(), "0", "low in the learned zone")
    e:clearPrints()
    e:slash("zones 1234")
    eq(e:printCount(), 1, "zones printed one line")
    e:slash("zones 1234 clear")
    eq(next(zonesOf(1234)), nil, "zones cleared")
    eq(e:clutter(), "9", "clutter restored once no zone is tracked")
end)

-- A debug dump that errors is worse than no debug dump, and the client it has to
-- survive is exactly the one where the thing being diagnosed is missing.
test("slash: debug dumps state on both API surfaces", function()
    for _, api in ipairs({ "classic", "retail" }) do
        local e = boot({ api = api })
        e.questLog = { 1234 }
        e.objectives[1234] = { "object" }
        e:slash("add 1")
        e:clearPrints()
        e:slash("debug")
        if e:printCount() < 8 then
            error(api .. ": debug printed only " .. e:printCount() .. " lines")
        end
    end
end)

test("slash: debug still works on a client missing everything", function()
    local e = boot({ api = "classic", noMap = true, noTimer = true, cvarFail = true })
    e:clearPrints()
    e:slash("debug")            -- no LibStub, no C_Map, no C_Timer, CVar writes fail
    if e:printCount() < 6 then
        error("debug printed only " .. e:printCount() .. " lines")
    end
end)

test("slash: list, remove and unknown subcommands behave", function()
    local e = boot({ api = "classic" })
    e.questLog = { 1234 }
    e:slash("add 1")
    e:clearPrints()
    e:slash("list")
    if e:printCount() < 1 then error("list printed nothing") end
    e:slash("remove 1234")
    eq(e:clutter(), "9", "removing the only tracked quest restores clutter")
    e:clearPrints()
    e:slash("list")
    eq(e:printCount(), 1, "empty whitelist reports once")
    e:clearPrints()
    e:slash("nonsense")
    eq(e:printCount(), 1, "unknown subcommand prints usage")
end)

say("")
say(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
say("")
os.exit(failed == 0 and 0 or 1)
