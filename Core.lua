local ADDON, ns = ...
local L = ns.L

-- Most lines a tooltip ever gets, including while Shift is held.
ns.HARD_CAP = 40
-- Highest level any crafted item requires.
ns.LEVEL_CAP = 60

local DEFAULTS = {
    enabled = true,
    showUnlearned = false,
    maxLines = 8,
    showOptimal = true,
    showMedium = true,
    showEasy = true,
    showTrivial = true,
    minLevel = 0,
    maxLevel = ns.LEVEL_CAP,
    introShown = false,
}
ns.DEFAULTS = DEFAULTS

-- Recipes recorded for this character, keyed by recipe spell ID:
-- { name, icon, learned, diff, prof, out, lvl, reagents = { [itemID] = quantity } }
-- `out` is the item the recipe makes and `lvl` the level required to use it.
ns.recipes = {}

-- itemID -> list of recipe IDs using it: known recipes first, then by profession.
local index = {}

local function Print(msg)
    print("|cff33ff99EasyRecipe|r: " .. msg)
end
ns.Print = Print

-- The options panel, minimap button and welcome window are extras: one of them
-- failing must not take the others, or the tooltip, down with it.
function ns.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Print(L.EXTRA_ERROR:format(tostring(err))) end
end

local function CompareRecipes(a, b)
    local ra, rb = ns.recipes[a], ns.recipes[b]
    if ra.learned ~= rb.learned then return ra.learned end
    local pa, pb = ra.prof or "", rb.prof or ""
    if pa ~= pb then return pa < pb end
    local da, db = ra.diff or 4, rb.diff or 4
    if da ~= db then return da < db end
    if ra.name ~= rb.name then return ra.name < rb.name end
    return a < b
end

function ns.RebuildIndex()
    wipe(index)
    for recipeID, recipe in pairs(ns.recipes) do
        for itemID in pairs(recipe.reagents) do
            local list = index[itemID]
            if not list then
                list = {}
                index[itemID] = list
            end
            list[#list + 1] = recipeID
        end
    end
    for _, list in pairs(index) do
        table.sort(list, CompareRecipes)
    end
end

function ns.RecipesFor(itemID)
    return index[itemID]
end

-- Known recipes, all recipes, those whose crafted item is recorded and those
-- whose crafted item's level is.
function ns.Count()
    local learned, total, items, levels = 0, 0, 0, 0
    for _, recipe in pairs(ns.recipes) do
        total = total + 1
        if recipe.learned then learned = learned + 1 end
        if recipe.out then items = items + 1 end
        if recipe.lvl then levels = levels + 1 end
    end
    return learned, total, items, levels
end

-- Names of the professions this character has recipes recorded for, sorted.
function ns.Professions()
    local seen, names = {}, {}
    for _, recipe in pairs(ns.recipes) do
        local name = recipe.prof
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

local function InitDB()
    if type(EasyRecipeDB) ~= "table" then EasyRecipeDB = {} end
    for key, value in pairs(DEFAULTS) do
        if type(EasyRecipeDB[key]) ~= type(value) then EasyRecipeDB[key] = value end
    end
    -- LibDBIcon keeps the minimap button's position and visibility here.
    if type(EasyRecipeDB.minimap) ~= "table" then EasyRecipeDB.minimap = {} end
    ns.db = EasyRecipeDB

    if type(EasyRecipeCharDB) ~= "table" then EasyRecipeCharDB = {} end
    local char = EasyRecipeCharDB
    if type(char.recipes) ~= "table" then char.recipes = {} end
    -- Profession name -> true for the professions left out of the tooltip.
    if type(char.hiddenProfs) ~= "table" then char.hiddenProfs = {} end
    for recipeID, recipe in pairs(char.recipes) do
        if type(recipeID) ~= "number" or type(recipe) ~= "table"
            or type(recipe.name) ~= "string" or type(recipe.reagents) ~= "table" then
            char.recipes[recipeID] = nil
        else
            recipe.learned = recipe.learned and true or false
            if type(recipe.diff) ~= "number" then recipe.diff = nil end
            if type(recipe.prof) ~= "string" or recipe.prof == "" then recipe.prof = nil end
            if type(recipe.out) ~= "number" then recipe.out = nil end
            if type(recipe.lvl) ~= "number" or not recipe.out then recipe.lvl = nil end
        end
    end
    ns.char = char
    ns.recipes = char.recipes
end

local SCAN_EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        ns.RebuildIndex()
        if not ns.HookTooltips() then Print(L.NO_TOOLTIP_API) end
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("NEW_RECIPE_LEARNED")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        for _, name in ipairs(SCAN_EVENTS) do
            self:RegisterEvent(name)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Said once per character: one without professions never has recipes.
        if not ns.char.hinted and next(ns.recipes) == nil then
            ns.char.hinted = true
            Print(L.HINT)
        end
        ns.ResolveLevels()
        ns.Try(ns.SetupOptions)
        ns.Try(ns.SetupMinimap)
        if not ns.db.introShown then ns.Try(ns.ShowIntro) end
    elseif event == "NEW_RECIPE_LEARNED" then
        ns.OnRecipeLearned(arg1)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.OnItemInfo(arg1, arg2)
    else
        ns.QueueScan()
    end
end)

SLASH_EASYRECIPE1 = "/easyrecipe"
SLASH_EASYRECIPE2 = "/ezr"
SlashCmdList.EASYRECIPE = function(msg)
    local db = ns.db
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "config" then
        ns.OpenOptions()
    elseif cmd == "intro" then
        ns.Try(ns.ShowIntro)
    elseif cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        Print(db.enabled and L.ENABLED or L.DISABLED)
    elseif cmd == "all" then
        db.showUnlearned = not db.showUnlearned
        Print(db.showUnlearned and L.ALL_ON or L.ALL_OFF)
    elseif cmd == "max" then
        local n = tonumber(arg)
        if n and n >= 1 then
            db.maxLines = math.min(math.floor(n), ns.HARD_CAP)
            Print(L.MAX_SET:format(db.maxLines))
        else
            Print(L.MAX_USAGE)
        end
    elseif cmd == "reset" then
        wipe(ns.recipes)
        ns.RebuildIndex()
        Print(L.RESET)
    else
        local learned, total, items, levels = ns.Count()
        Print(L.STATUS:format(learned, total))
        Print(L.STATUS_LEVELS:format(items, levels))
        for _, line in ipairs(L.HELP) do
            print("  " .. line)
        end
    end
end
