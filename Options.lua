local _, ns = ...
local L = ns.L

-- Setting, color of its label and the label's text, hardest first.
local DIFFICULTIES = {
    { "showOptimal", "ffff8040", "OPT_OPTIMAL" },
    { "showMedium", "ffffff00", "OPT_MEDIUM" },
    { "showEasy", "ff40bf40", "OPT_EASY" },
    { "showTrivial", "ff808080", "OPT_TRIVIAL" },
}

local category, layout
-- Profession name -> true once the panel has a checkbox for it.
local professionListed = {}

local function AddHeader(text)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

-- A checkbox for a boolean of the account's settings.
local function AddCheckbox(key, name, tooltip)
    local setting = Settings.RegisterAddOnSetting(category, "EasyRecipe_" .. key, key, ns.db,
        Settings.VarType.Boolean, name, ns.DEFAULTS[key])
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- A checkbox for a value kept somewhere else, read and written through functions.
local function AddProxyCheckbox(variable, name, tooltip, get, set)
    local setting = Settings.RegisterProxySetting(category, "EasyRecipe_" .. variable,
        Settings.VarType.Boolean, name, true, get, set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(key, name, tooltip, lowest, highest)
    local setting = Settings.RegisterAddOnSetting(category, "EasyRecipe_" .. key, key, ns.db,
        Settings.VarType.Number, name, ns.DEFAULTS[key])
    local options = Settings.CreateSliderOptions(lowest, highest, 1)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(value) return ("%d"):format(value) end)
    end
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function AddProfessionCheckbox(name)
    local hidden = ns.char.hiddenProfs
    AddProxyCheckbox("profession_" .. name, name, L.OPT_PROFESSION_TIP,
        function() return not hidden[name] end,
        function(value) hidden[name] = not value or nil end)
end

-- A profession can be recorded after the panel was built, so its checkbox is
-- added whenever the recipes change.
function ns.AddProfessionOptions()
    if not category then return end
    for _, name in ipairs(ns.Professions()) do
        if not professionListed[name] then
            if next(professionListed) == nil then ns.Try(AddHeader, L.OPT_PROFESSIONS) end
            professionListed[name] = true
            ns.Try(AddProfessionCheckbox, name)
        end
    end
end

function ns.SetupOptions()
    if category then return end
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
    category, layout = Settings.RegisterVerticalLayoutCategory("EasyRecipe")

    -- Each piece on its own, so one API difference leaves the rest of the panel.
    local Try = ns.Try
    Try(AddHeader, L.OPT_GENERAL)
    Try(AddCheckbox, "enabled", L.OPT_ENABLED, L.OPT_ENABLED_TIP)
    Try(AddProxyCheckbox, "minimap", L.OPT_MINIMAP, L.OPT_MINIMAP_TIP,
        function() return not ns.db.minimap.hide end,
        function(value) ns.SetMinimapShown(value) end)
    Try(AddCheckbox, "showUnlearned", L.OPT_UNLEARNED, L.OPT_UNLEARNED_TIP)
    Try(AddSlider, "maxLines", L.OPT_MAX, L.OPT_MAX_TIP:format(ns.HARD_CAP), 1, ns.HARD_CAP)

    Try(AddHeader, L.OPT_DIFFICULTY)
    for _, difficulty in ipairs(DIFFICULTIES) do
        local key, color, label = difficulty[1], difficulty[2], difficulty[3]
        Try(AddCheckbox, key, "|c" .. color .. L[label] .. "|r", L.OPT_DIFFICULTY_TIP)
    end

    Try(AddHeader, L.OPT_LEVEL)
    Try(AddSlider, "minLevel", L.OPT_MIN_LEVEL, L.OPT_LEVEL_TIP, 0, ns.LEVEL_CAP)
    Try(AddSlider, "maxLevel", L.OPT_MAX_LEVEL, L.OPT_LEVEL_TIP, 0, ns.LEVEL_CAP)

    ns.AddProfessionOptions()
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if not (category and Settings.OpenToCategory) then
        ns.Print(L.NO_OPTIONS)
    elseif InCombatLockdown() then
        -- The game's options panel is protected while fighting.
        ns.Print(L.OPTIONS_COMBAT)
    elseif not pcall(Settings.OpenToCategory, category.GetID and category:GetID() or category.ID) then
        ns.Print(L.NO_OPTIONS)
    end
end
