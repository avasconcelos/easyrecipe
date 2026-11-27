local _, ns = ...
local L = ns.L

local WIDTH, HEIGHT, ROW_HEIGHT, INDENT = 480, 540, 18, 16
-- Same width as the book so long recipe names fit on one line.
local SHOP_WIDTH, SHOP_ROW = WIDTH, 20
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
-- may be hundreds, and professions open. expandOverride forces every header
-- open (true) or closed (false) until the player toggles one by hand.
local toggled, headerDefault, expandOverride = {}, {}, nil
-- What the search box holds, lowercased, or nil.
local search
-- Shopping list for recipe tabs: recipeID -> how many to make. Saved per
-- character (EasyRecipeCharDB.cart) once ns.InitCart has run.
local cart = {}

function ns.InitCart()
    local saved = ns.char.cart
    if type(saved) ~= "table" then saved = {} end
    for recipeID, qty in pairs(saved) do
        if type(recipeID) ~= "number" or type(qty) ~= "number" or qty < 1 then
            saved[recipeID] = nil
        else
            saved[recipeID] = math.min(math.floor(qty), 999)
        end
    end
    -- Anything added before the saved variables loaded is kept.
    for recipeID, qty in pairs(cart) do saved[recipeID] = qty end
    ns.char.cart = saved
    cart = saved
end
-- Session stays open while one pane is folded away.
local sessionOpen, foldBook, foldShop = false, false, false

local function ShoppingTab()
    return tab == "craftable" or tab == "almost" or tab == "all"
end

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

-- Bags and bank apart. With the bank closed the game may not count it, so what
-- the bank held when last open stands in.
local function BagsAndBank(itemID)
    local bags = Count(itemID, false)
    local bank = Count(itemID, true) - bags
    if bank <= 0 then bank = ns.char.bank[itemID] or 0 end
    return bags, bank
end

local function Have(itemID)
    local bags, bank = BagsAndBank(itemID)
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
    headerDefault[key] = openByDefault
    -- While searching everything found is shown.
    if search then return true end
    if toggled[key] ~= nil then return toggled[key] end
    if expandOverride ~= nil then return expandOverride end
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
    local open = IsOpen(key, headerDefault[key] ~= nil and headerDefault[key] or true)
    toggled[key] = not open
end

function ns.SetBookExpanded(open)
    wipe(toggled)
    expandOverride = open and true or false
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

function ns.ShopToggle(recipeID)
    if cart[recipeID] then
        cart[recipeID] = nil
    else
        cart[recipeID] = 1
    end
end

function ns.ShopSet(recipeID, qty)
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or not ns.recipes[recipeID] then
        cart[recipeID] = nil
    else
        cart[recipeID] = math.min(qty, 999)
    end
end

function ns.ShopClear()
    wipe(cart)
end

function ns.ShopList()
    local list = {}
    for recipeID, qty in pairs(cart) do
        if ns.recipes[recipeID] and type(qty) == "number" and qty > 0 then
            list[#list + 1] = recipeID
        end
    end
    table.sort(list, CompareRecipes)
    return list
end

-- Reagents to buy across the shopping list: need, have, and still short.
function ns.ShopTotals()
    local need = {}
    for recipeID, qty in pairs(cart) do
        local recipe = ns.recipes[recipeID]
        if recipe and type(qty) == "number" and qty > 0 then
            for itemID, per in pairs(recipe.reagents) do
                need[itemID] = (need[itemID] or 0) + per * qty
            end
        end
    end
    local list = {}
    for itemID, total in pairs(need) do
        local bags, bank = BagsAndBank(itemID)
        local have = bags + bank
        list[#list + 1] = {
            itemID = itemID, need = total, have = have, bags = bags, bank = bank,
            buy = math.max(0, total - have),
        }
    end
    table.sort(list, function(a, b)
        if a.buy ~= b.buy then return a.buy > b.buy end
        return a.itemID < b.itemID
    end)
    return list
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
                if ns.RecipeName then ns.RecipeName(recipeID) end
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
            local text = WithIcon(ns.RecipeName and ns.RecipeName(recipeID) or recipe.name, recipe.icon)
            if times[recipeID] > 0 then text = text .. "  x" .. times[recipeID] end
            if mode == "craftable" or mode == "almost" or mode == "all" then
                text = (cart[recipeID] and "|cff33ff99[+]|r " or "|cff666666[ ]|r ") .. text
            end
            local openRecipe = Header(lines, text, ns.DIFFICULTY_COLOR[recipe.diff] or ns.NO_DIFFICULTY_COLOR,
                "recipe:" .. recipeID, true, 1, recipe.out)
            if mode == "craftable" or mode == "almost" or mode == "all" then
                lines[#lines].select = recipeID
            end
            for _, itemID in ipairs(openRecipe and SortedKeys(recipe.reagents) or {}) do
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
        -- Adds or removes the recipe from the shopping list (Almost / All).
        row.cartBtn = CreateFrame("Button", nil, row)
        row.cartBtn:SetSize(24, 24)
        row.cartBtn:SetPoint("RIGHT", row.trashBtn, "LEFT", -2, 0)
        row.cartBtn.label = row.cartBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.cartBtn.label:SetPoint("CENTER", 0, 1)
        row.cartBtn:SetScript("OnClick", function(self)
            local id = self:GetParent().select
            if not id then return end
            ns.ShopToggle(id)
            Refresh()
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

local shopRows = {}

local function ShopRow(i)
    local row = shopRows[i]
    if not row then
        row = CreateFrame("Frame", nil, window.shopContent)
        row:SetHeight(SHOP_ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * SHOP_ROW)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * SHOP_ROW)
        row:EnableMouse(true)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.minus = CreateFrame("Button", nil, row)
        row.minus:SetSize(20, 20)
        row.minus:SetPoint("RIGHT", -42, 0)
        row.minus.label = row.minus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.minus.label:SetPoint("CENTER")
        row.minus.label:SetText("-")
        row.plus = CreateFrame("Button", nil, row)
        row.plus:SetSize(20, 20)
        row.plus:SetPoint("RIGHT", -2, 0)
        row.plus.label = row.plus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.plus.label:SetPoint("CENTER")
        row.plus.label:SetText("+")
        row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.qty:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
        row.qty:SetWidth(28)
        row.qty:SetJustifyH("CENTER")
        row.minus:SetScript("OnClick", function(self)
            local id = self:GetParent().recipeID
            if id then ns.ShopSet(id, (cart[id] or 1) - 1); Refresh() end
        end)
        row.plus:SetScript("OnClick", function(self)
            local id = self:GetParent().recipeID
            if id then ns.ShopSet(id, (cart[id] or 0) + 1); Refresh() end
        end)
        row:SetScript("OnEnter", function(self)
            if self.bags == nil then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then GameTooltip:SetItemByID(self.itemID) end
            GameTooltip:AddLine(L.BOOK_SHOP_HAVE_TIP:format(self.bags, self.bank), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        shopRows[i] = row
    end
    return row
end

-- The discreet "clear" button both panes use: small, dark gray with a thin
-- border, in the bottom right corner, lit on hover, with a longer
-- explanation in its tooltip.
local function ClearButton(parent, text, tip, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(18)
    button:SetPoint("BOTTOMRIGHT", -20, 15)
    button:SetBackdrop({
        bgFile = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
    })
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", 0, 0)
    local function Paint(hover)
        button.label:SetText((hover and "|cffff3030×|r " or "|cff909090×|r ") .. text)
        if hover then
            button.label:SetTextColor(1, 1, 1)
            button:SetBackdropColor(0.22, 0.22, 0.22, 0.95)
            button:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        else
            button.label:SetTextColor(0.7, 0.7, 0.7)
            button:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
            button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end
    end
    Paint(false)
    button:SetWidth((button.label:GetStringWidth() or 0) + 14)
    button:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    button:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    button:SetScript("OnEnter", function(self)
        Paint(true)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        Paint(false)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", onClick)
    return button
end

-- Slim edge tab; red matches Blizzard close-button / RED_FONT_COLOR.
local function FoldTab(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(14, 40)
    button:SetFrameLevel(parent:GetFrameLevel() + 30)
    button:SetBackdrop({
        bgFile = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local red = RED_FONT_COLOR or { r = 1, g = 0.1, b = 0.1 }
    button:SetBackdropColor(red.r * 0.55, red.g * 0.55, red.b * 0.55, 0.95)
    button:SetBackdropBorderColor(red.r * 0.35, red.g * 0.35, red.b * 0.35, 1)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER", 0, 1)
    button.label:SetTextColor(1, 0.95, 0.9)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(red.r * 0.75, red.g * 0.75, red.b * 0.75, 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(red.r * 0.55, red.g * 0.55, red.b * 0.55, 0.95)
        GameTooltip:Hide()
    end)
    button:Hide()
    return button
end

local function StyleFold(button, parent, point, relative, x, y, arrow, tip)
    if not button then return end
    button:SetParent(parent)
    button:SetFrameLevel(parent:GetFrameLevel() + 30)
    button:ClearAllPoints()
    button:SetPoint(point, parent, relative, x, y)
    button.label:SetText(arrow)
    button.tip = tip
    button:Show()
end

-- Only one close button: on the list when it is visible, otherwise on the book.
local function PlaceCloseX()
    local bookClose = window and window.close
    local shopClose = window and window.shop and window.shop.close
    if not (bookClose and shopClose) then return end
    if sessionOpen and ShoppingTab() and not foldShop then
        bookClose:Hide()
        shopClose:Show()
    else
        shopClose:Hide()
        bookClose:Show()
    end
end

local function RefreshShop()
    local shop = window and window.shop
    if not shop then return end
    local bookTab, shopTab = window.bookFold, window.shopFold

    if not (sessionOpen and ShoppingTab()) then
        -- Leaving the shopping tabs clears the fold layout; closing the window
        -- keeps foldBook/foldShop so the next open restores them.
        local restoreBook = sessionOpen and foldBook and window and not window:IsShown()
        if sessionOpen then foldBook, foldShop = false, false end
        shop:Hide()
        if bookTab then bookTab:Hide() end
        if shopTab then shopTab:Hide() end
        if restoreBook then window:Show() end
        PlaceCloseX()
        return
    end

    if foldBook then
        if window:IsShown() then window:Hide() end
    elseif not window:IsShown() then
        window:Show()
    end

    if foldShop then
        shop:Hide()
        if bookTab then bookTab:Hide() end
        -- Book alone: > on the right opens the list.
        StyleFold(shopTab, window, "LEFT", "RIGHT", -4, 0, ">", L.BOOK_SHOW_SHOP)
        PlaceCloseX()
        return
    end

    shop:ClearAllPoints()
    if foldBook then
        shop:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
        if shopTab then shopTab:Hide() end
        -- List alone: < on the left opens the book.
        StyleFold(bookTab, shop, "RIGHT", "LEFT", 4, 0, "<", L.BOOK_SHOW_BOOK)
    else
        shop:SetPoint("TOPLEFT", window, "TOPRIGHT", -4, 0)
        shop:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", -4, 0)
        -- Both open: > left of book hides book; < right of list hides list.
        StyleFold(bookTab, window, "RIGHT", "LEFT", 4, 0, ">", L.BOOK_HIDE_BOOK)
        StyleFold(shopTab, shop, "LEFT", "RIGHT", -4, 0, "<", L.BOOK_HIDE_SHOP)
    end
    shop:Show()
    PlaceCloseX()

    local list, totals, lines = ns.ShopList(), ns.ShopTotals(), {}
    if #list == 0 then
        lines[1] = { text = L.BOOK_SHOP_EMPTY, color = GRAY }
    else
        for _, recipeID in ipairs(list) do
            local recipe = ns.recipes[recipeID]
            lines[#lines + 1] = {
                text = WithIcon(ns.RecipeName and ns.RecipeName(recipeID) or recipe.name, recipe.icon),
                color = GOLD,
                recipeID = recipeID,
                qty = cart[recipeID],
            }
        end
        lines[#lines + 1] = { text = " ", color = GRAY }
        lines[#lines + 1] = { text = L.BOOK_SHOP_NEED, color = GOLD }
        for _, entry in ipairs(totals) do
            local name, icon = ns.ItemDisplay(entry.itemID)
            local color = entry.buy > 0 and MISSING_COLOR or HAVE_COLOR
            lines[#lines + 1] = {
                text = ("%s  %d  |cff999999(%s)|r"):format(
                    WithIcon(name, icon), entry.buy, L.BOOK_SHOP_HAVE:format(entry.bags, entry.bank)),
                color = color,
                itemID = entry.itemID,
                bags = entry.bags,
                bank = entry.bank,
            }
        end
    end
    for i, line in ipairs(lines) do
        local row = ShopRow(i)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 2, 0)
        row.label:SetText(line.text)
        row.label:SetTextColor(line.color[1], line.color[2], line.color[3])
        row.recipeID = line.recipeID
        row.itemID = line.itemID
        row.bags, row.bank = line.bags, line.bank
        if line.qty then
            row.qty:SetText(tostring(line.qty))
            row.qty:Show()
            row.minus:Show()
            row.plus:Show()
            row.label:SetPoint("RIGHT", row.minus, "LEFT", -4, 0)
        else
            row.qty:Hide()
            row.minus:Hide()
            row.plus:Hide()
            row.label:SetPoint("RIGHT", -2, 0)
        end
        row:Show()
    end
    for i = #lines + 1, #shopRows do
        shopRows[i]:Hide()
    end
    window.shopContent:SetHeight(math.max(1, #lines * SHOP_ROW))
end

-- Search at -74; profession icons under it; expand/collapse under the icons.
local SEARCH_Y, FILTER_Y, FILTER_SLOT, ACTION_H = -74, -100, 48, 24
local filters = {}

-- Secondary skills always last: First Aid, Fishing, Cooking (locale names).
local SECONDARY_RANK = {
    ["First Aid"] = 1, ["Primeiros Socorros"] = 1,
    ["Fishing"] = 2, ["Pesca"] = 2,
    ["Cooking"] = 3, ["Culinária"] = 3,
}
local PROF_ICONS = {
    Alchemy = [[Interface\Icons\Trade_Alchemy]],
    Alquimia = [[Interface\Icons\Trade_Alchemy]],
    Blacksmithing = [[Interface\Icons\Trade_BlackSmithing]],
    Ferraria = [[Interface\Icons\Trade_BlackSmithing]],
    Enchanting = [[Interface\Icons\Trade_Engraving]],
    Encantamento = [[Interface\Icons\Trade_Engraving]],
    Engineering = [[Interface\Icons\Trade_Engineering]],
    Engenharia = [[Interface\Icons\Trade_Engineering]],
    Herbalism = [[Interface\Icons\Trade_Herbalism]],
    Herborismo = [[Interface\Icons\Trade_Herbalism]],
    Leatherworking = [[Interface\Icons\Trade_LeatherWorking]],
    Couraria = [[Interface\Icons\Trade_LeatherWorking]],
    Mining = [[Interface\Icons\Trade_Mining]],
    ["Mineração"] = [[Interface\Icons\Trade_Mining]],
    Skinning = [[Interface\Icons\INV_Misc_Pelt_Wolf_01]],
    Esfolamento = [[Interface\Icons\INV_Misc_Pelt_Wolf_01]],
    Tailoring = [[Interface\Icons\Trade_Tailoring]],
    Alfaiataria = [[Interface\Icons\Trade_Tailoring]],
    Jewelcrafting = [[Interface\Icons\INV_Misc_Gem_01]],
    Joalheria = [[Interface\Icons\INV_Misc_Gem_01]],
    Inscription = [[Interface\Icons\INV_Inscription_Tradeskill01]],
    Escrivania = [[Interface\Icons\INV_Inscription_Tradeskill01]],
    Cooking = [[Interface\Icons\INV_Misc_Food_15]],
    ["Culinária"] = [[Interface\Icons\INV_Misc_Food_15]],
    Fishing = [[Interface\Icons\Trade_Fishing]],
    Pesca = [[Interface\Icons\Trade_Fishing]],
    ["First Aid"] = [[Interface\Icons\Spell_Holy_SealOfSacrifice]],
    ["Primeiros Socorros"] = [[Interface\Icons\Spell_Holy_SealOfSacrifice]],
}

local function LiveProfessionIcons()
    local byName = {}
    if not (GetProfessions and GetProfessionInfo) then return byName end
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if not ok then return byName end
    for _, index in ipairs({ a, b, c, d, e, f }) do
        if index then
            local name, icon = GetProfessionInfo(index)
            if type(name) == "string" and name ~= "" then
                byName[name] = icon or PROF_ICONS[name]
            end
        end
    end
    return byName
end

-- Primary slots first (character's 1st / 2nd), then First Aid, Fishing, Cooking.
local function OrderedProfessions()
    local have, primary, secondary = {}, {}, {}
    for _, name in ipairs(ns.Professions()) do
        have[name] = true
        if SECONDARY_RANK[name] then
            secondary[#secondary + 1] = name
        else
            primary[#primary + 1] = name
        end
    end
    local rank, icons = {}, LiveProfessionIcons()
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2 = pcall(GetProfessions)
        if ok then
            if p1 then
                local name = GetProfessionInfo(p1)
                if name then rank[name] = 1 end
            end
            if p2 then
                local name = GetProfessionInfo(p2)
                if name then rank[name] = 2 end
            end
        end
    end
    table.sort(primary, function(a, b)
        local ra, rb = rank[a] or 50, rank[b] or 50
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    table.sort(secondary, function(a, b)
        return (SECONDARY_RANK[a] or 99) < (SECONDARY_RANK[b] or 99)
    end)
    local list = {}
    local function push(name)
        if not (name and have[name]) then return end
        have[name] = nil
        list[#list + 1] = {
            name = name,
            icon = icons[name] or PROF_ICONS[name] or [[Interface\Icons\INV_Misc_QuestionMark]],
        }
    end
    for _, name in ipairs(primary) do push(name) end
    for _, name in ipairs(secondary) do push(name) end
    return list
end

local function Filter(name, icon)
    local check = filters[name]
    if not check then
        check = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        -- Kept for tests / accessibility; the icon is what the player sees.
        check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check.label:SetText(name)
        check.label:Hide()
        check.icon = check:CreateTexture(nil, "ARTWORK")
        check.icon:SetSize(18, 18)
        check.icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(name)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        check:SetScript("OnClick", function(self)
            ns.char.hiddenProfs[name] = not self:GetChecked() or nil
            Refresh()
        end)
        filters[name] = check
    end
    if check.icon and icon then check.icon:SetTexture(icon) end
    return check
end

local function LayoutFilters()
    local shown = tab ~= "beasts"
    local list = shown and OrderedProfessions() or {}
    for _, check in pairs(filters) do check:Hide() end
    local y = FILTER_Y
    if #list > 0 then
        for i, entry in ipairs(list) do
            local check = Filter(entry.name, entry.icon)
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", 22 + (i - 1) * FILTER_SLOT, y)
            check:SetChecked(not ns.char.hiddenProfs[entry.name])
            check:Show()
        end
        y = y - 28
    end
    if window.collapse and window.expand then
        window.collapse:ClearAllPoints()
        window.collapse:SetPoint("TOPLEFT", 22, y)
        window.expand:ClearAllPoints()
        window.expand:SetPoint("LEFT", window.collapse, "RIGHT", 4, 0)
        window.collapse:Show()
        window.expand:Show()
        y = y - ACTION_H - 4
    end
    window.scroll:SetPoint("TOPLEFT", 20, y)
end

function Refresh()
    if not window then return end
    if window:IsShown() then
        LayoutFilters()
        local lines = ns.BookLines(tab)
        for i, line in ipairs(lines) do
            local row = Row(i)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", line.indent * INDENT, 0)
            row.itemID = line.itemID
            row.toggle = line.toggle
            row.trash = line.trash
            row.select = line.select
            if line.trash then row.trashBtn:Show() else row.trashBtn:Hide() end
            if line.select then
                row.cartBtn:Show()
                row.cartBtn.label:SetText(cart[line.select] and "|cff33ff99+|r" or "|cff999999+|r")
                row.label:SetPoint("RIGHT", row.cartBtn, "LEFT", -4, 0)
            else
                row.cartBtn:Hide()
                row.label:SetPoint("RIGHT", line.trash and row.trashBtn or row, line.trash and "LEFT" or "RIGHT", -4, 0)
            end
            row.label:SetText(line.text)
            row.label:SetTextColor(line.color[1], line.color[2], line.color[3])
            row:Show()
        end
        for i = #lines + 1, #rows do
            rows[i]:Hide()
        end
        content:SetHeight(math.max(1, #lines * ROW_HEIGHT))
        for _, button in ipairs(window.tabs) do
            local active = button.mode == tab
            if button.underline then
                if active then button.underline:Show() else button.underline:Hide() end
            end
            if button.label then
                if active then button.label:SetTextColor(1, 0.82, 0) else button.label:SetTextColor(0.7, 0.7, 0.7) end
            end
        end
        if window.box then
            window.box:ClearAllPoints()
            window.box:SetPoint("TOPLEFT", 26, SEARCH_Y)
        end
        if tab == "beasts" then
            window.view:SetText(ns.db.beastView == "kind" and L.BOOK_BY_PLACE or L.BOOK_BY_KIND)
            window.view:Show()
            if window.box then window.box:SetPoint("RIGHT", window.view, "LEFT", -8, 0) end
            local hasLoot = next(ns.db.loot and ns.db.loot.sources or {}) ~= nil
            if hasLoot and not search then window.clearAll:Show() else window.clearAll:Hide() end
            window.scroll:SetPoint("BOTTOMRIGHT", -36, hasLoot and not search and 38 or 18)
        else
            window.view:Hide()
            if window.box then window.box:SetPoint("RIGHT", window, "RIGHT", -20, 0) end
            window.clearAll:Hide()
            window.scroll:SetPoint("BOTTOMRIGHT", -36, 18)
        end
    end
    RefreshShop()
    if ns.RefreshVendor then ns.Try(ns.RefreshVendor) end
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
    -- Drag scripts are wired after the shopping window exists, so both panes move together.
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
    frame.close = close

    -- Tab strip (not red panel buttons): label + gold underline when active.
    frame.tabs = {}
    local tabWidth = (WIDTH - 36) / #TABS
    for i, info in ipairs(TABS) do
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(tabWidth - 2, 26)
        button:SetPoint("TOPLEFT", 18 + (i - 1) * tabWidth, -40)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER", 0, 1)
        button.label:SetText(L[info[2]])
        button.text = L[info[2]]
        button.mode = info[1]
        button.underline = button:CreateTexture(nil, "OVERLAY")
        if button.underline then
            button.underline:SetHeight(2)
            button.underline:SetPoint("BOTTOMLEFT", 4, 1)
            button.underline:SetPoint("BOTTOMRIGHT", -4, 1)
            pcall(function() button.underline:SetColorTexture(1, 0.82, 0, 1) end)
            button.underline:Hide()
        end
        button:SetScript("OnClick", function(self)
            tab = self.mode
            Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            if self.mode ~= tab then self.label:SetTextColor(1, 1, 1) end
        end)
        button:SetScript("OnLeave", function(self)
            if self.mode ~= tab then self.label:SetTextColor(0.7, 0.7, 0.7) end
        end)
        frame.tabs[i] = button
    end

    -- Shopping assistant as its own window, docked to the book's right side.
    local shop = CreateFrame("Frame", "EasyRecipeShop", UIParent, "BackdropTemplate")
    shop:Hide()
    shop:SetSize(SHOP_WIDTH, HEIGHT)
    shop:SetFrameStrata("HIGH")
    shop:SetClampedToScreen(true)
    shop:EnableMouse(true)
    shop:SetMovable(true)
    shop:RegisterForDrag("LeftButton")
    shop:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    if UISpecialFrames then table.insert(UISpecialFrames, "EasyRecipeShop") end

    -- Drag either pane: with both open the book leads (list is anchored to it);
    -- with only the list open, dragging parks the book under it for the next unfold.
    local function DragStart()
        if foldBook and shop:IsShown() then
            shop:StartMoving()
        else
            frame:StartMoving()
        end
    end
    local function DragStop()
        frame:StopMovingOrSizing()
        shop:StopMovingOrSizing()
        if foldBook and shop:IsShown() then
            local left, top = shop:GetLeft(), shop:GetTop()
            if left and top then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                shop:ClearAllPoints()
                shop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            end
        end
    end
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)
    shop:SetScript("OnDragStart", DragStart)
    shop:SetScript("OnDragStop", DragStop)
    local shopTitle = shop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    shopTitle:SetPoint("TOP", 0, -18)
    shopTitle:SetText(L.BOOK_SHOP)
    local function CloseSession()
        -- Remember foldBook/foldShop for the next open; only the session ends.
        sessionOpen = false
        local keepBook, keepShop = foldBook, foldShop
        foldBook = false
        frame:Hide()
        shop:Hide()
        foldBook, foldShop = keepBook, keepShop
        if frame.bookFold then frame.bookFold:Hide() end
        if frame.shopFold then frame.shopFold:Hide() end
    end

    local shopClose = CreateFrame("Button", nil, shop, "UIPanelCloseButton")
    shopClose:SetPoint("TOPRIGHT", -6, -6)
    shopClose:SetScript("OnClick", CloseSession)
    shop.close = shopClose
    shopClose:Hide()
    ClearButton(shop, L.BOOK_SHOP_CLEAR, nil, function()
        if next(cart) == nil then return end
        Confirm("EASYRECIPE_SHOP_CLEAR", L.BOOK_SHOP_CLEAR_CONFIRM, ns.ShopClear)
    end)
    local shopScroll = CreateFrame("ScrollFrame", nil, shop, "UIPanelScrollFrameTemplate")
    shopScroll:SetPoint("TOPLEFT", 16, -48)
    shopScroll:SetPoint("BOTTOMRIGHT", -32, 38)
    local shopContent = CreateFrame("Frame", nil, shopScroll)
    shopContent:SetSize(SHOP_WIDTH - 56, 1)
    shopScroll:SetScrollChild(shopContent)
    frame.shop, frame.shopContent = shop, shopContent

    frame.bookFold = FoldTab(frame)
    frame.bookFold:SetScript("OnClick", function()
        foldBook = not foldBook
        Refresh()
    end)
    frame.shopFold = FoldTab(frame)
    frame.shopFold:SetScript("OnClick", function()
        foldShop = not foldShop
        Refresh()
    end)

    frame:SetScript("OnHide", function()
        if foldBook and sessionOpen then return end
        sessionOpen = false
        shop:Hide()
        if frame.bookFold then frame.bookFold:Hide() end
        if frame.shopFold then frame.shopFold:Hide() end
    end)
    shop:SetScript("OnHide", function()
        if foldShop then return end
        if foldBook then
            -- Esc closed the list while the book was folded: end session, keep folds.
            sessionOpen = false
            if frame.bookFold then frame.bookFold:Hide() end
            if frame.shopFold then frame.shopFold:Hide() end
            return
        end
        if sessionOpen and ShoppingTab() then
            foldShop = true
            StyleFold(frame.shopFold, frame, "LEFT", "RIGHT", -4, 0, ">", L.BOOK_SHOW_SHOP)
            if frame.bookFold then frame.bookFold:Hide() end
        end
    end)

    local collapse = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    collapse:SetSize(100, 22)
    collapse:SetText(L.BOOK_COLLAPSE_ALL)
    collapse:SetScript("OnClick", function()
        ns.SetBookExpanded(false)
        Refresh()
    end)
    frame.collapse = collapse

    local expand = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    expand:SetSize(100, 22)
    expand:SetText(L.BOOK_EXPAND_ALL)
    expand:SetScript("OnClick", function()
        ns.SetBookExpanded(true)
        Refresh()
    end)
    frame.expand = expand

    -- A plain input box: SearchBoxTemplate is Blizzard UI on some clients and
    -- can throw "only available to the Blizzard UI".
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", 26, SEARCH_Y)
    box:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    box:SetAutoFocus(false)
    box:SetTextInsets(8, 8, 0, 0)
    frame.box = box
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
    view:SetSize(100, 22)
    view:SetPoint("TOPRIGHT", -20, SEARCH_Y + 1)
    view:SetScript("OnClick", function()
        ns.SetBeastView(ns.db.beastView == "kind" and "place" or "kind")
        Refresh()
    end)
    frame.view = view

    local clearAll = ClearButton(frame, L.BOOK_FORGET_ALL_SHORT, L.BOOK_FORGET_ALL,
        function() ns.BookAction("forgetAll") end)
    clearAll:Hide()
    frame.clearAll = clearAll

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, FILTER_Y - 56)
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
    frame:HookScript("OnShow", Refresh)
    return frame
end

function ns.ToggleBook()
    -- Kept only once complete, so a failed build is not shown half made.
    window = window or Build()
    if sessionOpen then
        sessionOpen = false
        local keepBook, keepShop = foldBook, foldShop
        foldBook = false
        window:Hide()
        if window.shop then window.shop:Hide() end
        foldBook, foldShop = keepBook, keepShop
        if window.bookFold then window.bookFold:Hide() end
        if window.shopFold then window.shopFold:Hide() end
    else
        sessionOpen = true
        window:Show()
    end
end
