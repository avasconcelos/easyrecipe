local _, ns = ...
local L = ns.L

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ITEM_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
-- Units that can be the corpse being looted, to learn the creature's name.
local CORPSE_UNITS = { "mouseover", "target", "softenemy", "softinteract", "focus" }

-- npcID -> name learned this session from a kill or a target, used when the
-- loot window opens without that corpse selected.
local pendingNames = {}

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function Text(fn, ...)
    if not fn then return end
    local ok, text = pcall(fn, ...)
    if ok and text ~= nil and not IsSecret(text) and type(text) == "string" and text ~= "" then return text end
end

-- Account-wide: a kind of creature drops the same things for every character.
-- sources: key -> { kind = "npc" | "fish" | "item", name, looted, zones, places, ctype, family,
--   items = { [itemID] = times dropped } }
--   keyed "npc:<npcID>", "fish:<zone>" or "item:<itemID>" for what opens, such
--   as clams; `looted` counts corpses, catches or openings, `zones` holds
--   the zones a creature was looted in, and `places` zone -> subzone ->
--   { x, y }, the map position of the last loot there ("" for no subzone).
-- items: itemID -> { name, icon, quality, reagent } as the loot window showed it.
local loot

-- itemID -> keys of the sources that dropped it, most drops first.
local dropIndex = {}

-- Corpses already counted this session, and the drops of each, so a corpse
-- opened again (or skinned after being looted) is not counted twice.
local seenCorpses, seenDrops = {}, {}
local windowRecorded = false

-- Creature-0-server-instance-zone-npcID-spawn. Players and objects such as
-- herbs, ore and chests have GUIDs of other kinds.
local function NpcID(guid)
    if guid == nil or IsSecret(guid) or type(guid) ~= "string" then return end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- The item opened when the loot comes from one, such as a clam.
local function OpenedItemID(guid)
    if guid == nil or IsSecret(guid) or type(guid) ~= "string" or not guid:find("^Item%-") then return end
    local id = C_Item and C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(guid)
    if type(id) == "number" and not IsSecret(id) then return id end
end

-- The last item used from the bags, for loot that comes without saying it
-- came from an item.
local lastUsed, lastUsedAt
local USE_WINDOW = 3

if hooksecurefunc and C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        local id = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
        if type(id) == "number" and not IsSecret(id) then
            lastUsed, lastUsedAt = id, GetTime()
        end
    end)
end

local function RecentlyOpened()
    if lastUsed and GetTime() - lastUsedAt <= USE_WINDOW then return lastUsed end
end

local function MapID()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if type(map) == "number" and not IsSecret(map) then return map end
end

-- The zone and subzone ("" for none). Not every client answers every one of
-- these, nor at every moment, so the last ones read stand in.
local lastZone, lastSubZone
local function Zone()
    local zone = Text(GetRealZoneText) or Text(GetZoneText)
    if not zone and MapID() and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(MapID())
        zone = info and Text(function() return info.name end)
    end
    if zone then
        lastZone = zone
        local sub = Text(GetSubZoneText) or Text(GetMinimapZoneText) or ""
        lastSubZone = sub == zone and "" or sub
    end
    return lastZone, lastSubZone or ""
end

-- The player's position on the zone map, 0 to 100, or nil where the map has
-- none, such as in dungeons.
local function Position()
    local map = MapID()
    if not map or not C_Map.GetPlayerMapPosition then return end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok and position and position.GetXY) then return end
    local x, y = position:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" or IsSecret(x) or IsSecret(y) or (x == 0 and y == 0) then return end
    return math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function InDungeon()
    if IsInInstance then
        local ok, inside, instanceType = pcall(IsInInstance)
        if ok and inside and (instanceType == "party" or instanceType == "raid") then return true end
    end
    if GetInstanceInfo then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        if ok and (instanceType == "party" or instanceType == "raid") then return true end
    end
end

local function MarkInstance(zone)
    if not (zone and loot and InDungeon()) then return end
    loot.instances = loot.instances or {}
    loot.instances[zone] = true
end

-- Where a source is, from where the player stands. Unless `always`, a place
-- already known is left as it is.
local function RememberPlace(source, always)
    local zone, sub = Zone()
    if not zone then return end
    MarkInstance(zone)
    source.zones = source.zones or {}
    source.zones[zone] = true
    source.places = source.places or {}
    local subzones = source.places[zone] or {}
    source.places[zone] = subzones
    if subzones[sub] and not always then return end
    local x, y = Position()
    subzones[sub] = x and { x, y } or subzones[sub] or {}
end

local zoneWatcher = CreateFrame("Frame")
zoneWatcher:SetScript("OnEvent", function()
    local zone = Zone()
    MarkInstance(zone)
end)

local StartWatchers

-- How a zone is named in the book: outdoor as itself, instances with a tag.
function ns.PlaceLabel(zone)
    if loot and loot.instances and loot.instances[zone] then
        return zone .. " (" .. L.BOOK_DUNGEON .. ")"
    end
    return zone
end

local function SortDrops(itemID)
    local sources = loot.sources
    table.sort(dropIndex[itemID], function(a, b)
        local ca, cb = sources[a].items[itemID], sources[b].items[itemID]
        if ca ~= cb then return ca > cb end
        return a < b
    end)
end

function ns.RebuildLootIndex()
    wipe(dropIndex)
    for key, source in pairs(loot.sources) do
        for itemID in pairs(source.items) do
            local list = dropIndex[itemID]
            if not list then
                list = {}
                dropIndex[itemID] = list
            end
            list[#list + 1] = key
        end
    end
    for itemID in pairs(dropIndex) do
        SortDrops(itemID)
    end
end

function ns.InitLoot()
    local db = ns.db
    if type(db.loot) ~= "table" then db.loot = {} end
    loot = db.loot
    if type(loot.sources) ~= "table" then loot.sources = {} end
    if type(loot.items) ~= "table" then loot.items = {} end
    if type(loot.instances) ~= "table" then loot.instances = {} end
    for zone in pairs(loot.instances) do
        if type(zone) ~= "string" then loot.instances[zone] = nil end
    end
    for key, source in pairs(loot.sources) do
        if type(key) ~= "string" or type(source) ~= "table" or type(source.items) ~= "table"
            or type(source.looted) ~= "number"
            or (source.kind ~= "npc" and source.kind ~= "fish" and source.kind ~= "item") then
            loot.sources[key] = nil
        else
            if type(source.name) ~= "string" then source.name = nil end
            if type(source.zones) ~= "table" then source.zones = nil end
            if type(source.places) ~= "table" then source.places = nil end
            if type(source.ctype) ~= "string" then source.ctype = nil end
            if type(source.family) ~= "string" then source.family = nil end
            for zone, subzones in pairs(source.places or {}) do
                if type(zone) ~= "string" or type(subzones) ~= "table" then source.places[zone] = nil end
            end
            for itemID, times in pairs(source.items) do
                if type(itemID) ~= "number" or type(times) ~= "number" then source.items[itemID] = nil end
            end
        end
    end
    for itemID, info in pairs(loot.items) do
        if type(itemID) ~= "number" or type(info) ~= "table" then loot.items[itemID] = nil end
    end
    ns.RebuildLootIndex()
    StartWatchers()
end

function ns.ResetLoot()
    wipe(loot.sources)
    wipe(loot.items)
    wipe(loot.instances)
    wipe(dropIndex)
    wipe(seenCorpses)
    wipe(seenDrops)
end

local function Unplaced(source)
    return source.kind ~= "item" and not (source.places and next(source.places))
end

-- Creatures and fishing spots with no known place, such as those recorded
-- before places were, and how many there are.
function ns.UnplacedCount()
    local count = 0
    for _, source in pairs(loot.sources) do
        if Unplaced(source) then count = count + 1 end
    end
    return count
end

function ns.ForgetUnplaced()
    for key, source in pairs(loot.sources) do
        if Unplaced(source) then loot.sources[key] = nil end
    end
    ns.RebuildLootIndex()
end

function ns.ForgetSources(keys)
    for _, key in ipairs(keys) do
        loot.sources[key] = nil
    end
    ns.RebuildLootIndex()
end

-- Drops a zone from every creature; those that only lived there are forgotten.
function ns.ForgetZone(zone)
    for key, source in pairs(loot.sources) do
        if source.places and source.places[zone] then
            source.places[zone] = nil
            if source.zones then source.zones[zone] = nil end
            if not next(source.places) then loot.sources[key] = nil end
        end
    end
    if loot.instances then loot.instances[zone] = nil end
    ns.RebuildLootIndex()
end

-- Kinds of creatures and fishing spots recorded.
function ns.LootCount()
    local creatures, spots = 0, 0
    for _, source in pairs(loot.sources) do
        if source.kind == "fish" then
            spots = spots + 1
        elseif source.kind == "npc" then
            creatures = creatures + 1
        end
    end
    return creatures, spots
end

local function Source(key, kind, name)
    local source = loot.sources[key]
    if not source then
        source = { kind = kind, looted = 0, items = {} }
        loot.sources[key] = source
    end
    if name then source.name = name end
    return source
end

local function CountDrop(key, source, itemID)
    local times = source.items[itemID]
    source.items[itemID] = (times or 0) + 1
    if not times then
        local list = dropIndex[itemID]
        if not list then
            list = {}
            dropIndex[itemID] = list
        end
        list[#list + 1] = key
    end
    SortDrops(itemID)
end

-- The item in a loot slot, or nil for money and currencies.
local function SlotItem(slot)
    if GetLootSlotType and GetLootSlotType(slot) ~= ITEM_SLOT then return end
    local link = GetLootSlotLink(slot)
    if link == nil or IsSecret(link) or type(link) ~= "string" then return end
    return tonumber(link:match("item:(%d+)"))
end

-- What the loot window shows of an item, kept so its tooltip lines need
-- nothing from the game's item cache.
local function RememberItem(itemID, slot)
    local info = loot.items[itemID] or {}
    local icon, name, _, _, quality = GetLootSlotInfo(slot)
    if type(name) == "string" and name ~= "" then info.name = name end
    if icon then info.icon = icon end
    if type(quality) == "number" then info.quality = quality end
    if GetItemInfo then
        local reagent = select(17, GetItemInfo(itemID))
        if type(reagent) == "boolean" then info.reagent = reagent end
    end
    loot.items[itemID] = info
end

local function UnitOf(guid)
    for _, unit in ipairs(CORPSE_UNITS) do
        local unitGUID = UnitGUID(unit)
        if unitGUID ~= nil and not IsSecret(unitGUID) and unitGUID == guid then return unit end
    end
end

-- The creature's type, such as Beast or Humanoid, and for beasts their
-- family, such as Bear. Target is tried first: some clients only answer for
-- the selected unit, not for mouseover.
local function RememberKind(source, preferred)
    local tried = {}
    local function Try(unit)
        if not unit or tried[unit] then return end
        tried[unit] = true
        source.ctype = Text(UnitCreatureType, unit) or source.ctype
        source.family = Text(UnitCreatureFamily, unit) or source.family
    end
    Try("target")
    Try(preferred)
    Try("mouseover")
end

-- A kill or a click names the creature for later loot, and fills a record that
-- was already made without a name (common in dungeons).
local function RememberNpcName(npcID, name)
    if type(npcID) ~= "number" or type(name) ~= "string" or name == "" or IsSecret(name) then return end
    pendingNames[npcID] = name
    local source = loot and loot.sources["npc:" .. npcID]
    if source and not source.name then source.name = name end
end

local function LearnSelected(unit)
    local guid = UnitGUID and UnitGUID(unit)
    local npcID = NpcID(guid)
    if not npcID then return end
    RememberNpcName(npcID, Text(UnitName, unit))
    local source = loot and loot.sources["npc:" .. npcID]
    if source then RememberKind(source, unit) end
end

local nameWatcher = CreateFrame("Frame")
nameWatcher:SetScript("OnEvent", function(_, event)
    if not loot then return end
    if event == "PLAYER_TARGET_CHANGED" then
        LearnSelected("target")
        return
    end
    if not CombatLogGetCurrentEventInfo then return end
    local _, subevent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if subevent ~= "UNIT_DIED" and subevent ~= "PARTY_KILL" then return end
    RememberNpcName(NpcID(destGUID), destName)
end)

StartWatchers = function()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        zoneWatcher:RegisterEvent(event)
    end
    -- Target only: COMBAT_LOG_EVENT_UNFILTERED is forbidden for addons on this client
    -- and still opens the Blizzard popup even when called through pcall.
    nameWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
end

local function RecordFishing(count)
    local zone = Zone()
    if not zone then return end
    local key = "fish:" .. zone
    local source = Source(key, "fish", zone)
    source.looted = source.looted + 1
    RememberPlace(source, true)
    for slot = 1, count do
        local itemID = SlotItem(slot)
        if itemID then
            RememberItem(itemID, slot)
            CountDrop(key, source, itemID)
        end
    end
end

local function RecordSources(count)
    -- One window is one opening: a stack of clams keeps its GUID, so openings
    -- are not told apart by it.
    local opened, known = {}, false
    local function RecordOpened(containerID, itemID, slot)
        local key = "item:" .. containerID
        local source = Source(key, "item")
        if not opened[key] then
            opened[key] = true
            source.looted = source.looted + 1
        end
        if itemID then
            RememberItem(itemID, slot)
            CountDrop(key, source, itemID)
        end
    end
    for slot = 1, count do
        local itemID = SlotItem(slot)
        -- A slot lists every corpse or item it came from, each followed by its amount.
        local origins = { GetLootSourceInfo(slot) }
        for i = 1, #origins, 2 do
            local guid = origins[i]
            local npcID = NpcID(guid)
            local containerID = not npcID and OpenedItemID(guid)
            -- A herb, ore or chest names itself: such loot is never an opened item.
            if npcID or containerID or (type(guid) == "string" and not IsSecret(guid) and not guid:find("^Item%-")) then
                known = true
            end
            if containerID then
                RecordOpened(containerID, itemID, slot)
            elseif npcID then
                local key = "npc:" .. npcID
                local unit = UnitOf(guid)
                local source = Source(key, "npc", (unit and Text(UnitName, unit)) or pendingNames[npcID])
                if unit then RememberKind(source, unit) end
                if not source.name and pendingNames[npcID] then source.name = pendingNames[npcID] end
                if not seenCorpses[guid] then
                    seenCorpses[guid] = true
                    RememberPlace(source, true)
                    source.looted = source.looted + 1
                end
                local drop = itemID and guid .. ":" .. itemID
                if drop and not seenDrops[drop] then
                    seenDrops[drop] = true
                    RememberItem(itemID, slot)
                    CountDrop(key, source, itemID)
                end
            end
        end
    end
    -- Nothing named where the loot came from: if an item was just used from
    -- the bags, it was opened.
    local containerID = not known and RecentlyOpened()
    if containerID then
        lastUsed = nil
        for slot = 1, count do
            RecordOpened(containerID, SlotItem(slot), slot)
        end
    end
end

-- LOOT_READY and LOOT_OPENED both come for one window; it is read once.
function ns.OnLootReady()
    if windowRecorded or not loot or not GetNumLootItems then return end
    local count = GetNumLootItems()
    if type(count) ~= "number" or count == 0 then return end
    windowRecorded = true
    -- Dungeons are skipped: corpses often have no name/type, and the list fills
    -- with "Creature #id". The book is for the open world.
    if InDungeon() then return end
    if IsFishingLoot and IsFishingLoot() then
        RecordFishing(count)
    else
        RecordSources(count)
    end
end

function ns.OnLootClosed()
    windowRecorded = false
end

function ns.QualityColor(quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

-- Name, icon and quality of an item: as the loot window showed it, else from
-- the game, which may not have it yet.
function ns.ItemDisplay(itemID)
    local info = loot and loot.items[itemID]
    local name, icon, quality = info and info.name, info and info.icon, info and info.quality
    if not name and GetItemInfo then
        local itemName, _, itemQuality = GetItemInfo(itemID)
        if type(itemName) == "string" then name, quality = itemName, quality or itemQuality end
    end
    if not icon and C_Item and C_Item.GetItemInfoInstant then
        icon = select(5, C_Item.GetItemInfoInstant(itemID))
    end
    return name or ("#" .. itemID), icon, quality
end

function ns.LootSource(key)
    return loot and loot.sources[key]
end

-- How a source is named in a list. An opened item names, after it, the
-- creature it most often came from, so a clam leads back to its crab.
function ns.SourceName(key, source, depth)
    if source.kind == "fish" then return L.FISHING:format(source.name) end
    if source.kind == "item" then
        local itemID = tonumber(key:match("%d+$"))
        local name = ns.ItemDisplay(itemID)
        -- An item found inside another (a box in a box) stops after two steps,
        -- and one found inside itself does not loop.
        local parents = dropIndex[itemID]
        local parentKey = parents and parents[1]
        if parentKey and parentKey ~= key and (depth or 0) < 2 then
            return L.OPENED_FROM:format(name, ns.SourceName(parentKey, loot.sources[parentKey], (depth or 0) + 1))
        end
        return name
    end
    return source.name or L.UNKNOWN_CREATURE:format(tonumber(key:match("%d+$")) or 0)
end

-- The items of a source, most dropped first. With the reagent filter on, only
-- reagents and items that open into something are kept.
function ns.SourceItems(source)
    local db, items, list = ns.db, source.items, {}
    for itemID in pairs(items) do
        local info = loot.items[itemID]
        if not (db.lootReagentsOnly and info and info.reagent == false and not loot.sources["item:" .. itemID]) then
            list[#list + 1] = itemID
        end
    end
    table.sort(list, function(a, b)
        if items[a] ~= items[b] then return items[a] > items[b] end
        return a < b
    end)
    return list
end

-- Keys of the creatures and fishing spots, by name.
function ns.Beasts()
    local keys, names = {}, {}
    for key, source in pairs(loot.sources) do
        if source.kind ~= "item" and source.looted > 0 then
            keys[#keys + 1] = key
            names[key] = ns.SourceName(key, source)
        end
    end
    table.sort(keys, function(a, b)
        if names[a] ~= names[b] then return names[a] < names[b] end
        return a < b
    end)
    return keys
end

local function OnUnitTooltip(tooltip, data)
    local db = ns.db
    if not (db and loot) then return end
    if tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local npcID = NpcID(data and data.guid)
    if not npcID then return end
    local source = loot.sources["npc:" .. npcID]
    if not source then return end
    -- A corpse looted without hovering or targeting it left the name out.
    if not source.name then
        local name = tooltip.GetUnit and Text(function() return tooltip:GetUnit() end)
        if not name and tooltip.GetName then
            local left = _G[tooltip:GetName() .. "TextLeft1"]
            name = left and Text(left.GetText, left)
        end
        if name then RememberNpcName(npcID, name) end
    end
    -- A creature in sight is near: where it lives, and what it is, are learned
    -- without looting it again. Dungeons are not stored as places.
    if not InDungeon() then RememberPlace(source) end
    local unit = UnitOf(data.guid)
    -- Where the game hides unit GUIDs, the unit the tooltip shows is taken as it is.
    if not unit and tooltip.GetUnit then unit = Text(function() return select(2, tooltip:GetUnit()) end) end
    if unit then RememberKind(source, unit) end
    -- Selecting a creature names and types it even when the tooltip is another.
    LearnSelected("target")
    if not db.lootOnUnit or source.looted == 0 then return end

    local list = ns.SourceItems(source)
    if #list == 0 then return end
    local limit = IsShiftKeyDown() and ns.HARD_CAP or db.maxLines
    tooltip:AddLine(" ")
    tooltip:AddLine(L.DROPS_UNIT:format(source.looted), 0.2, 1, 0.6)
    for i = 1, math.min(#list, limit) do
        local name, icon, quality = ns.ItemDisplay(list[i])
        if icon then name = "|T" .. icon .. ":0|t " .. name end
        tooltip:AddLine(name, ns.QualityColor(quality))
    end
    if #list > limit then
        tooltip:AddLine(L.MORE:format(#list - limit), 0.6, 0.6, 0.6)
    end
end

-- The creatures, fishing spots and opened items an item came from, under the
-- item's recipes.
function ns.AddDropLines(tooltip, itemID)
    local db = ns.db
    if not (db.lootOnItem and loot) then return end
    local list = dropIndex[itemID]
    if not list then return end

    local limit = IsShiftKeyDown() and ns.HARD_CAP or db.maxLines
    tooltip:AddLine(" ")
    tooltip:AddLine(L.DROPS_ITEM, 0.2, 1, 0.6)
    for i = 1, math.min(#list, limit) do
        tooltip:AddLine(ns.SourceName(list[i], loot.sources[list[i]]), 1, 1, 1)
    end
    if #list > limit then
        tooltip:AddLine(L.MORE:format(#list - limit), 0.6, 0.6, 0.6)
    end
end

function ns.HookUnitTooltips()
    local types = Enum.TooltipDataType
    if types.Unit then TooltipDataProcessor.AddTooltipPostCall(types.Unit, OnUnitTooltip) end
end
