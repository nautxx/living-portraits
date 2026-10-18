local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PREFIX = ns.PREFIX

-- BBF setup -----------------------------------------------------------------
-- One click sets BBF up the way Living Portraits is designed and tested (Jason's own BBF
-- settings): the No Portrait + Pixel Border mode the box style needs, plus the unit frame look
-- around it. We write these into BBF's saved settings (never its files) and keep a backup for
-- Undo. BBF reads them when it loads, so a UI reload applies them. Everything else in BBF
-- (auras, cast bars, action bars, chat, minimap, dark mode, raid frames) stays as it is.
-- The fonts and textures named here all ship with BBF (its LibSharedMedia and media folder).
local BBF_SETUP = {
    -- Mode: no portraits, pixel borders, on every frame (BBF.HasNoPortrait checks these).
    noPortraitModes = true, noPortraitPixelBorder = true,
    noPortraitPartyOnly = false, -- otherwise only the party frames lose their portraits
    noPortraitSkipPlayer = false, noPortraitSkipTarget = false, noPortraitSkipFocus = false,
    -- Fonts: names/levels, bar numbers, party.
    changeUnitFrameFont = true, unitFrameFont = "2002", unitFrameFontSize = 8, unitFrameFontOutline = "",
    unitFrameFontColor = false, unitFrameFontColorLvl = true, unitFrameFontColorRGB = { 0.953, 1, 0.969, 1 },
    changeUnitFrameValueFont = true, unitFrameValueFont = "Arial Narrow", unitFrameValueFontSize = 7,
    unitFrameValueFontOutline = "OUTLINE", unitFrameValueFontColor = true,
    changePartyFrameFont = true, partyFrameFont = "2002",
    -- Bar textures and the background behind them.
    changeUnitFrameHealthbarTexture = true, unitFrameHealthbarTexture = "Solid",
    changeUnitFrameManabarTexture = true, unitFrameManabarTexture = "Blizzard Retail Bar Crop 2",
    changeUnitFrameManaBarTextureKeepFancy = true, addUnitFrameBgTexture = true,
    -- Class colors on health bars and target names.
    classColorFrames = true, classColorTargetNames = true,
    -- Combo points under the player frame (our class resource moves and restyles that bar).
    foreverComboPoints = true, instantComboPoints = true, enableLegacyComboPoints = false,
    -- Target-of-target and focus-target placement that fits the taller box layout.
    targetToTScale = 0.97, targetToTXPos = -1, targetToTYPos = 17,
    focusToTScale = 0.97, focusToTXPos = -1, focusToTYPos = 17,
    -- Clutter that would sit on or around the portrait box and name row.
    hideTargetReputationColor = true, hideFocusReputationColor = true, hideCombatGlow = true,
    hideHitIndicator = true, hidePetHitIndicator = true, hidePvpIcon = true, hidePrestigeBadge = true,
    hideGroupIndicator = true, hidePlayerLeaderIcon = true, hideTargetLeaderIcon = true,
    hideFocusLeaderIcon = true, hidePlayerGuideIcon = true,
}
local NO_VALUE = "<nil>" -- backup marker: BBF had never saved this key

local function ShowReloadPopup()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.LIVING_PORTRAITS_RELOAD = StaticPopupDialogs.LIVING_PORTRAITS_RELOAD or {
        text = "Living Portraits changed your BetterBlizzFrames settings. Reload the UI to apply them?",
        button1 = RELOADUI or "Reload UI",
        button2 = LATER or "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("LIVING_PORTRAITS_RELOAD")
end

-- Values can be tables (colors): compare them field by field, and never hand BBF our table.
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = x end
    return t
end

local function BBFSetupOn()
    local bdb = BetterBlizzFramesDB
    if type(bdb) ~= "table" then return false end
    for k, v in pairs(BBF_SETUP) do
        local cur = bdb[k]
        if cur == nil and v == false then cur = false end
        if not Same(cur, v) then return false end
    end
    return true
end

-- Both return a line for chat.
local function ApplyBBFSetup()
    local bdb = BetterBlizzFramesDB
    if not BBF or type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    if BBFSetupOn() then return "BetterBlizzFrames is already set up." end
    -- Keep the first backup (it holds the settings from before us), adding keys a newer
    -- preset touches that an older one didn't.
    local backup = db.bbfBackup or {}
    for k in pairs(BBF_SETUP) do
        if backup[k] == nil then
            if bdb[k] == nil then backup[k] = NO_VALUE else backup[k] = Copy(bdb[k]) end
        end
    end
    db.bbfBackup = backup
    for k, v in pairs(BBF_SETUP) do bdb[k] = Copy(v) end
    ShowReloadPopup()
    return "Set up BetterBlizzFrames (Pixel Border mode, fonts, bar textures, class colors, combo points, "
        .. "target-of-target, less clutter). Reload the UI to apply it."
end

local function UndoBBFSetup()
    local bdb, backup = BetterBlizzFramesDB, db.bbfBackup
    if not backup then return "Nothing to undo." end
    if type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    for k, v in pairs(backup) do
        if v == NO_VALUE then bdb[k] = nil else bdb[k] = Copy(v) end
    end
    db.bbfBackup = nil
    ShowReloadPopup()
    return "Put back your previous BBF settings. Reload the UI to apply them."
end

-- Old install ---------------------------------------------------------------
-- Until v0.2.1 this addon was "BBF_AnimatedPortraits". If that folder is still installed
-- and enabled, both addons draw models and lay out the bars on the same frames. Offer to
-- disable it (Blizzard's own pattern: DisableAddOn, then reload), once per session.
local OLD_ADDON = "BBF_AnimatedPortraits"
local oldAddonWarned = false

local function CheckOldAddon()
    local api = C_AddOns
    if oldAddonWarned or not (api and api.IsAddOnLoaded and api.IsAddOnLoaded(OLD_ADDON)) then return end
    oldAddonWarned = true
    print(PREFIX .. "replaces BBF Animated Portraits, which is still enabled. Disable it, then delete the "
        .. OLD_ADDON .. " folder from your AddOns.")
    if not (StaticPopupDialogs and StaticPopup_Show and api.DisableAddOn) then return end
    StaticPopupDialogs.LIVING_PORTRAITS_OLD_ADDON = StaticPopupDialogs.LIVING_PORTRAITS_OLD_ADDON or {
        text = "LivingPortraits is the new name of BBF Animated Portraits, but the old version is still enabled. "
            .. "Running both breaks your unit frames.\n\nDisable the old version and reload?",
        button1 = DISABLE or "Disable",
        button2 = IGNORE_DIALOG or "Ignore",
        OnAccept = function()
            api.DisableAddOn(OLD_ADDON)
            ReloadUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("LIVING_PORTRAITS_OLD_ADDON")
end

ns.ApplyBBFSetup = ApplyBBFSetup
ns.UndoBBFSetup = UndoBBFSetup
ns.CheckOldAddon = CheckOldAddon
