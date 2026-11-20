local _, ns = ...
local L = ns.L

local C = C_TradeSkillUI
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

-- Events arrive in bursts (one per craft), so a scan waits for them to settle.
local SCAN_DELAY = 0.5

-- True when C_TradeSkillUI has the function and it answers true.
local function Flag(name)
    local fn = C[name]
    return fn and fn() or false
end

-- Only the player's own profession counts: a linked, guild or NPC window
-- lists someone else's recipes as learned.
local function IsOwnProfessionOpen()
    if not (C and C.GetAllRecipeIDs and C.GetRecipeInfo and C.GetRecipeSchematic) then return false end
    if C.IsTradeSkillReady and not C.IsTradeSkillReady() then return false end
    return not (Flag("IsTradeSkillLinked") or Flag("IsTradeSkillGuild") or Flag("IsTradeSkillGuildMember")
        or Flag("IsNPCCrafting") or Flag("IsRuneforging") or Flag("IsDataSourceChanging"))
end

-- Localized profession name from one of the C_TradeSkillUI info getters, or nil.
-- The parent name comes first: a child profession is named after its expansion.
local function ProfessionName(getter, ...)
    local fn = C[getter]
    if not fn then return end
    local ok, info = pcall(fn, ...)
    if not ok or type(info) ~= "table" then return end
    local name = info.parentProfessionName
    if type(name) ~= "string" or name == "" then name = info.professionName end
    if type(name) == "string" and name ~= "" then return name end
end

-- Every recipe in the open window belongs to one profession, so the first
-- recipe can name it when the window's own info comes back empty.
local function OpenProfessionName(recipeIDs)
    return ProfessionName("GetBaseProfessionInfo") or ProfessionName("GetChildProfessionInfo")
        or (recipeIDs[1] and ProfessionName("GetProfessionInfoByRecipeID", recipeIDs[1]))
        or nil
end

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

-- Crafted items the game had no data for yet. Asking made it request them, and
-- GET_ITEM_INFO_RECEIVED says when each one arrives.
local waiting = {}

-- Fills in the level required to use the item a recipe makes, now or once the
-- game has the item's data.
local function ResolveLevel(entry)
    local itemID = entry.out
    if not itemID or entry.lvl or not GetItemInfo then return end
    local _, _, _, _, minLevel = GetItemInfo(itemID)
    if type(minLevel) == "number" then
        entry.lvl = minLevel
    else
        waiting[itemID] = true
    end
end

-- Recipes saved before their item's data arrived are picked up at the next login.
function ns.ResolveLevels()
    for _, entry in pairs(ns.recipes) do
        ResolveLevel(entry)
    end
end

function ns.OnItemInfo(itemID, success)
    if not waiting[itemID] then return end
    waiting[itemID] = nil
    if not success then return end
    for _, entry in pairs(ns.recipes) do
        if entry.out == itemID then ResolveLevel(entry) end
    end
end

local scratch = {}

-- Reads a known recipe from the game into `entry` (or a new table). Returns nil
-- and leaves `entry` alone when the game has nothing usable for it. `learned`
-- vouches for a recipe the game may not report as learned yet.
local function ReadRecipe(recipeID, entry, profession, learned)
    local okInfo, info = pcall(C.GetRecipeInfo, recipeID)
    if not okInfo or type(info) ~= "table" then return end
    if not (learned or info.learned) then return end
    if info.isDummyRecipe or info.isGatheringRecipe or info.isRecraft or info.isSalvageRecipe then return end

    local okSchematic, schematic = pcall(C.GetRecipeSchematic, recipeID, false)
    if not okSchematic or type(schematic) ~= "table" then return end
    local slots = schematic.reagentSlotSchematics
    if type(slots) ~= "table" then return end

    wipe(scratch)
    for _, slot in ipairs(slots) do
        local quantity = slot.quantityRequired
        -- Optional and finishing slots are left out: the recipe works without them.
        if (slot.required or (BASIC ~= nil and slot.reagentType == BASIC))
            and type(quantity) == "number" and quantity > 0 and type(slot.reagents) == "table" then
            for _, reagent in ipairs(slot.reagents) do
                local itemID = reagent.itemID
                if type(itemID) == "number" and itemID > 0 then
                    scratch[itemID] = (scratch[itemID] or 0) + quantity
                end
            end
        end
    end
    if next(scratch) == nil then return end

    entry = entry or {}
    entry.reagents = entry.reagents and wipe(entry.reagents) or {}
    for itemID, quantity in pairs(scratch) do
        entry.reagents[itemID] = quantity
    end
    local name = info.name or schematic.name
    entry.name = type(name) == "string" and name ~= "" and name or ("#" .. recipeID)
    entry.icon = info.icon or schematic.icon
    entry.diff = type(info.relativeDifficulty) == "number" and info.relativeDifficulty or nil
    entry.prof = profession or entry.prof
    -- Recipes that make no item, such as enchantments, have no output and no level.
    local out = schematic.outputItemID
    if type(out) ~= "number" or out <= 0 then out = nil end
    if entry.out ~= out then
        entry.out = out
        entry.lvl = nil
    end
    ResolveLevel(entry)
    return entry
end

function ns.Scan()
    if not IsOwnProfessionOpen() then return end
    local recipeIDs = C.GetAllRecipeIDs()
    if type(recipeIDs) ~= "table" then return end

    local recipes = ns.recipes
    local before = ns.Count()
    local profession = OpenProfessionName(recipeIDs)
    for _, recipeID in ipairs(recipeIDs) do
        local entry = ReadRecipe(recipeID, recipes[recipeID], profession)
        if entry then recipes[recipeID] = entry end
    end
    ns.RebuildIndex()
    ns.AddProfessionOptions()

    local after = ns.Count()
    if after ~= before then ns.Print(L.SCANNED:format(after)) end
end

local queued = false
function ns.QueueScan()
    if queued then return end
    queued = true
    C_Timer.After(SCAN_DELAY, function()
        queued = false
        ns.Scan()
    end)
end

-- A recipe can be learned with the profession window closed, where no scan runs.
function ns.OnRecipeLearned(recipeID)
    if type(recipeID) ~= "number" then return end
    if not ns.recipes[recipeID] and C and C.GetRecipeInfo and C.GetRecipeSchematic then
        local entry = ReadRecipe(recipeID, nil, ProfessionName("GetProfessionInfoByRecipeID", recipeID), true)
        ns.recipes[recipeID] = entry
    end
    if ns.recipes[recipeID] then
        ns.RebuildIndex()
        ns.AddProfessionOptions()
    end
    ns.QueueScan()
end
