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

function ns.InitBank()
    for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
        pcall(bankWatcher.RegisterEvent, bankWatcher, event)
    end
end

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
-- `trash` is an optional { kind, ... } for the bin on the right of the row.
local function Header(lines, text, color, key, openByDefault, indent, itemID, trash)
    local open = IsOpen(key, openByDefault)
    Line(lines, "|T" .. (open and MINUS or PLUS) .. ":16|t " .. text, color, indent, itemID)
    lines[#lines].toggle = key
    if trash and not search then lines[#lines].trash = trash end
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
        local label = ns.PlaceLabel(zone)
        for _, sub in ipairs(SortedKeys(subzones)) do
            Line(lines, (sub == "" and label or label .. ": " .. sub) .. Position(subzones[sub]), GRAY, indent)
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
        local trash = { "sources", groups[kind] }
        if Header(lines, kind .. Gray("(" .. #groups[kind] .. ")"), KIND_COLOR, keyPrefix .. kind, openByDefault, indent, nil, trash) then
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
        local trash = { "zone", zone }
        if Header(lines, ns.PlaceLabel(zone) .. Gray("(" .. count .. ")"), GOLD, "zone:" .. zone, false, 0, nil, trash) then
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
        if Header(lines, L.BOOK_UNPLACED .. Gray("(" .. #unplaced .. ")"), GRAY, "unplaced", false, 0, nil, { "unplaced" }) then
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

-- Our own yes/no window. The game's StaticPopup is blocked for addons on some
-- clients ("only available to the Blizzard UI").
local confirm
local function Confirm(_, text, fn, arg)
    local message = text
    if arg ~= nil then
        local ok, formatted = pcall(string.format, text, arg)
        if ok then message = formatted end
    end
    if not confirm then
        confirm = CreateFrame("Frame", "EasyRecipeConfirm", UIParent, "BackdropTemplate")
        confirm:SetSize(360, 140)
        confirm:SetPoint("CENTER")
        confirm:SetFrameStrata("DIALOG")
        confirm:SetClampedToScreen(true)
        confirm:EnableMouse(true)
        confirm:SetBackdrop({
            bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
            edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        confirm.text:SetPoint("TOPLEFT", 20, -24)
        confirm.text:SetPoint("TOPRIGHT", -20, -24)
        confirm.text:SetJustifyH("CENTER")
        confirm.text:SetWordWrap(true)
        local yes = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
        yes:SetSize(110, 24)
        yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -8, 18)
        yes:SetText(L.BOOK_YES)
        yes:SetScript("OnClick", function()
            confirm:Hide()
            if confirm.fn then confirm.fn() end
            ns.RefreshBook()
        end)
        local no = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
        no:SetSize(110, 24)
        no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 8, 18)
        no:SetText(L.BOOK_NO)
        no:SetScript("OnClick", function() confirm:Hide() end)
    end
    confirm.fn = fn
    confirm.text:SetText(message)
    confirm:Show()
end

local function ForgetUnplacedAction()
    Confirm("EASYRECIPE_FORGET", L.BOOK_FORGET_CONFIRM, ns.ForgetUnplaced, ns.UnplacedCount())
end

local ACTIONS = {
    forget = ForgetUnplacedAction,
    unplaced = ForgetUnplacedAction,
    forgetAll = function()
        Confirm("EASYRECIPE_FORGET_ALL", L.BOOK_FORGET_ALL_CONFIRM, ns.ResetLoot)
    end,
    sources = function(keys)
        Confirm("EASYRECIPE_FORGET_KEYS", L.BOOK_FORGET_KEYS_CONFIRM, function() ns.ForgetSources(keys) end, #keys)
    end,
    zone = function(zone)
        Confirm("EASYRECIPE_FORGET_ZONE", L.BOOK_FORGET_ZONE_CONFIRM, function() ns.ForgetZone(zone) end, ns.PlaceLabel(zone))
    end,
}

function ns.BookAction(name, arg)
    local action = ACTIONS[name]
    if action then action(arg) end
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
        -- A plain red X. No Blizzard cursor textures: those are forbidden on some clients.
        row.trashBtn = CreateFrame("Button", nil, row)
        row.trashBtn:SetSize(18, 18)
        row.trashBtn:SetPoint("RIGHT", -2, 0)
        row.trashBtn.label = row.trashBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.trashBtn.label:SetPoint("CENTER", 0, 1)
        row.trashBtn.label:SetText("|cffff3030×|r")
        row.trashBtn:SetScript("OnEnter", function(self)
            self.label:SetText("|cffffffff×|r")
        end)
        row.trashBtn:SetScript("OnLeave", function(self)
            self.label:SetText("|cffff3030×|r")
        end)
        row.trashBtn:SetScript("OnClick", function(self)
            local trash = self:GetParent().trash
            if trash then ns.BookAction(trash[1], trash[2]) end
        end)
        row:SetScript("OnEnter", ShowItemTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.toggle then
                ns.ToggleBookEntry(self.toggle)
                Refresh()
            end
        end)
        rows[i] = row
    end
    return row
end

-- One checkbox per profession, the same filter as the options panel's, in
-- rows under the search box on the recipe tabs.
local FILTER_WIDTH, FILTER_HEIGHT, FILTER_COLUMNS, LIST_TOP = 110, 22, 4, -100
local filters = {}

local function Filter(name)
    local check = filters[name]
    if not check then
        check = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", 0, 1)
        check.label:SetWidth(FILTER_WIDTH - 24)
        check.label:SetJustifyH("LEFT")
        check.label:SetWordWrap(false)
        check.label:SetText(name)
        check:SetScript("OnClick", function(self)
            ns.char.hiddenProfs[name] = not self:GetChecked() or nil
            Refresh()
        end)
        filters[name] = check
    end
    return check
end

local function LayoutFilters()
    local shown = tab ~= "beasts"
    local names = shown and ns.Professions() or {}
    for _, check in pairs(filters) do check:Hide() end
    for i, name in ipairs(names) do
        local check = Filter(name)
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", 22 + ((i - 1) % FILTER_COLUMNS) * FILTER_WIDTH,
            LIST_TOP + 2 - math.floor((i - 1) / FILTER_COLUMNS) * FILTER_HEIGHT)
        check:SetChecked(not ns.char.hiddenProfs[name])
        check:Show()
    end
    window.scroll:SetPoint("TOPLEFT", 20, LIST_TOP - math.ceil(#names / FILTER_COLUMNS) * FILTER_HEIGHT)
end

function Refresh()
    if not (window and window:IsShown()) then return end
    LayoutFilters()
    local lines = ns.BookLines(tab)
    for i, line in ipairs(lines) do
        local row = Row(i)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", line.indent * INDENT, 0)
        row.label:SetPoint("RIGHT", row.trashBtn, "LEFT", -4, 0)
        row.label:SetText(line.text)
        row.label:SetTextColor(line.color[1], line.color[2], line.color[3])
        row.itemID = line.itemID
        row.toggle = line.toggle
        row.trash = line.trash
        if line.trash then row.trashBtn:Show() else row.trashBtn:Hide() end
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
        local hasLoot = next(ns.db.loot and ns.db.loot.sources or {}) ~= nil
        if hasLoot and not search then window.clearAll:Show() else window.clearAll:Hide() end
        window.scroll:SetPoint("BOTTOMRIGHT", -36, hasLoot and not search and 48 or 18)
    else
        window.view:Hide()
        window.clearAll:Hide()
        window.scroll:SetPoint("BOTTOMRIGHT", -36, 18)
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

    -- A plain input box: SearchBoxTemplate is Blizzard UI on some clients and
    -- can throw "only available to the Blizzard UI".
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(WIDTH - 170, 20)
    box:SetPoint("TOPLEFT", 26, -74)
    box:SetAutoFocus(false)
    box:SetTextInsets(8, 8, 0, 0)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText(L.BOOK_SEARCH)
    box:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if hint then if text == "" then hint:Show() else hint:Hide() end end
        ns.SetBookSearch(text)
        Refresh()
    end)
    box:SetScript("OnEditFocusGained", function() if hint then hint:Hide() end end)
    box:SetScript("OnEditFocusLost", function(self)
        if hint and (self:GetText() or "") == "" then hint:Show() end
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

    local clearAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearAll:SetSize(WIDTH - 60, 24)
    clearAll:SetPoint("BOTTOM", 0, 16)
    clearAll:SetText(L.BOOK_FORGET_ALL)
    clearAll:SetScript("OnClick", function() ns.BookAction("forgetAll") end)
    clearAll:Hide()
    frame.clearAll = clearAll

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    frame.scroll = scroll
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
