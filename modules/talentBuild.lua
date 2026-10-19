local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local Safe = ns.Safe
local UnitFrameOf = ns.UnitFrameOf
local Lookup = ns.Lookup
local buildTexts = ns.buildTexts
local GetBarFrames = ns.GetBarFrames
local TallLine = ns.TallLine
local Mirrored = ns.Mirrored
local EliteInRow = ns.EliteInRow
local ELITE_ROOM = ns.ELITE_ROOM
local BuildLineVisible = ns.BuildLineVisible
local ClassLabel = ns.ClassLabel
local ClassTextMode = ns.ClassTextMode

-- Talent build on the player, target and focus -------------------------------------
-- Points per talent tree ("2/8/0") in the square style's name area: on its own line above
-- the name with tall portraits (TallLine), else just left of the level. Your own build is
-- read directly (cached until your talents change); other players need an inspect
-- (server round trip, ~30 yd range, shared throttle), so results are cached per GUID for
-- the session and requests are spaced out. NPCs and players we can't inspect show
-- nothing rather than a guess.
local BUILD_UNITS = { "player", "target", "focus" }
local builds = {}         -- GUID -> "2/8/0"
local ownBuild            -- your build, cleared when your talents change
local inspectGUID         -- GUID of our pending inspect
local inspectAt = 0       -- GetTime() of our last NotifyInspect
local INSPECT_GAP = 1.5   -- seconds between our inspects
local INSPECT_TIMEOUT = 4 -- give up waiting for a reply after this long
local NO_REPLY_WAIT = 30  -- a player who didn't answer waits this long before we ask again
local noReply = {}        -- GUID -> GetTime() of an inspect that got no answer

-- Points per tree for a trait config, in the talent window's tree order. The game leaves
-- out trees with no points spent (Blizzard's own tree headers show "0" for those).
local function ReadBuild(configID)
    if not (configID and C_Traits and C_Traits.GetConfigInfo) then return end
    local info = C_Traits.GetConfigInfo(configID)
    local tree = info and info.treeIDs and info.treeIDs[1]
    local display = tree and C_Traits.GetGroupDisplayInfoByTreeID(tree)
    if not display or #display == 0 then return end
    local ids = {}
    for i, d in ipairs(display) do ids[i] = d.groupID end
    local spent = {}
    for _, g in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = g.currencyInfos and g.currencyInfos[1]
        local n = c and Safe(c.spent)
        if c and n == nil then return end -- secret: show nothing
        spent[g.traitNodeGroupID] = n or 0
    end
    local parts = {}
    for i, d in ipairs(display) do parts[i] = tostring(spent[d.groupID] or 0) end
    return table.concat(parts, "/")
end

local function OwnBuild()
    if not ownBuild and C_ClassTalents then -- not ready right after login: retried by the ticker
        ownBuild = ReadBuild(C_ClassTalents.GetActiveConfigID())
    end
    return ownBuild
end

-- Class name above the level (classText.lua, "level" with tall portraits): on the build line, on
-- the level's side. FontStrings per unit, created on first use.
local classTexts = {}
local function UpdateLevelClass(unit, label, hpPos, row, extra, level)
    local fs = classTexts[unit]
    if not label then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        local uf = UnitFrameOf(unit)
        if not uf then return end
        fs = uf:CreateFontString(nil, "OVERLAY")
        local font, size, flags = level:GetFont()
        if font then
            fs:SetFont(font, math.max((size or 10) - 2, 7), flags)
        elseif GameFontNormalSmall then
            fs:SetFontObject(GameFontNormalSmall)
        end
        fs:SetTextColor(1, 1, 1) -- the class color comes from the text's color code
        classTexts[unit] = fs
    end
    local mirror = Mirrored(unit)
    fs:ClearAllPoints()
    if mirror then -- level on the outer (left) edge
        fs:SetPoint("LEFT", hpPos, "TOPLEFT", 1, row + extra / 2)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("RIGHT", hpPos, "TOPRIGHT", -1, row + extra / 2)
        fs:SetJustifyH("RIGHT")
    end
    fs:SetText(label)
    fs:Show()
end

-- One inspect at a time (target and focus share it): a second request would replace the
-- pending one and its answer would be ignored. No answer in time: that player waits
-- NO_REPLY_WAIT so the other frame gets a turn.
local function RequestInspect(guid, unit)
    if not (NotifyInspect and guid) or InCombatLockdown() then return end
    local now = GetTime()
    if inspectGUID then
        if now - inspectAt < INSPECT_TIMEOUT then return end -- still waiting for its reply
        noReply[inspectGUID], inspectGUID = now, nil
    end
    if noReply[guid] and now - noReply[guid] < NO_REPLY_WAIT then return end
    if now - inspectAt < INSPECT_GAP then return end -- the ticker asks again shortly
    if CanInspect and not CanInspect(unit) then return end -- out of range, enemy, ...
    if InspectFrame and InspectFrame:IsShown() then return end -- Blizzard's inspect owns it
    inspectGUID, inspectAt = guid, GetTime()
    NotifyInspect(unit)
end

local function BuildFor(unit)
    if unit == "player" or Safe(UnitIsUnit(unit, "player")) then return OwnBuild() end
    if not Safe(UnitIsPlayer(unit)) then return end
    local guid = Safe(UnitGUID(unit))
    if guid and not builds[guid] then RequestInspect(guid, unit) end
    return guid and builds[guid]
end

local function CreateBuildText(unit, level)
    local uf = UnitFrameOf(unit)
    if not uf then return end
    local fs = uf:CreateFontString(nil, "OVERLAY")
    local font, size, flags = level:GetFont()
    if font then
        fs:SetFont(font, math.max((size or 10) - 2, 7), flags)
    elseif GameFontNormalSmall then
        fs:SetFontObject(GameFontNormalSmall)
    end
    fs:SetTextColor(0.7, 0.7, 0.7) -- muted: the name is the main information
    fs:Hide()
    return fs
end

local function UpdateBuildFor(unit)
    local name, level, bbfName = Lookup(unit, "texts")
    local lineOn = BuildLineVisible(unit)
    local hpPos = lineOn and GetBarFrames(unit)
    local row, extra = hpPos and hpPos.bapRow or 0, TallLine(unit)
    local above = row > 0 and extra > 0
    -- The class (classText.lua): in the build text for "build", and for "level" when there's no
    -- line above the level; on its own above the level otherwise.
    local mode = lineOn and ClassTextMode(unit)
    local label = (mode == "build" or mode == "level") and ClassLabel(unit) or nil
    local inBuild = label and (mode == "build" or not above)
    if level then UpdateLevelClass(unit, hpPos and not inBuild and label or nil, hpPos, row, extra, level) end
    local build = lineOn and db.showBuild and BuildFor(unit) or nil
    local text = build
    if inBuild then text = build and (label .. " " .. build) or label end
    local fs = buildTexts[unit]
    if not text and not (fs and fs:IsShown()) then return end -- nothing to show or hide
    if not level then return end
    if text and not fs then
        fs = CreateBuildText(unit, level)
        buildTexts[unit] = fs
    end
    if not fs then return end
    -- Own line above the name (left-aligned with it), or next to the level.
    hpPos = hpPos or GetBarFrames(unit)
    local mirror = Mirrored(unit)
    local eliteRow = EliteInRow(unit) and true or false -- the inline build steps past the elite icon
    if fs.bapText == text and fs.bapInline == not above and fs.bapRow == row and fs.bapExtra == extra
        and fs.bapMirror == mirror and fs.bapEliteRow == eliteRow then return end
    fs.bapText, fs.bapInline, fs.bapRow, fs.bapExtra, fs.bapMirror = text, not above, row, extra, mirror
    fs.bapEliteRow = eliteRow
    fs:ClearAllPoints()
    if above and mirror then -- above the name, on the portrait side
        fs:SetPoint("RIGHT", hpPos, "TOPRIGHT", -1, row + extra / 2)
        fs:SetJustifyH("RIGHT")
    elseif above then
        fs:SetPoint("LEFT", hpPos, "TOPLEFT", 1, row + extra / 2)
        fs:SetJustifyH("LEFT")
    elseif mirror then -- between the level (outer edge) and the name, past the elite icon
        fs:SetPoint("LEFT", level, "RIGHT", 4 + (eliteRow and ELITE_ROOM or 0), 0)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("RIGHT", level, "LEFT", -4 - (eliteRow and ELITE_ROOM or 0), 0)
        fs:SetJustifyH("RIGHT")
    end
    fs:SetText(text or "")
    fs:SetShown(text ~= nil)
    -- The name's room depends on an inline build text: re-fit the pinned names.
    for _, pinned in ipairs({ name, bbfName }) do
        if pinned and pinned.bapLayout and pinned.bapApply then pinned.bapApply(pinned) end
    end
end

local function UpdateBuild()
    for _, unit in ipairs(BUILD_UNITS) do UpdateBuildFor(unit) end
end

local function OnTalentsChanged()
    ownBuild = nil
    UpdateBuild()
end

local function OnInspectReady(guid)
    if not guid or guid ~= inspectGUID then return end -- someone else's inspect
    inspectGUID = nil
    local build = Constants and Constants.TraitConsts and ReadBuild(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
    if build then builds[guid] = build end
    UpdateBuild()
end

ns.UpdateBuild = UpdateBuild
ns.OnTalentsChanged = OnTalentsChanged
ns.OnInspectReady = OnInspectReady
