local _, ns = ...
local L = ns.L

-- Enum.TradeskillRelativeDifficulty: Optimal, Medium, Easy, Trivial.
local DIFFICULTY_COLOR = {
    [0] = { 1.00, 0.50, 0.25 },
    [1] = { 1.00, 1.00, 0.00 },
    [2] = { 0.25, 0.75, 0.25 },
    [3] = { 0.50, 0.50, 0.50 },
}
local NO_DIFFICULTY_COLOR = { 1, 1, 1 }
ns.DIFFICULTY_COLOR, ns.NO_DIFFICULTY_COLOR = DIFFICULTY_COLOR, NO_DIFFICULTY_COLOR
-- The setting that lists the recipes of each difficulty.
local DIFFICULTY_SETTING = { [0] = "showOptimal", [1] = "showMedium", [2] = "showEasy", [3] = "showTrivial" }

-- Whether the player's filters let a recipe into the tooltip.
local function IsListed(recipe, db, hiddenProfs, lowest, highest)
    local setting = DIFFICULTY_SETTING[recipe.diff]
    if setting and not db[setting] then return false end
    if recipe.prof and hiddenProfs[recipe.prof] then return false end
    -- Level 0 is an item anyone can use, and no level is an item the game has
    -- not described yet: neither is in or out of a range.
    local level = recipe.lvl
    if level and level > 0 and (level < lowest or level > highest) then return false end
    return true
end

-- The same filters, for the recipe book.
function ns.IsListed(recipe)
    local db = ns.db
    return IsListed(recipe, db, ns.char.hiddenProfs,
        math.min(db.minLevel, db.maxLevel), math.max(db.minLevel, db.maxLevel))
end

local function AddRecipeLines(tooltip, itemID, db)
    local list = ns.RecipesFor(itemID)
    if not list then return end

    local recipes, hiddenProfs = ns.recipes, ns.char.hiddenProfs
    local lowest, highest = math.min(db.minLevel, db.maxLevel), math.max(db.minLevel, db.maxLevel)
    local limit = IsShiftKeyDown() and ns.HARD_CAP or db.maxLines
    -- Recipes of one profession are adjacent, so its name is a line above them.
    local listed, profession = 0, nil
    for i = 1, #list do
        local recipe = recipes[list[i]]
        if IsListed(recipe, db, hiddenProfs, lowest, highest) then
            listed = listed + 1
            if listed == 1 then
                tooltip:AddLine(" ")
                tooltip:AddLine(L.HEADER, 0.2, 1, 0.6)
            end
            if listed <= limit then
                if recipe.prof ~= profession then
                    profession = recipe.prof
                    if profession then tooltip:AddLine(profession, 1, 0.82, 0) end
                end
                local color = DIFFICULTY_COLOR[recipe.diff] or NO_DIFFICULTY_COLOR
                local left = ns.RecipeName and ns.RecipeName(list[i]) or recipe.name
                if recipe.icon then left = "|T" .. recipe.icon .. ":0|t " .. left end
                tooltip:AddDoubleLine(left, recipe.reagents[itemID] .. "x", color[1], color[2], color[3], 0.8, 0.8, 0.8)
            end
        end
    end
    if listed > limit then
        tooltip:AddLine(L.MORE:format(listed - limit), 0.6, 0.6, 0.6)
    end
end

-- Lines are only ever added: the tooltip's owner, anchor and visibility belong
-- to the game and to UI addons such as EllesmereUI.
local function OnItemTooltip(tooltip, data)
    local db = ns.db
    if not db then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local itemID = data and data.id
    -- Herb bags and some Forever container tips omit data.id; the link still has it.
    if (itemID == nil or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number")
        and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    end
    if itemID == nil or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" then return end
    if db.enabled then AddRecipeLines(tooltip, itemID, db) end
    ns.AddDropLines(tooltip, itemID)
end

function ns.HookTooltips()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then
        return false
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    ns.HookUnitTooltips()
    return true
end
