SetCVar("graphicsGroundClutter", 9)

function ToggleGroundClutter()
    local currentSetting = tonumber(GetCVar("graphicsGroundClutter"))
    if currentSetting < 9 then
        SetCVar("graphicsGroundClutter", 9)
    else
        SetCVar("graphicsGroundClutter", 0)
    end
end

local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("RaapWhistle", {
    type = "data source",
    text = "RaapWhistle",
    icon = "Interface\\ICONS\\Ability_hunter_beastcall",
    OnClick = function(self, btn)
        ToggleGroundClutter()
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then
            return
        end
        tooltip:AddLine("RaapWhistle")
    end
})

local icon = LibStub("LibDBIcon-1.0")
icon:Register("RaapWhistle", miniButton, RaapWhistleDB)
