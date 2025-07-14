SetCVar("graphicsGroundClutter", 9)

function ToggleGroundClutter()
    local currentSetting = tonumber(GetCVar("graphicsGroundClutter"))
    if currentSetting < 9 then
        SetCVar("graphicsGroundClutter", 9)
        print("RaapWhistle: Ground clutter set to high.")
    else
        SetCVar("graphicsGroundClutter", 0)
        print("RaapWhistle: Ground clutter set to low.")
    end

-- Slash command to add current selected quest to whitelist
SLASH_RAAPWHISTLE1 = "/raapwhistle"
SlashCmdList["RAAPWHISTLE"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "add" then
        local index = tonumber(arg)
        local questIndex
        if index and index > 0 then
            questIndex = index
        else
            questIndex = GetQuestLogSelection and GetQuestLogSelection()
        end
        if questIndex and questIndex > 0 then
            local questId = select(8, GetQuestLogTitle(questIndex))
            if questId then
                RaapWhistleDB.profile.questWhitelist = RaapWhistleDB.profile.questWhitelist or {}
                RaapWhistleDB.profile.questWhitelist[questId] = true
                print("RaapWhistle: Added quest ID " .. questId .. " to whitelist.")
            else
                print("RaapWhistle: Could not determine quest ID.")
            end
        else
            print("RaapWhistle: No valid quest index provided or selected.")
        end
    else
        print("RaapWhistle: Usage: /raapwhistle add [quest log index]")
    end
end

-- Keybinding support for manual toggle
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    BINDING_HEADER_RAAPWHISTLE = "RaapWhistle"
    BINDING_NAME_RAAPWHISTLE_TOGGLE = "Toggle Ground Clutter"
end)

function RaapWhistle_ToggleBinding()
    ToggleGroundClutter()
end
end

local L = LibStub("AceLocale-3.0"):GetLocale("RaapWhistle", true) or {
    ["RaapWhistle"] = "RaapWhistle",
    ["Ground clutter set to high."] = "Ground clutter set to high.",
    ["Ground clutter set to low."] = "Ground clutter set to low.",
    ["Quest objective complete, ground clutter restored."] = "Quest objective complete, ground clutter restored.",
    ["Quest objective started, ground clutter reduced."] = "Quest objective started, ground clutter reduced.",
    ["Auto Clutter Toggle"] = "Auto Clutter Toggle",
    ["Automatically toggle ground clutter based on quest state"] = "Automatically toggle ground clutter based on quest state",
    ["Low Clutter Value"] = "Low Clutter Value",
    ["Value for reduced ground clutter"] = "Value for reduced ground clutter",
    ["High Clutter Value"] = "High Clutter Value",
    ["Value for restored ground clutter"] = "Value for restored ground clutter",
    ["Toggle Ground Clutter"] = "Toggle Ground Clutter",
}

local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("RaapWhistle", {
    type = "data source",
    text = L["RaapWhistle"],
    icon = "Interface\\ICONS\\Ability_hunter_beastcall",
    OnClick = function(self, btn)
        ToggleGroundClutter()
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then
            return
        end
        tooltip:AddLine(L["RaapWhistle"])
    end
})

local icon = LibStub("LibDBIcon-1.0")
icon:Register("RaapWhistle", miniButton, RaapWhistleDB)

-- Questie integration: auto-toggle ground clutter based on quest state (placeholder)
local function GetCurrentZoneID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function IsWhitelistedQuestZone(questId, zoneId)
    local whitelist = RaapWhistleDB and RaapWhistleDB.profile and RaapWhistleDB.profile.questWhitelist or {}
    return whitelist[questId] and whitelist[questId] == zoneId
end

local function OnQuestieEvent(event, questId, ...)
    local zoneId = GetCurrentZoneID()
    local whitelist = RaapWhistleDB and RaapWhistleDB.profile and RaapWhistleDB.profile.questWhitelist or {}
    if event == "Questie:ObjectiveStart" then
        if whitelist[questId] then
            whitelist[questId] = zoneId
            print("RaapWhistle: Tracking quest " .. questId .. " in zone " .. tostring(zoneId))
        end
    elseif event == "Questie:ObjectiveComplete" then
        if whitelist[questId] then
            whitelist[questId] = nil
            SetCVar("graphicsGroundClutter", RaapWhistleDB.profile.clutterHigh or 9)
            print("RaapWhistle: Quest " .. questId .. " completed, ground clutter restored and quest removed from whitelist.")
        end
    end
end

local function OnZoneChanged()
    if not RaapWhistleDB or not RaapWhistleDB.profile then return end
    local zoneId = GetCurrentZoneID()
    local whitelist = RaapWhistleDB.profile.questWhitelist or {}
    for questId, trackedZoneId in pairs(whitelist) do
        if trackedZoneId == zoneId then
            SetCVar("graphicsGroundClutter", RaapWhistleDB.profile.clutterLow or 0)
            print("RaapWhistle: In tracked zone for quest " .. questId .. ", ground clutter reduced.")
            return
        end
    end
    SetCVar("graphicsGroundClutter", RaapWhistleDB.profile.clutterHigh or 9)
    print("RaapWhistle: Left tracked quest zone, ground clutter restored.")
end

local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("ZONE_CHANGED")
zoneFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:SetScript("OnEvent", OnZoneChanged)

-- Try to hook into Questie events if Questie is loaded
local questieFrame = _G["Questie"]
if questieFrame and questieFrame.RegisterCallback then
    questieFrame:RegisterCallback("Questie:ObjectiveComplete", OnQuestieEvent)
    questieFrame:RegisterCallback("Questie:ObjectiveStart", OnQuestieEvent)
end

-- AceConfig-3.0 options for user configuration (basic example)
local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
local AceDB = LibStub("AceDB-3.0", true)

if AceConfig and AceConfigDialog and AceDB then
    RaapWhistleDB = RaapWhistleDB or {}
    local defaults = {
        profile = {
            autoClutter = true,
            clutterLow = 0,
            clutterHigh = 9,
        }
    }
    local db = AceDB:New("RaapWhistleDB", defaults, true)
    if not db or not db.profile then
        db = { profile = defaults.profile }
    end
    local options = {
        name = "RaapWhistle",
        type = "group",
        args = {
            profile = LibStub("AceDBOptions-3.0", true) and LibStub("AceDBOptions-3.0"):GetOptionsTable(db),
            autoClutter = {
                type = "toggle",
                name = L["Auto Clutter Toggle"],
                desc = L["Automatically toggle ground clutter based on quest state"],
                get = function() return db.profile and db.profile.autoClutter end,
                set = function(_, val) if db.profile then db.profile.autoClutter = val end end,
            },
            clutterLow = {
                type = "range",
                name = L["Low Clutter Value"],
                desc = L["Value for reduced ground clutter"],
                min = 0, max = 9, step = 1,
                get = function() return db.profile and db.profile.clutterLow end,
                set = function(_, val) if db.profile then db.profile.clutterLow = val end end,
            },
            clutterHigh = {
                type = "range",
                name = L["High Clutter Value"],
                desc = L["Value for restored ground clutter"],
                min = 0, max = 9, step = 1,
                get = function() return db.profile and db.profile.clutterHigh end,
                set = function(_, val) if db.profile then db.profile.clutterHigh = val end end,
            },
            questWhitelist = {
                type = "input",
                name = "Quest Whitelist",
                desc = "Comma-separated quest IDs to autotoggle",
                get = function()
                    local wl = db.profile and db.profile.questWhitelist or {}
                    local ids = {}
                    for k in pairs(wl) do table.insert(ids, k) end
                    return table.concat(ids, ",")
                end,
                set = function(_, val)
                    if db.profile then
                        db.profile.questWhitelist = {}
                        for id in string.gmatch(val, "%d+") do
                            db.profile.questWhitelist[tonumber(id)] = true
                        end
                    end
                end,
            },
        }
    }
    AceConfig:RegisterOptionsTable("RaapWhistle", options)
    AceConfigDialog:AddToBlizOptions("RaapWhistle", "RaapWhistle")
    if LibStub("AceDBOptions-3.0", true) then
        AceConfigDialog:AddToBlizOptions("RaapWhistle", "Profiles", "RaapWhistle")
    end
end
