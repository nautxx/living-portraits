-- luacheck config for Living Portraits (WoW uses Lua 5.1)
std = "lua51"
max_line_length = false
exclude_files = { ".git/" }

-- Globals this addon defines
globals = {
    "LivingPortraitsDB",
    "SLASH_LIVINGPORTRAITS1", "SLASH_LIVINGPORTRAITS2", "SLASH_LIVINGPORTRAITS3",
    "SlashCmdList",
    "StaticPopupDialogs",
    "BetterBlizzFramesDB", -- BBF's saved settings: /lp bbfsetup writes a few switches
}

-- WoW API / frames we read
read_globals = {
    -- frames
    "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "UIParent", "PlayerName", "PlayerLevelText", "EditModeManagerFrame",
    -- API
    "CreateFrame", "C_Timer", "hooksecurefunc", "PixelUtil",
    "UnitExists", "UnitGUID", "UnitIsVisible", "UnitIsConnected",
    "issecretvalue", "InCombatLockdown",
    "Settings", "SettingsPanel", "CreateSettingsListSectionHeaderInitializer", "CreateSettingsButtonInitializer",
    "MinimalSliderWithSteppersMixin", "StaticPopup_Show", "ReloadUI", "RELOADUI", "LATER",
    "C_AddOns", "DISABLE", "IGNORE_DIALOG",
    "C_Traits", "C_ClassTalents", "Constants", "NotifyInspect", "CanInspect", "InspectFrame", "GetTime",
    "UnitIsPlayer", "UnitIsUnit", "GameFontNormalSmall",
    -- WoW Lua extensions
    "wipe", "unpack",
    -- BetterBlizzFrames (optional)
    "BBF",
}

-- The test harness stubs the WoW API by defining globals on purpose.
files["tests/"] = { ignore = { "1", "21" } }
