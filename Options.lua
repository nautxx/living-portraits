local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local defaults = ns.defaults
local GROUPS = ns.GROUPS
local PREFIX = ns.PREFIX
local QueueRefreshAll = ns.QueueRefreshAll
local UpdateBarTexts = ns.UpdateBarTexts
local ApplyBBFSetup = ns.ApplyBBFSetup
local UndoBBFSetup = ns.UndoBBFSetup
local PROFILES = ns.PROFILES
local AskLoadProfile = ns.AskLoadProfile
local ShowExport = ns.ShowExport
local ShowImport = ns.ShowImport

-- Settings panel ------------------------------------------------------------
-- Options > AddOns > Living Portraits. Proxy settings read and write db directly,
-- so the panel and /lp always agree (slash changes call NotifyOptions).
local optionVars = {} -- registered setting variables, refreshed by NotifyOptions
local optionsCategory

local function NotifyOptions()
    if not (Settings and Settings.NotifyUpdate) then return end
    for _, var in ipairs(optionVars) do Settings.NotifyUpdate(var) end
end

local function FormatDecimal(v) return ("%.2f"):format(v) end
local function FormatWhole(v) return ("%d"):format(math.floor(v + 0.5)) end
local function FormatPercent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

-- get/set for db[k1][k2]..., and the matching default.
local function Path(keys)
    local last = keys[#keys]
    local function Parent()
        local t = db
        for i = 1, #keys - 1 do t = t[keys[i]] end
        return t
    end
    local d = defaults
    for _, k in ipairs(keys) do d = d[k] end
    return function() return Parent()[last] end, function(v) Parent()[last] = v end, d
end

-- The built-in profiles as one row of buttons, each with the profile's name, starting where row
-- labels start (no label: more buttons get added over time). Blizzard's button row with an empty
-- name already does that for its one button (SettingsButtonControlMixin:Init anchors it to the
-- label spot), so the first profile is that button; the others are buttons of ours to its right.
-- List rows are recycled for other button rows (Export, Undo...), so ours go on in InitFrame and
-- come off in Resetter, and the stock button gets its width back. (Blizzard's plain
-- SettingsListElementTemplate can't be used: it never runs its OnLoad, Init errored in game.)
-- One row for now: wrap it when there are more profiles than fit.
local PROFILE_BUTTON_GAP, PROFILE_BUTTON_WIDTH, STOCK_BUTTON_WIDTH = 6, 120, 200
-- A profile's name, in its class's color when it has one (like BBF's streamer profiles).
local function ProfileTitle(p)
    local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if not c then return p.name end
    if type(c.colorStr) == "string" then return "|c" .. c.colorStr .. p.name .. "|r" end -- Blizzard's exact hex
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5), p.name)
end
local PROFILE_NOTE = " Replaces your Living Portraits and BetterBlizzFrames settings; Undo puts them back. Reloads the UI."
local function ProfileButtonsInitializer(say)
    local first = PROFILES[1]
    local initializer = CreateSettingsButtonInitializer("", ProfileTitle(first), function() say(AskLoadProfile(first.name)) end,
        first.name .. ": " .. first.desc .. PROFILE_NOTE, true)
    local baseInit, baseReset = initializer.InitFrame, initializer.Resetter
    function initializer:InitFrame(frame)
        baseInit(self, frame)
        if not frame.Button then return end
        frame.Button:SetWidth(PROFILE_BUTTON_WIDTH)
        frame.lpProfileButtons = frame.lpProfileButtons or {}
        local prev = frame.Button
        for i = 2, #PROFILES do
            local b = frame.lpProfileButtons[i]
            if not b then
                b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                b:SetScript("OnEnter", function(btn)
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:SetText(ProfileTitle(btn.lpProfile), 1, 1, 1)
                    GameTooltip:AddLine(btn.lpProfile.desc .. PROFILE_NOTE, nil, nil, nil, true)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:SetScript("OnClick", function(btn) say(AskLoadProfile(btn.lpProfile.name)) end)
                frame.lpProfileButtons[i] = b
            end
            b.lpProfile = PROFILES[i]
            b:SetText(ProfileTitle(PROFILES[i]))
            b:SetSize(PROFILE_BUTTON_WIDTH, frame.Button:GetHeight())
            b:ClearAllPoints()
            b:SetPoint("LEFT", prev, "RIGHT", PROFILE_BUTTON_GAP, 0)
            b:Show()
            prev = b
        end
    end
    function initializer:Resetter(frame)
        for _, b in pairs(frame.lpProfileButtons or {}) do b:Hide() end
        if frame.Button then frame.Button:SetWidth(STOCK_BUTTON_WIDTH) end
        baseReset(self, frame)
    end
    return initializer
end

local function BuildOptions()
    if optionsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory and SettingsPanel) then return end
    local category = -- Styled like BBF's own entry (plain first word, cyan second). The list sorts on the raw
    -- name, so it must not start with a color code.
    Settings.RegisterVerticalLayoutCategory("Living|cff00c0ffPortraits|r")
    local layout = SettingsPanel:GetLayout(category)

    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
    local function Register(var, name, default, get, set)
        var = "LivingPortraits_" .. var
        optionVars[#optionVars + 1] = var
        return Settings.RegisterProxySetting(category, var, nil, name, default, get, function(v)
            set(v)
            QueueRefreshAll()
        end)
    end
    local function Check(keys, name, tooltip)
        local get, set, default = Path(keys)
        Settings.CreateCheckbox(category, Register(table.concat(keys, "_"), name, default, get, set), tooltip)
    end
    -- step >= 1 means whole numbers.
    local function Slider(keys, name, tooltip, lo, hi, step, format)
        local get, set, default = Path(keys)
        local whole = step >= 1
        local setting = Register(table.concat(keys, "_"), name, default, get, function(v)
            set(whole and math.floor(v + 0.5) or v)
        end)
        local options = Settings.CreateSliderOptions(lo, hi, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            format or (whole and FormatWhole or FormatDecimal))
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    Header("General")
    Check({ "enabled" }, "Enable", "Show living portraits.")
    Check({ "hideSurname" }, "Hide Surnames", "Show only first names on the player, target, focus, target-of-target and party frames.")
    local styleGet, styleSet, styleDefault = Path({ "style" })
    Settings.CreateDropdown(category, Register("style", "Style", styleDefault, styleGet, styleSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("square", "Box")
        c:Add("circle", "Circle")
        return c:GetData()
    end, "Box: the portrait in a bordered box beside the bars (needs BBF's Pixel Border mode: Profiles page). Circle: inside the round portrait. Frames where BBF still shows portraits always use the circle.")
    for _, g in ipairs({ { "player", "Player Portrait", "player frame" },
                         { "target", "Target Portrait", "target frame" },
                         { "focus", "Focus Portrait", "focus frame" },
                         { "tot", "Target of Target Portrait", "target-of-target and focus-target frames" },
                         { "party", "Party Portraits", "party frames" } }) do
        local list = GROUPS[g[1]]
        Settings.CreateCheckbox(category, Register("unit_" .. g[1], g[2], true,
            function() return db.units[list[1]] end,
            function(v) for _, unit in ipairs(list) do db.units[unit] = v end end),
            "Living portrait on the " .. g[3] .. ".")
    end

    Header("Camera")
    Slider({ "zoom" }, "Zoom", "1 = head and shoulders; lower shows more of the body. Both styles.", 0, 1, 0.05)

    Header("Bar text")
    local barGet, barSet, barDefault = Path({ "barText" })
    Settings.CreateDropdown(category, Register("barText", "Bar Text", barDefault, barGet, function(v)
        barSet(v)
        UpdateBarTexts(true)
    end), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("default", "Default (Blizzard / BBF)")
        c:Add("max", "Current (max), left")
        c:Add("percent", "Current (percent), left")
        return c:GetData()
    end, "Health and mana text on the player, target, focus and party bars. The left-aligned formats are always shown, whatever the Status Text setting.")
    local styleTextGet, styleTextSet, styleTextDefault = Path({ "barTextStyle" })
    Settings.CreateDropdown(category, Register("barTextStyle", "Bar Text Style", styleTextDefault, styleTextGet, function(v)
        styleTextSet(v)
        UpdateBarTexts()
    end), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("outline_shadow", "Outline + shadow")
        c:Add("outline", "Outline")
        c:Add("shadow", "Shadow")
        c:Add("thick", "Thick outline")
        c:Add("thick_shadow", "Thick outline + shadow")
        return c:GetData()
    end, "Outline and shadow of the left-aligned bar text. The font itself follows BetterBlizzFrames' unit frame number font.")

    Header("Target bars")
    Check({ "growBars" }, "Grow on new target", "Health and mana grow from empty when you pick a new target or focus.")
    Slider({ "growTime" }, "Grow time", "Seconds the grow takes.", 0.1, 2, 0.05,
        function(v) return ("%.2fs"):format(v) end)

    -- Profiles and each style's settings on their own pages under the main entry (falls back to
    -- sections on the main page if the client has no subcategories). Each style's camera distance
    -- lives there: square boxes share one distance, circle portraits use large/small.
    local main = category
    local function Page(name)
        if Settings.RegisterVerticalLayoutSubcategory then
            category, layout = Settings.RegisterVerticalLayoutSubcategory(main, name)
            layout = layout or SettingsPanel:GetLayout(category)
        else
            Header(name)
        end
    end

    -- Profiles page (first under the main entry): a whole look (ours + BBF's) in one click, the
    -- BBF setup, and the Undo they share. A dialog confirms or shows the string; a returned line
    -- means it couldn't (no BBF, no dialogs).
    local function Say(msg) if msg then print(PREFIX .. msg) end end
    Page("Profiles")
    Header("Profiles")
    layout:AddInitializer(ProfileButtonsInitializer(Say))

    Header("Import / Export")
    layout:AddInitializer(CreateSettingsButtonInitializer("Export profile", "Export",
        function() Say(ShowExport()) end,
        "A text string with your Living Portraits and BetterBlizzFrames settings, to share or to copy to another PC.", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Import profile", "Import",
        function() Say(ShowImport()) end,
        "Paste a profile string. Replaces your Living Portraits and BetterBlizzFrames settings; Undo puts them back. Reloads the UI.", true))

    Header("BetterBlizzFrames")
    layout:AddInitializer(CreateSettingsButtonInitializer("Pixel Border mode", "Turn on",
        function() print(PREFIX .. ApplyBBFSetup()) end,
        "Turns on BBF's No Portrait + Pixel Border mode on every frame (and Classic Frames off), which the box style needs, and keeps the rest of your BBF settings. For a whole look, load a profile above. Reloads the UI.", true))

    Header("Undo")
    layout:AddInitializer(CreateSettingsButtonInitializer("Undo setup / profile", "Undo",
        function() print(PREFIX .. UndoBBFSetup()) end,
        "Puts back the Living Portraits and BBF settings you had before loading or importing a profile, or turning on Pixel Border mode here. Reloads the UI.", true))

    Page("Box Style")
    Header("Camera")
    Slider({ "sizes", "square", "cam" }, "Distance", "All box portraits. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Slider({ "squareBg" }, "Background", "Dark background behind the model.", 0, 1, 0.05, FormatPercent)

    Header("Size and layout")
    local TALL_TIP = "The portrait grows into a taller rectangle. Player, target and focus: with a line above the name for the talent build (off: square, build next to the level)."
    Check({ "tallPortraits", "player" }, "Tall portraits: player", TALL_TIP)
    Check({ "tallPortraits", "target" }, "Tall portraits: target & focus", TALL_TIP)
    Check({ "tallPortraits", "party" }, "Tall portraits: party", TALL_TIP)
    Slider({ "stackExtra", "large" }, "Extra height: large frames", "Player, target and focus. Makes the health + mana stack taller; the box grows with it.", 0, 30, 1)
    Slider({ "stackExtra", "small" }, "Extra height: small frames", "Target of target and party. Makes the health + mana stack taller; the box grows with it.", 0, 30, 1)
    Slider({ "nameRow", "large" }, "Name row: large frames", "Height of the name + level row inside the box (0 = off).", 0, 24, 1)
    Slider({ "nameRow", "tot" }, "Name row: target of target", "Height of the name row inside the box (0 = off).", 0, 24, 1)
    Slider({ "nameRow", "party" }, "Name row: party", "Height of the name row inside the box (0 = off).", 0, 24, 1)
    Slider({ "hpShare" }, "Health share", "Health bar's share of the stack; mana gets the rest.", 0.4, 0.85, 0.01, FormatPercent)
    Slider({ "squareGap" }, "Gap to bars", "Space between the box and the bars (1 = borders share one line).", 0, 20, 1)
    Slider({ "barSpacing" }, "Bar spacing", "Space between health and mana (0 = borders share one line).", 0, 10, 1)
    Check({ "alignMana" }, "Align mana bar", "Line the mana bar up with the health bar next to the box.")

    Header("Borders")
    local colorGet, colorSet, colorDefault = Path({ "borderColor" })
    Settings.CreateColorSwatch(category, Register("borderColor", "Border Color", colorDefault, colorGet, colorSet),
        "Color of the 1px lines around the portrait box and the health and mana bars.")
    local sizeGet, sizeSet, sizeDefault = Path({ "borderSize" })
    Settings.CreateDropdown(category, Register("borderSize", "Border Thickness", sizeDefault, sizeGet, sizeSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add(1, "Thin")
        c:Add(2, "Medium")
        c:Add(3, "Heavy")
        return c:GetData()
    end, "Thickness of the lines around the portrait box and the bars.")
    Slider({ "borderAlpha" }, "Border Opacity", "Opacity of the 1px lines around the portrait box and the bars.", 0, 1, 0.05, FormatPercent)

    Header("Text")
    Check({ "showBuild" }, "Show Talent Build", "Points per talent tree (like 2/8/0) on the player, target and focus frames. Other players need to be within inspect range (about 30 yards); NPCs show nothing.")
    Check({ "mirrorTarget" }, "Mirror Target Text", "Target and focus: name and talent build next to the portrait, level on the outer edge, mirroring the player frame.")
    local restGet, restSet, restDefault = Path({ "restIcon" })
    Settings.CreateDropdown(category, Register("restIcon", "Resting Icon", restDefault, restGet, restSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("name", "After the name")
        c:Add("corner", "Portrait top-right corner")
        return c:GetData()
    end, "Where the player's resting Zzz goes: just after your name, or over the top-right corner of the portrait box.")

    Header("Elite and rare")
    Check({ "eliteBorder" }, "Elite Border", "Target and focus: the portrait and bar borders turn gold for elites and bosses, silver for rares. The elite icon uses these colors either way.")
    for _, c in ipairs({ { "eliteColor", "Elite Border Color", "Border color for elite and boss targets." },
                         { "rareColor", "Rare Border Color", "Border color for rare and rare elite targets." } }) do
        local get, set, default = Path({ c[1] })
        Settings.CreateColorSwatch(category, Register(c[1], c[2], default, get, set), c[3])
    end
    local eliteGet, eliteSet, eliteDefault = Path({ "eliteIcon" })
    Settings.CreateDropdown(category, Register("eliteIcon", "Elite Icon", eliteDefault, eliteGet, eliteSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("top", "Portrait top corner")
        c:Add("bottom", "Portrait bottom corner")
        c:Add("center", "Portrait bottom center")
        c:Add("level", "Next to level")
        c:Add("hidden", "Hidden")
        return c:GetData()
    end, "Target and focus: where the small elite/rare icon goes. The corners are on the portrait's outer side.")

    Header("Class resource")
    local resGet, resSet, resDefault = Path({ "resource" })
    Settings.CreateDropdown(category, Register("resource", "Class Resource", resDefault, resGet, resSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("pixel", "Pixel border")
        c:Add("bbf", "BetterBlizzFrames")
        c:Add("none", "None")
        return c:GetData()
    end, "Player frame: rogue and druid combo points (BBF's \"Move Combo Points under PlayerFrame\"), warlock soul shards, mage arcane charges and paladin holy charges. Both go under the mana bar. Pixel border: circles (gems for shards) using the border color and thickness above and BBF's \"hide when empty\" and \"only show filled\" settings. BetterBlizzFrames: BBF's own combo point art (warlock, mage and paladin have no bar of their own here, so nothing shows). None: hidden.")
    local alignGet, alignSet, alignDefault = Path({ "resourceAlign" })
    Settings.CreateDropdown(category, Register("resourceAlign", "Alignment", alignDefault, alignGet, alignSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("left", "Left")
        c:Add("center", "Center")
        c:Add("right", "Right")
        return c:GetData()
    end, "Line the class resource up with the left edge, the middle or the right edge of the mana bar.")
    Slider({ "resourceRadius" }, "Size", "Radius of the circles, inside the border. With BetterBlizzFrames, its points are scaled to the same width (instead of its Class Resource Scale).", 2, 16, 1)
    for _, c in ipairs({ { "combo", "Rogue / Druid: Combo Points" }, { "shards", "Warlock: Soul Shards" },
                         { "arcane", "Mage: Arcane Charges" }, { "holy", "Paladin: Holy Charges" } }) do
        local get, set, default = Path({ "resourceColors", c[1] })
        Settings.CreateColorSwatch(category, Register("resourceColors_" .. c[1], c[2], default, get, set),
            "Color of a filled circle. Empty ones are dark.")
    end

    Page("Circle Style")
    Header("Camera")
    Slider({ "sizes", "large", "cam" }, "Distance: large frames", "Player, target and focus. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Slider({ "sizes", "small", "cam" }, "Distance: small frames", "Target of target and party. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Header("Portrait")
    Slider({ "circleBg" }, "Background", "Dark background inside the ring (0 = clear).", 0, 1, 0.05, FormatPercent)
    Check({ "vignette" }, "Round edge", "The circle edge that hides the model's square corners.")
    Slider({ "sizes", "large", "inset" }, "Model size: large frames", "Model size relative to the portrait.", 0.3, 1.2, 0.01)
    Slider({ "sizes", "small", "inset" }, "Model size: small frames", "Model size relative to the portrait.", 0.3, 1.2, 0.01)

    category, layout = main, SettingsPanel:GetLayout(main)
    Settings.RegisterAddOnCategory(category)
    optionsCategory = category
end

local function OpenOptions()
    if optionsCategory and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return true
    end
end

ns.BuildOptions = BuildOptions
ns.OpenOptions = OpenOptions
ns.NotifyOptions = NotifyOptions
