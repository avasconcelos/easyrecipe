local _, ns = ...
local L = ns.L

-- A panel docked to the vendor's window listing what this vendor sells that
-- is on the shopping list. Shown only when the vendor sells any of it.

local WIDTH, ROW, TOP, BOTTOM = 360, 20, 44, 18
local MAX_ROWS = 18

local CoinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString

local panel, merchantOpen
local rows = {}

local function Number(value)
    if value == nil or (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then return nil end
    return value
end

-- itemID -> { index, price, stack } for everything this vendor sells.
local function VendorItems()
    local items = {}
    local count = Number(GetMerchantNumItems and GetMerchantNumItems()) or 0
    for index = 1, count do
        local itemID = Number(GetMerchantItemID and GetMerchantItemID(index))
        if itemID and not items[itemID] then
            local price, stack
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = C_MerchantFrame.GetItemInfo(index)
                if type(info) == "table" then price, stack = Number(info.price), Number(info.stackCount) end
            elseif GetMerchantItemInfo then
                local _, _, p, s = GetMerchantItemInfo(index)
                price, stack = Number(p), Number(s)
            end
            items[itemID] = { index = index, price = price, stack = stack }
        end
    end
    return items
end

local function Row(i)
    local row = rows[i]
    if not row then
        row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW)
        row:SetPoint("TOPLEFT", 18, -TOP - (i - 1) * ROW)
        row:SetPoint("TOPRIGHT", -18, -TOP - (i - 1) * ROW)
        row:EnableMouse(true)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.right:SetPoint("RIGHT", 0, 0)
        row.right:SetJustifyH("RIGHT")
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            if self.bags then
                GameTooltip:AddLine(L.BOOK_SHOP_HAVE_TIP:format(self.bags, self.bank), 1, 0.82, 0)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end
    return row
end

local function Build()
    panel = CreateFrame("Frame", "EasyRecipeVendor", UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetWidth(WIDTH)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -20)
    title:SetText(L.VENDOR_TITLE)
end

local function Hide()
    if panel then panel:Hide() end
end

function ns.RefreshVendor()
    if not merchantOpen or not ns.ShopTotals then return Hide() end
    local merchant = MerchantFrame
    if not (merchant and merchant:IsShown()) then return Hide() end

    local sold = VendorItems()
    local lines = {}
    for _, entry in ipairs(ns.ShopTotals()) do
        local item = sold[entry.itemID]
        if item then
            lines[#lines + 1] = { entry = entry, item = item }
        end
    end
    if #lines == 0 then return Hide() end

    if not panel then Build() end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", merchant, "TOPRIGHT", 2, 0)

    local shown = math.min(#lines, MAX_ROWS)
    for i = 1, shown do
        local entry, item = lines[i].entry, lines[i].item
        local row = Row(i)
        local name, icon = ns.ItemDisplay(entry.itemID)
        row.label:SetText((icon and ("|T" .. icon .. ":0|t ") or "") .. (name or ("item:" .. entry.itemID)))
        -- Red: still to buy; green: bags and bank already hold enough.
        if entry.buy > 0 then row.label:SetTextColor(1, 0.3, 0.3) else row.label:SetTextColor(0.25, 1, 0.25) end
        -- What bags and bank hold together, and what is still to buy; the
        -- tooltip splits bags from bank.
        local right = L.VENDOR_COUNTS:format(entry.have, entry.buy)
        if item.price and item.price > 0 and CoinText then
            -- Vendors sell some items in stacks; the price shown is per item.
            local each = item.price / math.max(1, item.stack or 1)
            right = right .. "  |cffbbbbbb" .. CoinText(math.ceil(each)) .. "|r"
        end
        row.right:SetText(right)
        row.itemID, row.bags, row.bank = entry.itemID, entry.bags, entry.bank
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    panel:SetHeight(TOP + shown * ROW + BOTTOM)
    panel:Show()
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        ns.Try(ns.RefreshVendor)
    end)
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        return Hide()
    elseif not merchantOpen then
        return
    end
    Queue()
end)
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
