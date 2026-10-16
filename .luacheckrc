-- luacheck config for BBF Animated Portraits (WoW uses Lua 5.1)
std = "lua51"
max_line_length = false
exclude_files = { ".git/" }

-- Globals this addon defines
globals = {
    "BBFAnimatedPortraitsDB",
    "SLASH_BBFANIMPORTRAITS1",
    "SlashCmdList",
    "StaticPopupDialogs",
    "BetterBlizzFramesDB", -- BBF's saved settings: /bap bbfsetup writes a few switches
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
    -- WoW Lua extensions
    "wipe", "unpack",
    -- BetterBlizzFrames (optional)
    "BBF",
}

-- The test harness stubs the WoW API by defining globals on purpose.
files["tests/"] = { ignore = { "1", "21" } }
