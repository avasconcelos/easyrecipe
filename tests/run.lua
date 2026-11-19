-- Runs the addon against a stand-in for the WoW API.
-- From the repository root, with Lua 5.1: lua tests/run.lua

local ADDON = "EasyRecipe"
local ROOT = ""

local failures, checks = 0, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        io.write("FAIL: ", label, "\n")
    end
end
local function equal(actual, expected, label)
    check(actual == expected, ("%s (expected %s, got %s)"):format(label, tostring(expected), tostring(actual)))
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local COPPER_BAR, COARSE_STONE, FLUX, LINEN = 2840, 2836, 2880, 2589

local game = {}
local function ResetGame()
    game.locale = "enUS"
    game.shift = false
    game.ready = true
    game.linked = false
    game.printed = {}
    game.timers = {}
    game.frames = {}
    game.postCalls = {}
    game.secret = {}
    -- What the open window says about itself. The child info is empty, as it
    -- was seen to be on Forever.
    game.base = { professionID = 164, professionName = "Blacksmithing" }
    game.child = { professionID = 0, professionName = "" }
    game.byRecipe = {}
    game.combat = false
    -- What the options panel, the minimap libraries and the frames were given.
    game.settings = {}
    game.controls = {}
    game.category = nil
    game.opened = nil
    game.launcher = nil
    game.button = nil
    game.libraries = {
        ["LibDataBroker-1.1"] = {
            NewDataObject = function(_, _, object)
                game.launcher = object
                return object
            end,
        },
        ["LibDBIcon-1.0"] = {
            IsRegistered = function() return game.button ~= nil end,
            Register = function(_, name, object, db)
                assert(object.icon, "a minimap button needs an icon")
                game.button = { name = name, db = db, shown = not db.hide }
            end,
            Refresh = function(_, _, db) game.button.shown = not db.hide end,
        },
    }
    -- itemID -> level required to use it, for the items the client has data for.
    -- An item anyone can use has level 0.
    game.items = { [2862] = 1, [2852] = 0, [3469] = 5, [2845] = 9, [3488] = 13 }
    -- recipeID -> info and reagent slots, as the profession window gives them
    game.recipes = {
        [2660] = { name = "Rough Sharpening Stone", icon = 135248, learned = true, diff = 3, out = 2862,
            slots = { { type = 1, required = true, qty = 1, items = { 2835 } } } },
        [2662] = { name = "Copper Chain Pants", icon = 134583, learned = true, diff = 2, out = 2852,
            slots = { { type = 1, required = true, qty = 4, items = { COPPER_BAR } } } },
        [3319] = { name = "Copper Chain Boots", icon = 132535, learned = true, diff = 0, out = 3469,
            slots = { { type = 1, required = true, qty = 8, items = { COPPER_BAR } } } },
        [2738] = { name = "Copper Axe", icon = 132417, learned = true, diff = 1, out = 2845,
            slots = {
                { type = 1, required = true, qty = 6, items = { COPPER_BAR } },
                { type = 1, required = true, qty = 2, items = { FLUX } },
                -- an optional slot must not count as a use of the item
                { type = 2, required = false, qty = 1, items = { COARSE_STONE } },
            } },
        [3293] = { name = "Copper Battle Axe", icon = 132417, learned = false, diff = 0, out = 3488,
            slots = { { type = 1, required = true, qty = 12, items = { COPPER_BAR } } } },
        [9999] = { name = "Dummy", icon = 1, learned = true, diff = 0, dummy = true,
            slots = { { type = 1, required = true, qty = 1, items = { COPPER_BAR } } } },
        [9998] = { name = "No Reagents", icon = 1, learned = true, diff = 0, slots = {} },
    }
end

local function InstallGame()
    wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        game.printed[#game.printed + 1] = table.concat(parts, " ")
    end
    GetLocale = function() return game.locale end
    IsShiftKeyDown = function() return game.shift end
    issecretvalue = function(v) return game.secret[v] == true end
    SlashCmdList = {}
    Enum = {
        CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2 },
        TooltipDataType = { Item = 0 },
    }
    C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
    TooltipDataProcessor = {
        AddTooltipPostCall = function(dataType, fn)
            assert(dataType == Enum.TooltipDataType.Item, "only item tooltips are hooked")
            game.postCalls[#game.postCalls + 1] = fn
        end,
    }
    -- A frame, button or font string. Layout calls are accepted and ignored.
    local function NewWidget(name)
        local widget = { name = name, events = {}, scripts = {}, shown = true }
        function widget:RegisterEvent(event) self.events[event] = true end
        function widget:UnregisterEvent(event) self.events[event] = nil end
        function widget:SetScript(script, fn) self.scripts[script] = fn end
        function widget:Show() self.shown = true end
        function widget:Hide() self.shown = false end
        function widget:SetText(text) self.text = text end
        function widget:GetStringHeight() return 120 end
        function widget:CreateFontString() return NewWidget() end
        return setmetatable(widget, { __index = function() return function() end end })
    end
    UIParent = NewWidget("UIParent")
    CreateFrame = function(_, name)
        local frame = NewWidget(name)
        game.frames[#game.frames + 1] = frame
        return frame
    end
    InCombatLockdown = function() return game.combat end
    C_Item = {
        GetItemInfo = function(itemID)
            local level = game.items[itemID]
            if level then return "Item " .. itemID, "link", 1, level + 5, level end
        end,
    }
    LibStub = function(name, silent)
        assert(silent == true, "a missing library must not raise an error")
        return game.libraries[name]
    end

    -- The game's options panel: settings by variable name, controls in order.
    local function NewSetting(variable, name, get, set)
        assert(not game.settings[variable], variable .. " registered twice")
        local setting = { name = name }
        function setting:GetValue() return get() end
        function setting:SetValue(value) set(value) end
        game.settings[variable] = setting
        return setting
    end
    local function AddControl(kind, setting, tooltip)
        assert(type(tooltip) == "string" and tooltip ~= "", setting.name .. " has a tooltip")
        game.controls[#game.controls + 1] = kind .. ":" .. setting.name
    end
    Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            local category, layout = { name = name }, {}
            function category:GetID() return "id of " .. name end
            function layout:AddInitializer(initializer) game.controls[#game.controls + 1] = initializer end
            return category, layout
        end,
        RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
            assert(type(tbl[key]) == varType and type(default) == varType, variable .. " is a " .. varType)
            return NewSetting(variable, name, function() return tbl[key] end, function(value) tbl[key] = value end)
        end,
        RegisterProxySetting = function(_, variable, _, name, _, get, set)
            return NewSetting(variable, name, get, set)
        end,
        CreateCheckbox = function(_, setting, tooltip) AddControl("checkbox", setting, tooltip) end,
        CreateSliderOptions = function(lowest, highest)
            return { lowest = lowest, highest = highest, SetLabelFormatter = function() end }
        end,
        CreateSlider = function(_, setting, options, tooltip)
            assert(options.lowest < options.highest, "slider range")
            AddControl("slider", setting, tooltip)
        end,
        RegisterAddOnCategory = function(category) game.category = category end,
        OpenToCategory = function(id) game.opened = id end,
    }
    CreateSettingsListSectionHeaderInitializer = function(text) return "header:" .. text end
    C_TradeSkillUI = {
        IsTradeSkillReady = function() return game.ready end,
        IsTradeSkillLinked = function() return game.linked, game.linked and "Someone" or nil end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        GetBaseProfessionInfo = function() return game.base end,
        GetChildProfessionInfo = function() return game.child end,
        GetProfessionInfoByRecipeID = function(id) return game.byRecipe[id] end,
        GetAllRecipeIDs = function()
            local ids = {}
            for id in pairs(game.recipes) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end,
        GetRecipeInfo = function(id)
            local r = game.recipes[id]
            if not r then return nil end
            return { recipeID = id, name = r.name, icon = r.icon, learned = r.learned,
                relativeDifficulty = r.diff, isDummyRecipe = r.dummy or false,
                isGatheringRecipe = false, isRecraft = false, isSalvageRecipe = false }
        end,
        GetRecipeSchematic = function(id, isRecraft)
            assert(isRecraft == false, "isRecraft must be passed")
            local r = assert(game.recipes[id], "schematic of an unknown recipe")
            local slots = {}
            for i, s in ipairs(r.slots) do
                local reagents = {}
                for j, itemID in ipairs(s.items) do reagents[j] = { itemID = itemID } end
                slots[i] = { reagentType = s.type, required = s.required, quantityRequired = s.qty, reagents = reagents }
            end
            return { recipeID = id, name = r.name, icon = r.icon, outputItemID = r.out, reagentSlotSchematics = slots }
        end,
    }
    local function NewTooltip()
        local tooltip = { lines = {}, forbidden = false }
        function tooltip:IsForbidden() return self.forbidden end
        function tooltip:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { text, nil, r, g, b } end
        function tooltip:AddDoubleLine(left, right, r, g, b) self.lines[#self.lines + 1] = { left, right, r, g, b } end
        return tooltip
    end
    GameTooltip, ItemRefTooltip, ShoppingTooltip1 = NewTooltip(), NewTooltip(), NewTooltip()
end

---------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------
-- Loads the files the TOC lists, in its order, as the client does.
local function LoadAddon()
    local ns = {}
    local toc = assert(io.open(ROOT .. ADDON .. ".toc", "r"), "TOC not found; run from the repository root")
    for line in toc:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        -- The libraries are not the addon's: LibStub above stands in for them.
        if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 5) ~= "Libs\\" then
            local chunk = assert(loadfile(ROOT .. line:gsub("\\", "/")))
            chunk(ADDON, ns)
        end
    end
    toc:close()
    return ns
end

local function Fire(event, ...)
    for _, frame in ipairs(game.frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

-- The frame created with this global name, or nil.
local function Window(name)
    for _, frame in ipairs(game.frames) do
        if frame.name == name then return frame end
    end
end

-- Clicks the button with this label.
local function Click(label)
    for _, frame in ipairs(game.frames) do
        if frame.text == label and frame.scripts.OnClick then return frame.scripts.OnClick(frame) end
    end
    error("no button labeled " .. label)
end

-- The value of an option, set the way the options panel sets it.
local function SetOption(variable, value)
    assert(game.settings["EasyRecipe_" .. variable], "no option " .. variable):SetValue(value)
end

local function HasLine(lines, text)
    for _, line in ipairs(lines) do
        if line[1]:find(text, 1, true) then return true end
    end
    return false
end

local function RunTimers()
    local timers = game.timers
    game.timers = {}
    for _, fn in ipairs(timers) do fn() end
    return #timers
end

local function Hover(itemID, tooltip)
    tooltip = tooltip or GameTooltip
    tooltip.lines = {}
    for _, fn in ipairs(game.postCalls) do fn(tooltip, { type = 0, id = itemID }) end
    return tooltip.lines
end

local function Login()
    local ns = LoadAddon()
    Fire("ADDON_LOADED", "SomeOtherAddon")
    Fire("ADDON_LOADED", ADDON)
    Fire("PLAYER_LOGIN")
    return ns
end

local function OpenProfession()
    Fire("TRADE_SKILL_SHOW")
    Fire("TRADE_SKILL_LIST_UPDATE")
    Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    return RunTimers()
end

local function Printed(pattern)
    for _, line in ipairs(game.printed) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
ResetGame()
InstallGame()
EasyRecipeDB, EasyRecipeCharDB = nil, nil

-- First login: nothing recorded yet.
local ns = Login()
check(Printed("open each of your profession windows"), "first login explains what to do")
equal(#Hover(COPPER_BAR), 0, "no lines before any scan")
equal(#game.postCalls, 1, "one item post call registered")

-- Opening the profession records its recipes in a single scan.
equal(OpenProfession(), 1, "a burst of events queues one scan")
check(Printed("4 known recipes recorded."), "scan reports the known recipes")
equal(select(2, ns.Count()), 5, "dummy and reagent-less recipes are not stored")

local lines = Hover(COPPER_BAR)
equal(#lines, 6, "blank + header + profession + three known recipes")
equal(lines[1][1], " ", "blank separator")
equal(lines[2][1], "Recipes using this item", "header")
equal(lines[3][1], "Blacksmithing", "profession the recipes belong to")
equal(lines[3][2], nil, "profession is a line of its own")
equal(lines[4][1], "|T132535:0|t Copper Chain Boots", "hardest recipe first, with its icon")
equal(lines[4][2], "8x", "quantity the recipe needs")
equal(lines[4][4], 0.50, "optimal recipes are orange")
equal(lines[5][1], "|T132417:0|t Copper Axe", "then medium")
equal(lines[5][2], "6x", "quantity of the second recipe")
equal(lines[6][1], "|T134583:0|t Copper Chain Pants", "then easy")
equal(#Hover(COARSE_STONE), 0, "an optional reagent slot is not a use")
equal(#Hover(FLUX), 4, "second reagent of a recipe is indexed too")
equal(#Hover(LINEN), 0, "unrelated item is untouched")

-- Tooltips that must be left alone.
equal(#Hover(COPPER_BAR, ShoppingTooltip1), 0, "comparison tooltips are skipped")
equal(#Hover(COPPER_BAR, ItemRefTooltip), 6, "linked item tooltips are handled")
GameTooltip.forbidden = true
equal(#Hover(COPPER_BAR), 0, "forbidden tooltip is skipped")
GameTooltip.forbidden = false
game.secret[COPPER_BAR] = true
equal(#Hover(COPPER_BAR), 0, "secret item id is skipped")
game.secret[COPPER_BAR] = nil
for _, fn in ipairs(game.postCalls) do fn(GameTooltip, nil) end
check(true, "missing tooltip data does not error")

-- Options.
SlashCmdList.EASYRECIPE("all")
lines = Hover(COPPER_BAR)
equal(#lines, 7, "unlearned recipes join the list, under the same profession line")
equal(lines[7][1], "|T132417:0|t Copper Battle Axe (not learned)", "unlearned recipes come last, marked")
equal(lines[7][2], "12x", "unlearned quantity")

SlashCmdList.EASYRECIPE("max 2")
lines = Hover(COPPER_BAR)
equal(#lines, 6, "blank + header + profession + two recipes + more line")
equal(lines[6][1], "+2 more (hold Shift while hovering)", "more line counts what is hidden")
game.shift = true
equal(#Hover(COPPER_BAR), 7, "Shift shows every recipe")
game.shift = false
SlashCmdList.EASYRECIPE("max 0")
equal(EasyRecipeDB.maxLines, 2, "invalid max is refused")
SlashCmdList.EASYRECIPE("max 999")
equal(EasyRecipeDB.maxLines, 40, "max is capped")
SlashCmdList.EASYRECIPE("all")
SlashCmdList.EASYRECIPE("max 8")

SlashCmdList.EASYRECIPE("off")
equal(#Hover(COPPER_BAR), 0, "off adds nothing")
SlashCmdList.EASYRECIPE("  ON ")
equal(#Hover(COPPER_BAR), 6, "on restores the lines")
game.printed = {}
SlashCmdList.EASYRECIPE("")
check(Printed("4 known recipes recorded (5 including unlearned)."), "status line")

-- Learning a recipe with the window closed.
game.ready = false
game.recipes[3293].learned = true
Fire("NEW_RECIPE_LEARNED", 3293)
RunTimers()
equal(#Hover(COPPER_BAR), 7, "newly learned recipe shows without a rescan")

-- Someone else's profession must not be recorded.
game.ready = true
game.linked = true
game.recipes[7777] = { name = "Their Recipe", icon = 1, learned = true, diff = 0,
    slots = { { type = 1, required = true, qty = 1, items = { LINEN } } } }
OpenProfession()
equal(#Hover(LINEN), 0, "linked profession is not scanned")
game.linked = false
game.recipes[7777] = nil

-- A window still loading is skipped; the next update picks it up.
game.ready = false
game.recipes[3319].diff = 3
OpenProfession()
equal(Hover(COPPER_BAR)[5][1], "|T132535:0|t Copper Chain Boots", "not ready: order unchanged")
game.ready = true
OpenProfession()
lines = Hover(COPPER_BAR)
equal(lines[7][1], "|T132535:0|t Copper Chain Boots", "trivial recipe now sorts last")
equal(lines[7][3], 0.50, "and is gray")

-- A reload keeps the data: saved variables only, no profession window.
ResetGame()
InstallGame()
game.ready = false
EasyRecipeCharDB.recipes.bad = { name = "x", reagents = {} }
EasyRecipeCharDB.recipes[5] = "garbage"
ns = Login()
check(not Printed("open each of your profession windows"), "hint is not repeated")
equal(#Hover(COPPER_BAR), 7, "saved recipes are indexed at load, profession included")
equal(EasyRecipeCharDB.recipes.bad, nil, "malformed saved entries are dropped")
equal(EasyRecipeCharDB.recipes[5], nil, "non-table saved entries are dropped")

-- Reset.
SlashCmdList.EASYRECIPE("reset")
equal(#Hover(COPPER_BAR), 0, "reset clears the index")
equal(next(EasyRecipeCharDB.recipes), nil, "reset clears the saved recipes")

-- Recipes of a second profession get their own profession line.
local BOLTS = { name = "Handful of Copper Bolts", icon = 133025, learned = true, diff = 1,
    slots = { { type = 1, required = true, qty = 1, items = { COPPER_BAR } } } }
ResetGame()
InstallGame()
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
OpenProfession()
game.base = { professionID = 202, professionName = "Engineering" }
game.recipes = { [3922] = BOLTS }
OpenProfession()
lines = Hover(COPPER_BAR)
equal(#lines, 8, "two professions: two profession lines")
equal(lines[3][1], "Blacksmithing", "first profession")
equal(lines[6][1], "|T134583:0|t Copper Chain Pants", "its recipes stay together")
equal(lines[7][1], "Engineering", "second profession")
equal(lines[8][1], "|T133025:0|t Handful of Copper Bolts", "its recipe")

-- The profession name is taken from whichever source has one.
local function ProfessionLineWith(base, child, byRecipe)
    ResetGame()
    InstallGame()
    EasyRecipeDB, EasyRecipeCharDB = nil, nil
    game.base, game.child, game.byRecipe = base, child, byRecipe or {}
    Login()
    OpenProfession()
    return Hover(COPPER_BAR)
end
local EMPTY = { professionID = 0, professionName = "" }
lines = ProfessionLineWith(EMPTY, { professionName = "Classic Blacksmithing", parentProfessionName = "Blacksmithing" })
equal(lines[3][1], "Blacksmithing", "child info names the profession by its parent")
lines = ProfessionLineWith(nil, EMPTY, { [2660] = { professionName = "Blacksmithing" } })
equal(lines[3][1], "Blacksmithing", "the first recipe names the profession")
lines = ProfessionLineWith(nil, nil)
equal(#lines, 5, "no profession name: recipes are listed without the line")
equal(lines[3][1], "|T132535:0|t Copper Chain Boots", "and start right after the header")

-- A later scan fills in the profession of recipes recorded without one.
game.base = { professionID = 164, professionName = "Blacksmithing" }
OpenProfession()
equal(Hover(COPPER_BAR)[3][1], "Blacksmithing", "rescan adds the missing profession")

-- Options panel, minimap button and welcome window on a first login.
ResetGame()
InstallGame()
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
equal(game.category and game.category.name, "EasyRecipe", "options panel is registered")
equal(#game.controls, 13, "three headers, seven checkboxes and three sliders")
equal(game.controls[1], "header:General", "panel starts with the general section")
equal(game.controls[7], "checkbox:|cffff8040Orange|r", "difficulty checkboxes carry their color")
equal(game.controls[13], "slider:Highest level", "level range closes the panel")
equal(game.button and game.button.db, EasyRecipeDB.minimap, "minimap button keeps its place in the saved settings")
check(game.button.shown, "minimap button is shown by default")
local intro = Window("EasyRecipeIntro")
check(intro and intro.shown, "first login shows the welcome window")

game.launcher.OnClick()
equal(game.opened, "id of EasyRecipe", "clicking the minimap button opens the options")
game.opened, game.combat = nil, true
SlashCmdList.EASYRECIPE("config")
equal(game.opened, nil, "options stay closed in combat")
check(Printed("can't be opened in combat"), "and the player is told why")
game.combat = false
SlashCmdList.EASYRECIPE("config")
equal(game.opened, "id of EasyRecipe", "/easyrecipe config opens the options")
GameTooltip.lines = {}
game.launcher.OnTooltipShow(GameTooltip)
equal(GameTooltip.lines[2][1], "Click to open the options.", "minimap button says what a click does")

SetOption("minimap", false)
check(EasyRecipeDB.minimap.hide and not game.button.shown, "minimap button can be hidden")
equal(game.settings.EasyRecipe_minimap:GetValue(), false, "and its checkbox follows")
SetOption("minimap", true)
check(game.button.shown, "minimap button can be shown again")

equal(EasyRecipeDB.introShown, false, "welcome window is not read until a button says so")
Click("Got it")
check(EasyRecipeDB.introShown and not intro.shown, "Got it closes the welcome window for good")
game.opened = nil
SlashCmdList.EASYRECIPE("intro")
check(intro.shown, "/easyrecipe intro shows it again")
Click("Open the options")
check(not intro.shown and game.opened == "id of EasyRecipe", "its other button opens the options")

-- Filters. The axe's item is not in the client's cache when it is scanned.
local axeLevel = game.items[2845]
game.items[2845] = nil
OpenProfession()
equal(#game.controls, 15, "a scanned profession gets a header and a checkbox")
equal(game.controls[15], "checkbox:Blacksmithing", "named after the profession")
OpenProfession()
equal(#game.controls, 15, "a rescan adds no second checkbox")
equal(#Hover(COPPER_BAR), 6, "no filter set: three known recipes")

SetOption("showEasy", false)
lines = Hover(COPPER_BAR)
check(#lines == 5 and not HasLine(lines, "Copper Chain Pants"), "green recipes can be left out")
SetOption("showEasy", true)
SetOption("showUnlearned", true)
SetOption("showOptimal", false)
lines = Hover(COPPER_BAR)
check(not HasLine(lines, "Copper Chain Boots"), "orange recipes can be left out")
check(HasLine(lines, "Copper Battle Axe"), "a recipe not learned has no difficulty to filter by")
SetOption("showOptimal", true)
SetOption("showUnlearned", false)

SetOption("minLevel", 5)
SetOption("maxLevel", 5)
lines = Hover(COPPER_BAR)
equal(#lines, 6, "level 5 only: the level 5 boots, plus what has no level to compare")
check(HasLine(lines, "Copper Chain Pants"), "an item anyone can use is always listed")
check(HasLine(lines, "Copper Axe"), "an item the client has no data for yet is listed")
game.items[2845] = axeLevel
Fire("GET_ITEM_INFO_RECEIVED", 2845, true)
lines = Hover(COPPER_BAR)
check(#lines == 5 and not HasLine(lines, "Copper Axe"), "once its data arrives the level filter applies")
SetOption("minLevel", 60)
SetOption("maxLevel", 9)
lines = Hover(COPPER_BAR)
check(HasLine(lines, "Copper Axe") and not HasLine(lines, "Copper Chain Boots"), "a range set backwards still works")
game.printed = {}
SlashCmdList.EASYRECIPE("")
check(Printed("Crafted item recorded for 5 recipes, its required level for 5."), "status counts the levels known")

-- The level is saved with the recipe: after a reload nothing is asked again.
ResetGame()
InstallGame()
game.ready = false
game.items = {}
Login()
equal(Window("EasyRecipeIntro"), nil, "welcome window is not shown again")
equal(game.controls[15], "checkbox:Blacksmithing", "saved professions have their checkbox at login")
lines = Hover(COPPER_BAR)
check(HasLine(lines, "Copper Axe") and not HasLine(lines, "Copper Chain Boots"), "saved levels and range survive a reload")
SetOption("minLevel", 0)
SetOption("maxLevel", 60)

-- Leaving one of the character's professions out.
game.ready = true
game.base = { professionID = 202, professionName = "Engineering" }
game.recipes = { [3922] = BOLTS }
OpenProfession()
equal(game.controls[16], "checkbox:Engineering", "a profession scanned later gets its checkbox right away")
equal(#Hover(COPPER_BAR), 8, "both professions listed")
SetOption("profession_Engineering", false)
lines = Hover(COPPER_BAR)
check(#lines == 6 and not HasLine(lines, "Engineering"), "a profession can be left out")
equal(EasyRecipeCharDB.hiddenProfs.Engineering, true, "the choice is saved with the character")
SetOption("profession_Blacksmithing", false)
equal(#Hover(COPPER_BAR), 0, "nothing listed: no header either")
SetOption("profession_Engineering", true)
SetOption("profession_Blacksmithing", true)
equal(next(EasyRecipeCharDB.hiddenProfs), nil, "listing them again leaves nothing saved")
equal(#Hover(COPPER_BAR), 8, "and both are back")

-- A client without the options panel or the minimap libraries.
ResetGame()
InstallGame()
Settings, LibStub = nil, nil
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
OpenProfession()
equal(#Hover(COPPER_BAR), 6, "tooltips work without the panel and the button")
check(not Printed("could not be set up"), "their absence is not an error")
SlashCmdList.EASYRECIPE("config")
check(Printed("options panel is not available"), "/easyrecipe config says the panel is missing")

-- One broken piece of the panel does not take the rest down.
ResetGame()
InstallGame()
Settings.CreateSlider = function() error("no sliders here") end
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
equal(#game.controls, 10, "everything but the three sliders is built")
check(Printed("no sliders here"), "the failure is reported in chat")
check(game.button ~= nil and Window("EasyRecipeIntro") ~= nil, "minimap button and welcome window still come up")

-- Portuguese client.
ResetGame()
InstallGame()
game.locale = "ptBR"
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
OpenProfession()
equal(Hover(COPPER_BAR)[2][1], "Receitas que usam este item", "ptBR header")
check(Printed("4 receitas conhecidas registradas."), "ptBR scan message")

-- A client without the tooltip API loads and says so.
ResetGame()
InstallGame()
TooltipDataProcessor = nil
EasyRecipeDB, EasyRecipeCharDB = nil, nil
Login()
check(Printed("no tooltip data API"), "missing tooltip API is reported, not an error")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
