local _, ns = ...
local L = ns.L

local WIDTH, MARGIN = 440, 26
local TEXT_TOP, TEXT_BOTTOM = 52, 58

local frame

-- Either button counts as read; closing the game with the window still up
-- brings it back at the next login.
local function Dismiss()
    ns.db.introShown = true
    frame:Hide()
end

local function AddButton(window, text, point, x, onClick)
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetSize(170, 24)
    button:SetPoint(point, window, point, x, 20)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
end

-- A window of its own, not one of the game's help bubbles: UI addons such as
-- EllesmereUI can hide those.
local function Build()
    local window = CreateFrame("Frame", "EasyRecipeIntro", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetPoint("CENTER", 0, 80)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -24)
    title:SetText(L.INTRO_TITLE)

    local text = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", MARGIN, -TEXT_TOP)
    text:SetWidth(WIDTH - MARGIN * 2)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetText(L.INTRO_TEXT)
    -- The text is longer in some languages, so the window takes its height.
    window:SetSize(WIDTH, TEXT_TOP + text:GetStringHeight() + TEXT_BOTTOM)

    AddButton(window, L.INTRO_OPTIONS, "BOTTOMLEFT", MARGIN, function()
        Dismiss()
        ns.OpenOptions()
    end)
    AddButton(window, L.INTRO_OK, "BOTTOMRIGHT", -MARGIN, Dismiss)
    return window
end

function ns.ShowIntro()
    -- Kept only once complete, so a failed build is not shown half made.
    frame = frame or Build()
    frame:Show()
end
