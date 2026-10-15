-- luacheck config for BBF Animated Portraits (WoW uses Lua 5.1)
std = "lua51"
max_line_length = false
exclude_files = { ".git/" }

-- Globals this addon defines
globals = {
    "BBFAnimatedPortraitsDB",
    "SLASH_BBFANIMPORTRAITS1",
    "SlashCmdList",
}

-- WoW API / frames we read
read_globals = {
    -- frames
    "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame",
    -- API
    "CreateFrame", "C_Timer",
    "UnitExists", "UnitGUID", "UnitIsVisible", "UnitIsConnected",
    "issecretvalue",
    -- WoW Lua extensions
    "strsplit", "wipe",
    -- BetterBlizzFrames (optional)
    "BBF",
}

-- The test harness stubs the WoW API by defining globals on purpose.
files["tests/"] = { ignore = { "1", "21" } }
