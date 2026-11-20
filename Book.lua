local _, ns = ...
local L = ns.L

local WIDTH, HEIGHT, ROW_HEIGHT, INDENT = 480, 540, 18, 16
-- Tab, its label; the first is shown when the book opens for the first time.
local TABS = {
    { "craftable", "BOOK_CRAFTABLE" },
    { "almost", "BOOK_ALMOST" },
    { "all", "BOOK_ALL" },
    { "beasts", "BOOK_BEASTS" },
}
local HAVE_COLOR, MISSING_COLOR = { 0.25, 1, 0.25 }, { 1, 0.3, 0.3 }
local GOLD, GRAY = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount

local PLUS, MINUS = [[Interface\Buttons\UI-PlusButton-Up]], [[Interface\Buttons\UI-MinusButton-Up]]

local window, content
local rows = {}
local tab = "craftable"
-- Headers clicked open or closed this session: beasts start closed, as there
-- may be hundreds, and professions open.
local toggled = {}
-- What the search box holds, lowercased, or nil.
local search

function ns.SetBookSearch(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$"):lower() or ""
    search = text ~= "" and text or nil
end

local function Matches(text)
    return type(text) == "string" and text:lower():find(search, 1, true) ~= nil
end

local function Count(itemID, includeBank)
    local count = GetItemCount and GetItemCount(itemID, includeBank)
    if count == nil or (issecretvalue and issecretvalue(count)) or type(count) ~= "number" then return 0 end
    return count
end

-- How many of an item the character has, bank included. With the bank closed
-- the game may not count it, so what the bank held when last open stands in.
local function Have(itemID)
    local bags = Count(itemID, false)
    local bank = Count(itemID, true) - bags
    if bank <= 0 then bank = ns.char.bank[itemID] or 0 end
    return bags + bank
end

-- The bank's containers: the main slots and its bags or tabs, whichever this
-- client has.
local function BankContainers()
    local list = {}
    local indexes = Enum and Enum.BagIndex
    if indexes then
        for name, index in pairs(indexes) do
            if name == "Bank" or name == "Reagentbank" or name:find("^BankBag_") or name:find("^CharacterBankTab_") then
                list[#list + 1] = index
            end
        end
    end
    if #list == 0 then
        list[1] = BANK_CONTAINER or -1
        local first = (NUM_BAG_SLOTS or 4) + 1
        for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
            list[#list + 1] = bag
        end
    end
    return list
end

local bankOpen = false

local function RememberBank()
    local container = C_Container
    if not (bankOpen and container and container.GetContainerNumSlots and container.GetContainerItemInfo) then return end
    local bank = wipe(ns.char.bank)
    for _, bag in ipairs(BankContainers()) do
        local ok, slots = pcall(container.GetContainerNumSlots, bag)
        for slot = 1, ok and type(slots) == "number" and slots or 0 do
            local info = container.GetContainerItemInfo(bag, slot)
            local itemID, stack = info and info.itemID, info and info.stackCount
            if type(itemID) == "number" and type(stack) == "number" then bank[itemID] = (bank[itemID] or 0) + stack end
        end
    end
end

local bankWatcher = CreateFrame("Frame")
bankWatcher:RegisterEvent("BANKFRAME_OPENED")
bankWatcher:RegisterEvent("BANKFRAME_CLOSED")
bankWatcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
bankWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
bankWatcher:SetScript("OnEvent", function(_, event)
    if not ns.char then return end
    -- At closing the bank's contents may already be gone, so nothing is read then.
    if event == "BANKFRAME_CLOSED" then
        bankOpen = false
        return
    end
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        -- Its contents can arrive just after the window.
        C_Timer.After(0.5, RememberBank)
    end
    RememberBank()
end)

local function WithIcon(name, icon)
    if icon then return "|T" .. icon .. ":0|t " .. name end
    return name
end

local function Line(lines, text, color, indent, itemID)
    lines[#lines + 1] = { text = text, color = color, indent = indent or 0, itemID = itemID }
end

local function IsOpen(key, openByDefault)
    -- While searching everything found is shown.
    if search then return true end
    if toggled[key] then return not openByDefault end
    return openByDefault
end

-- A line that opens or closes what is under it; returns whether it is open.
local function Header(lines, text, color, key, openByDefault, indent, itemID)
    local open = IsOpen(key, openByDefault)
    Line(lines, "|T" .. (open and MINUS or PLUS) .. ":16|t " .. text, color, indent, itemID)
    lines[#lines].toggle = key
    return open
end

function ns.ToggleBookEntry(key)
    toggled[key] = not toggled[key] or nil
end

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

-- How many times the recipe can be made from what the character has, and
-- whether any of its reagents are there at all.
local function Craftable(recipe)
    local times, any = math.huge, false
    for itemID, need in pairs(recipe.reagents) do
        local have = Have(itemID)
        times = math.min(times, math.floor(have / need))
        if have > 0 then any = true end
    end
    return times, any
end

local function CompareRecipes(a, b)
    local ra, rb = ns.recipes[a], ns.recipes[b]
    local da, db = ra.diff or 4, rb.diff or 4
    if da ~= db then return da < db end
    if ra.name ~= rb.name then return ra.name < rb.name end
    return a < b
end

local function RecipeFound(recipe)
    if not search or Matches(recipe.name) then return true end
    for itemID in pairs(recipe.reagents) do
        if Matches((ns.ItemDisplay(itemID))) then return true end
    end
    return false
end

local function RecipeLines(lines, mode)
    -- profession -> recipe IDs, and how many times each can be made
    local byProfession, times = {}, {}
    for recipeID, recipe in pairs(ns.recipes) do
        if ns.IsListed(recipe) and RecipeFound(recipe) then
            local count, any = Craftable(recipe)
            if mode == "all" or (mode == "craftable" and count > 0) or (mode == "almost" and count == 0 and any) then
                local profession = recipe.prof or L.BOOK_OTHER
                byProfession[profession] = byProfession[profession] or {}
                table.insert(byProfession[profession], recipeID)
                times[recipeID] = count
            end
        end
    end
    for _, profession in ipairs(SortedKeys(byProfession)) do
        local list = byProfession[profession]
        local open = Header(lines, ("%s  |cff999999(%d)|r"):format(profession, #list), GOLD, "prof:" .. profession, true)
        table.sort(list, CompareRecipes)
        for _, recipeID in ipairs(open and list or {}) do
            local recipe = ns.recipes[recipeID]
            local text = WithIcon(recipe.name, recipe.icon)
            if times[recipeID] > 0 then text = text .. "  x" .. times[recipeID] end
            local open = Header(lines, text, ns.DIFFICULTY_COLOR[recipe.diff] or ns.NO_DIFFICULTY_COLOR,
                "recipe:" .. recipeID, true, 1, recipe.out)
            for _, itemID in ipairs(open and SortedKeys(recipe.reagents) or {}) do
                local need, have = recipe.reagents[itemID], Have(itemID)
                local name, icon = ns.ItemDisplay(itemID)
                Line(lines, ("%s  %d/%d"):format(WithIcon(name, icon), have, need),
                    have >= need and HAVE_COLOR or MISSING_COLOR, 2, itemID)
            end
        end
    end
end

-- Items of a source, each followed by what it opens into, if anything.
local function ItemLines(lines, source, indent, depth)
    for _, itemID in ipairs(ns.SourceItems(source)) do
        local name, icon, quality = ns.ItemDisplay(itemID)
        Line(lines, WithIcon(name, icon), { ns.QualityColor(quality) }, indent, itemID)
        local inside = ns.LootSource("item:" .. itemID)
        if inside and inside ~= source and depth < 2 then
            ItemLines(lines, inside, indent + 1, depth + 1)
        end
    end
end

local function Gray(text)
    return "  |cff999999" .. text .. "|r"
end

local KIND_COLOR = { 0.5, 0.8, 1 }

local function Position(at)
    if type(at) == "table" and at[1] and at[2] then return Gray(("%.1f, %.1f"):format(at[1], at[2])) end
    return ""
end

-- Each zone and subzone a source was found in, with where on the map it was
-- last looted there.
local function PlaceLines(lines, source, indent)
    for _, zone in ipairs(SortedKeys(source.places or {})) do
        local subzones = source.places[zone]
        for _, sub in ipairs(SortedKeys(subzones)) do
            Line(lines, (sub == "" and zone or zone .. ": " .. sub) .. Position(subzones[sub]), GRAY, indent)
        end
    end
end

-- A beast and what it drops: under a place, with where on the map it was
-- last looted there; under its kind, with every place it was found.
local function BeastLine(lines, key, indent, at, withPlaces)
    local source = ns.LootSource(key)
    local text = ns.SourceName(key, source) .. Position(at)
    text = text .. Gray("(" .. L.BOOK_LOOTED:format(source.looted) .. ")")
    if Header(lines, text, { 1, 1, 1 }, key, false, indent) then
        if withPlaces then PlaceLines(lines, source, indent + 1) end
        ItemLines(lines, source, indent + 1, 0)
    end
end

-- What kind of creature a source is: its type, and the family of beasts.
local function Kind(source)
    if source.kind == "fish" then return L.BOOK_FISHING end
    if source.ctype and source.family then return source.ctype .. ": " .. source.family end
    return source.ctype or L.BOOK_NO_TYPE
end

-- The beasts by kind, unknown kind last, each kind a header.
local function KindLines(lines, keys, indent, keyPrefix, openByDefault, beastLine)
    local groups = {}
    for _, key in ipairs(keys) do
        local kind = Kind(ns.LootSource(key))
        groups[kind] = groups[kind] or {}
        table.insert(groups[kind], key)
    end
    local kinds = SortedKeys(groups)
    for i, kind in ipairs(kinds) do
        if kind == L.BOOK_NO_TYPE then
            table.remove(kinds, i)
            kinds[#kinds + 1] = kind
            break
        end
    end
    for _, kind in ipairs(kinds) do
        if Header(lines, kind .. Gray("(" .. #groups[kind] .. ")"), KIND_COLOR, keyPrefix .. kind, openByDefault, indent) then
            for _, key in ipairs(groups[kind]) do beastLine(key, indent + 1) end
        end
    end
end

-- A source found by its name or by an item it drops, or that opens out of
-- one of those.
local function SourceFound(key, source, depth)
    if Matches(ns.SourceName(key, source)) then return true end
    for _, itemID in ipairs(ns.SourceItems(source)) do
        if Matches((ns.ItemDisplay(itemID))) then return true end
        local inside = ns.LootSource("item:" .. itemID)
        if inside and inside ~= source and depth < 2 and SourceFound("item:" .. itemID, inside, depth + 1) then
            return true
        end
    end
    return false
end

-- Zone, then subzone, then kind, then the beasts found there; a beast found
-- in several places is under each. Those with no known place come last.
local function PlaceView(lines, found)
    local tree, unplaced = {}, {}
    for _, key in ipairs(found) do
        local places = ns.LootSource(key).places
        if places and next(places) then
            for zone, subzones in pairs(places) do
                tree[zone] = tree[zone] or {}
                for sub in pairs(subzones) do
                    tree[zone][sub] = tree[zone][sub] or {}
                    table.insert(tree[zone][sub], key)
                end
            end
        else
            unplaced[#unplaced + 1] = key
        end
    end
    for _, zone in ipairs(SortedKeys(tree)) do
        local subzones, keys = tree[zone], {}
        for _, list in pairs(subzones) do
            for _, key in ipairs(list) do keys[key] = true end
        end
        local count = #SortedKeys(keys)
        if Header(lines, zone .. Gray("(" .. count .. ")"), GOLD, "zone:" .. zone, false) then
            -- Beasts found where the zone has no subzone come first, right under it.
            for _, sub in ipairs(SortedKeys(subzones)) do
                local indent = 1
                if sub ~= "" then
                    indent = 2
                    if not Header(lines, sub .. Gray("(" .. #subzones[sub] .. ")"), GOLD, "sub:" .. zone .. ":" .. sub, true, 1) then
                        indent = nil
                    end
                end
                if indent then
                    KindLines(lines, subzones[sub], indent, "kind:" .. zone .. ":" .. sub .. ":", true, function(key, at)
                        BeastLine(lines, key, at, ns.LootSource(key).places[zone][sub])
                    end)
                end
            end
        end
    end
    if #unplaced > 0 then
        if Header(lines, L.BOOK_UNPLACED .. Gray("(" .. #unplaced .. ")"), GRAY, "unplaced", false) then
            -- Clearing forgets all of them, not just those found.
            if not search then
                Line(lines, L.BOOK_FORGET, MISSING_COLOR, 1)
                lines[#lines].action = "forget"
            end
            for _, key in ipairs(unplaced) do
                BeastLine(lines, key, 1)
            end
        end
    end
end

local function BeastLines(lines)
    local found = {}
    for _, key in ipairs(ns.Beasts()) do
        if not search or SourceFound(key, ns.LootSource(key), 0) then found[#found + 1] = key end
    end
    if ns.db.beastView == "kind" then
        KindLines(lines, found, 0, "kind:", false, function(key, indent)
            BeastLine(lines, key, indent, nil, true)
        end)
    else
        PlaceView(lines, found)
    end
end

function ns.SetBeastView(view)
    ns.db.beastView = view
end

local function Forget()
    ns.ForgetUnplaced()
    ns.RefreshBook()
end

local ACTIONS = {
    forget = function()
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs.EASYRECIPE_FORGET = StaticPopupDialogs.EASYRECIPE_FORGET or {
                text = L.BOOK_FORGET_CONFIRM,
                button1 = YES,
                button2 = NO,
                OnAccept = Forget,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("EASYRECIPE_FORGET", ns.UnplacedCount())
        else
            Forget()
        end
    end,
}

function ns.BookAction(name)
    ACTIONS[name]()
end

local EMPTY = { craftable = "BOOK_EMPTY_CRAFTABLE", almost = "BOOK_EMPTY_ALMOST", all = "BOOK_EMPTY_ALL",
    beasts = "BOOK_EMPTY_BEASTS" }

-- The lines of a tab: { text, color, indent, itemID }.
function ns.BookLines(mode)
    local lines = {}
    if mode == "beasts" then
        BeastLines(lines)
    else
        RecipeLines(lines, mode)
    end
    if #lines == 0 then
        if search then Line(lines, L.BOOK_NO_MATCH, GRAY) else Line(lines, L[EMPTY[mode]], GRAY) end
    end
    return lines
end

local function ShowItemTooltip(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

local Refresh

local function Row(i)
    local row = rows[i]
    if not row then
        row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", ShowItemTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.action then
                ns.BookAction(self.action)
            elseif self.toggle then
                ns.ToggleBookEntry(self.toggle)
                Refresh()
            end
        end)
        rows[i] = row
    end
    return row
end

function Refresh()
    if not (window and window:IsShown()) then return end
    local lines = ns.BookLines(tab)
    for i, line in ipairs(lines) do
        local row = Row(i)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", line.indent * INDENT, 0)
        row.label:SetPoint("RIGHT")
        row.label:SetText(line.text)
        row.label:SetTextColor(line.color[1], line.color[2], line.color[3])
        row.itemID = line.itemID
        row.toggle = line.toggle
        row.action = line.action
        row:Show()
    end
    for i = #lines + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #lines * ROW_HEIGHT))
    for _, button in ipairs(window.tabs) do
        if button.mode == tab then button:LockHighlight() else button:UnlockHighlight() end
    end
    if tab == "beasts" then
        window.view:SetText(ns.db.beastView == "kind" and L.BOOK_BY_PLACE or L.BOOK_BY_KIND)
        window.view:Show()
    else
        window.view:Hide()
    end
end

-- Bag updates come in bursts while looting or crafting.
ns.RefreshBook = function() Refresh() end

local queued = false
local function QueueRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        Refresh()
    end)
end

local function Build()
    local frame = CreateFrame("Frame", "EasyRecipeBook", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- Escape closes it, like the game's own windows.
    if UISpecialFrames then table.insert(UISpecialFrames, "EasyRecipeBook") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText(L.BOOK_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    frame.tabs = {}
    local tabWidth = (WIDTH - 40) / #TABS
    for i, info in ipairs(TABS) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(tabWidth - 4, 22)
        button:SetPoint("TOPLEFT", 20 + (i - 1) * tabWidth, -46)
        button:SetText(L[info[2]])
        button.mode = info[1]
        button:SetScript("OnClick", function(self)
            tab = self.mode
            Refresh()
        end)
        frame.tabs[i] = button
    end

    -- The game's search box, with its clear button and hint; a plain input box
    -- where the client has none.
    local ok, box = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not ok then box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate") end
    box:SetSize(WIDTH - 170, 20)
    box:SetPoint("TOPLEFT", 26, -74)
    box:SetAutoFocus(false)
    if type(box.Instructions) == "table" then box.Instructions:SetText(L.BOOK_SEARCH) end
    box:HookScript("OnTextChanged", function(self)
        ns.SetBookSearch(self:GetText())
        Refresh()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local view = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    view:SetSize(120, 22)
    view:SetPoint("TOPRIGHT", -20, -73)
    view:SetScript("OnClick", function()
        ns.SetBeastView(ns.db.beastView == "kind" and "place" or "kind")
        Refresh()
    end)
    frame.view = view

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -100)
    scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 60, 1)
    scroll:SetScrollChild(content)

    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then QueueRefresh() end
    end)
    frame:SetScript("OnShow", Refresh)
    return frame
end

function ns.ToggleBook()
    -- Kept only once complete, so a failed build is not shown half made.
    window = window or Build()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
