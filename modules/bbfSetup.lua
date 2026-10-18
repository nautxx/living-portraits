local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PREFIX = ns.PREFIX

-- BBF setup -----------------------------------------------------------------
-- The square style needs BBF's No Portrait + Pixel Border mode on every frame. We write
-- those switches into BBF's saved settings (never its files) and keep a backup for Undo.
-- BBF reads them when it loads, so a UI reload applies them. The rest of BBF stays as is.
local BBF_SETUP = {
    noPortraitModes = true, noPortraitPixelBorder = true,
    noPortraitPartyOnly = false, -- otherwise only the party frames lose their portraits
    noPortraitSkipPlayer = false, noPortraitSkipTarget = false, noPortraitSkipFocus = false,
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

local function BBFSetupOn()
    local bdb = BetterBlizzFramesDB
    if type(bdb) ~= "table" then return false end
    for k, v in pairs(BBF_SETUP) do
        if (bdb[k] or false) ~= v then return false end
    end
    return true
end

-- Both return a line for chat.
local function ApplyBBFSetup()
    local bdb = BetterBlizzFramesDB
    if not BBF or type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    if BBFSetupOn() then return "BBF's Pixel Border mode is already on." end
    if not db.bbfBackup then -- keep the first backup: it holds the settings from before us
        local backup = {}
        for k in pairs(BBF_SETUP) do
            if bdb[k] == nil then backup[k] = NO_VALUE else backup[k] = bdb[k] end
        end
        db.bbfBackup = backup
    end
    for k, v in pairs(BBF_SETUP) do bdb[k] = v end
    ShowReloadPopup()
    return "Turned on BBF's No Portrait + Pixel Border mode. Reload the UI to apply it."
end

local function UndoBBFSetup()
    local bdb, backup = BetterBlizzFramesDB, db.bbfBackup
    if not backup then return "Nothing to undo." end
    if type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    for k, v in pairs(backup) do
        if v == NO_VALUE then bdb[k] = nil else bdb[k] = v end
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
