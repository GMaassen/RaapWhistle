-- Function to toggle ground clutter
function MyAddon_ToggleGroundClutter()
    print("MyAddon_ToggleGroundClutter")
    local currentSetting = tonumber(GetCVar("graphicsGroundClutter"))
    print(currentSetting)
    if currentSetting  < 9 then
        SetCVar("graphicsGroundClutter", 9)
    else
        SetCVar("graphicsGroundClutter", 1)
    end
end


-- Create minimap button
 
local minibtn = CreateFrame("Button", nil, Minimap)
minibtn:SetFrameLevel(8)
minibtn:SetSize(32,32)
minibtn:SetMovable(true)
 
-- minibtn:SetNormalTexture("Interface/AddOns/AutoSell/Leatrix_Plus_Up.blp")
-- minibtn:SetPushedTexture("Interface/AddOns/AutoSell/Leatrix_Plus_Up.blp")
-- minibtn:SetHighlightTexture("Interface/AddOns/AutoSell/Leatrix_Plus_Up.blp")
 
minibtn:SetNormalTexture("Interface/COMMON/Indicator-Yellow.png")
minibtn:SetPushedTexture("Interface/COMMON/Indicator-Yellow.png")
minibtn:SetHighlightTexture("Interface/COMMON/Indicator-Yellow.png")
 
 
local myIconPos = 0
 
-- Control movement
local function UpdateMapBtn()
    local Xpoa, Ypoa = GetCursorPosition()
    local Xmin, Ymin = Minimap:GetLeft(), Minimap:GetBottom()
    Xpoa = Xmin - Xpoa / Minimap:GetEffectiveScale() + 70
    Ypoa = Ypoa / Minimap:GetEffectiveScale() - Ymin - 70
    myIconPos = math.deg(math.atan2(Ypoa, Xpoa))
    minibtn:ClearAllPoints()
    minibtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - (80 * cos(myIconPos)), (80 * sin(myIconPos)) - 52)
end
 
minibtn:RegisterForDrag("LeftButton")
minibtn:SetScript("OnDragStart", function()
    minibtn:StartMoving()
    minibtn:SetScript("OnUpdate", UpdateMapBtn)
end)
 
minibtn:SetScript("OnDragStop", function()
    minibtn:StopMovingOrSizing();
    minibtn:SetScript("OnUpdate", nil)
    UpdateMapBtn();
end)
 
-- Set position
minibtn:ClearAllPoints();
minibtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - (80 * cos(myIconPos)),(80 * sin(myIconPos)) - 52)
 
-- Control clicks
minibtn:SetScript("OnClick", function()
    MyAddon_ToggleGroundClutter()
end)