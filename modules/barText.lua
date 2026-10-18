local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local Lookup = ns.Lookup
local HP_TEXT_KEYS = ns.HP_TEXT_KEYS
local MANA_TEXT_KEYS = ns.MANA_TEXT_KEYS

-- Bar text ------------------------------------------------------------------
-- Our own left-aligned "current (max)" / "current (percent)" text on health and mana bars,
-- always shown (whatever the Status Text setting or mouseover). Blizzard's bars call
-- UpdateTextStringWithValues on every value change; our post-hook writes our text and hides
-- Blizzard's/BBF's text regions on that bar (they re-show them each update, before us).
-- Values can be secret (instances, PvP): they only go to BreakUpLargeNumbers and
-- SetFormattedText (both take secrets from addon code), never compared or used in math;
-- percent comes from UnitHealthPercent/UnitPowerPercent with Blizzard's 0-100 curve.
local BAR_TEXT_MODES = { default = true, max = true, percent = true }
-- Text style -> font outline flag, drop shadow. The font face and size follow BBF.
local BAR_TEXT_STYLES = {
    outline_shadow = { "OUTLINE", true }, outline = { "OUTLINE", false }, shadow = { "", true },
    thick = { "THICKOUTLINE", false }, thick_shadow = { "THICKOUTLINE", true },
}
local BAR_TEXT_UNITS = { "player", "target", "focus", "party1", "party2", "party3", "party4" }

local function BarTextOn(unit)
    return db and db.enabled and db.units[unit] and db.barText ~= "default" and BAR_TEXT_MODES[db.barText]
end

-- Blizzard's/BBF's text regions on a bar (center, left, right, dead...), on the bar or its parent.
local function EachBlizzardText(bar, keys, fn)
    for _, holder in ipairs({ bar, bar:GetParent() }) do
        for _, key in ipairs(keys) do
            local t = holder and holder[key]
            if type(t) == "table" and t.Hide and t ~= bar.bapText then fn(t) end
        end
    end
end

-- Full numbers with thousands separators ("1,300", not "1.3K"), as Jason asked.
-- BreakUpLargeNumbers is a C function that accepts secret values from addon code.
local function NumberText(v)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(v) end
    return v
end

local function SetBarText(unit, bar, isHealth, value, valueMax)
    local keys = isHealth and HP_TEXT_KEYS or MANA_TEXT_KEYS
    local fs = bar.bapText
    if not BarTextOn(unit) then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        local ref
        EachBlizzardText(bar, keys, function(t) ref = ref or (t.GetFont and t) end)
        -- Own holder frame, a few levels above the bar. Copying the Blizzard text's parent put
        -- ours under the bars on the target (that parent is TargetFrame itself, below its
        -- bars; BBF only gives the player a text frame above them).
        local holder = CreateFrame("Frame", nil, bar)
        holder:SetAllPoints(bar)
        bar.bapTextHolder = holder
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(TextStatusBarText or GameFontHighlightSmall) -- until the ref's font is copied
        -- Centered on the visible bar: BBF's bordered frame, not the fill (1px taller and
        -- offset), same reference CenterBarTexts uses for Blizzard's texts.
        fs:SetPoint("LEFT", bar.BBFPositionFrame or bar, "LEFT", 4, 0)
        fs:SetJustifyH("LEFT")
        bar.bapText, bar.bapTextRef = fs, ref
    end
    -- Follow Blizzard's/BBF's number font face, size and color live (BBF: "Change unit frame
    -- number font"), so changing it there changes ours too; only re-set when it differs.
    -- Outline and shadow are ours (db.barTextStyle): BBF's thin outline alone got lost on light
    -- bars (white priest health).
    local ref = bar.bapTextRef
    if ref then
        local font, size = ref:GetFont()
        local style = BAR_TEXT_STYLES[db.barTextStyle] and db.barTextStyle or "outline_shadow"
        if font and (font ~= fs.bapFont or size ~= fs.bapSize or style ~= fs.bapStyle) then
            local look = BAR_TEXT_STYLES[style]
            fs:SetFont(font, size, look[1])
            fs:SetShadowColor(0, 0, 0, look[2] and 1 or 0)
            fs:SetShadowOffset(look[2] and 1 or 0, look[2] and -1 or 0)
            fs.bapFont, fs.bapSize, fs.bapStyle = font, size, style
        end
        fs:SetTextColor(ref:GetTextColor())
    end
    local holder = bar.bapTextHolder
    local level = bar:GetFrameLevel() + 5 -- above the fill and BBF's border/background frames
    if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end
    local cur = NumberText(value)
    if db.barText == "percent" then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        local pct
        if isHealth and UnitHealthPercent then pct = UnitHealthPercent(unit, true, curve)
        elseif not isHealth and UnitPowerPercent then pct = UnitPowerPercent(unit, nil, false, curve) end
        if pct then fs:SetFormattedText("%s (%.0f%%)", cur, pct) else fs:SetFormattedText("%s", cur) end
    else
        fs:SetFormattedText("%s (%s)", cur, NumberText(valueMax))
    end
    fs:Show()
    EachBlizzardText(bar, keys, function(t) t:Hide() end)
end

-- Hook each bar once; then (re)draw from the bar's current values, so a setting change shows
-- right away. Turning it off hides ours; Blizzard's text comes back on its next update, and
-- toggling the statusText CVar (as BBF does) makes Blizzard redraw it now.
local function UpdateBarTexts(fromSetting)
    if not db then return end
    for _, unit in ipairs(BAR_TEXT_UNITS) do
        local hpBar, manaBar = Lookup(unit, "bars")
        for _, info in ipairs({ { hpBar, true }, { manaBar, false } }) do
            local bar, isHealth = info[1], info[2]
            if bar and bar.UpdateTextStringWithValues then
                if not bar.bapTextHook and BarTextOn(unit) then
                    bar.bapTextHook = true
                    hooksecurefunc(bar, "UpdateTextStringWithValues", function(self, _, value, _, valueMax)
                        SetBarText(unit, self, isHealth, value, valueMax)
                    end)
                end
                if bar.bapTextHook then
                    local _, valueMax = bar:GetMinMaxValues()
                    SetBarText(unit, bar, isHealth, bar:GetValue(), valueMax)
                end
            end
        end
    end
    if fromSetting and db.barText == "default" and C_CVar and C_CVar.GetCVar("statusText") == "1" then
        C_CVar.SetCVar("statusText", "0")
        C_CVar.SetCVar("statusText", "1")
    end
end

ns.UpdateBarTexts = UpdateBarTexts
ns.BAR_TEXT_MODES = BAR_TEXT_MODES
ns.BAR_TEXT_STYLES = BAR_TEXT_STYLES
