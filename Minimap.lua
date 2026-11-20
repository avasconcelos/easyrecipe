local _, ns = ...
local L = ns.L

local NAME = "EasyRecipe"
local ICON = [[Interface\Icons\INV_Scroll_03]]

local function Library(name)
    return LibStub and LibStub(name, true)
end

-- The button is LibDBIcon's, so minimap addons such as EllesmereUI's collect and
-- skin it like every other addon's button.
function ns.SetupMinimap()
    local broker, icons = Library("LibDataBroker-1.1"), Library("LibDBIcon-1.0")
    if not (broker and icons) or icons:IsRegistered(NAME) then return end
    local launcher = broker:NewDataObject(NAME, {
        type = "launcher",
        text = NAME,
        icon = ICON,
        OnClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                ns.OpenOptions()
            else
                ns.Try(ns.ToggleBook)
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(NAME)
            tooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
            tooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
        end,
    })
    if launcher then icons:Register(NAME, launcher, ns.db.minimap) end
end

function ns.SetMinimapShown(shown)
    ns.db.minimap.hide = not shown
    local icons = Library("LibDBIcon-1.0")
    if icons then icons:Refresh(NAME, ns.db.minimap) end
end
