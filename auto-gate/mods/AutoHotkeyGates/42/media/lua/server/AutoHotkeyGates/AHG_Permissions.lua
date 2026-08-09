-- Automatic / Hotkey Gates - permission hook
--
-- Called on the SERVER for every gate trigger when sandbox option
-- "Enforce Permission Hook" is enabled. With the option off, everyone
-- may operate registered gates regardless of this file.
--
-- Permission Provider (sandbox enum):
--   1 = VanillaFactionTag — player's vanilla MP faction name must match
--       one of the comma-separated names in the gate tag
--   2 = PLZ_Membership — player's PLZ_Factions membership must match a
--       tag name AND their role must have USE_VEHICLE_GARAGE
--
-- Shared policy for both providers:
--   - Empty / whitespace tag     -> public (anyone)
--   - Solo sandbox               -> always allow
--   - Admin / Moderator          -> always allow (bypass)
--
-- Examples:
--   ""                    -> public
--   "Police"              -> Police only
--   "Police, Military"    -> Police or Military
--   "Police,Military,EMS" -> any of those three
--
-- Staff set the tag when registering (or via Change Tag...). To change access,
-- use Change Tag... or unregister and re-register.

if isClient() then return end

require "AutoHotkeyGates/AHG_Shared"

AHG = AHG or {}
AHG.Permissions = AHG.Permissions or {}

local STAFF_BYPASS_RANK = 4 -- moderator and above (admin = 5)
local PROVIDER_VANILLA = 1
local PROVIDER_PLZ = 2

local plzFactionMod = nil
local plzLoadAttempted = false
local plzMissingWarned = false

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normName(s)
    return string.lower(trim(s))
end

local function tagMatches(playerFactionName, allowed)
    local playerNorm = normName(playerFactionName)
    for i = 1, #allowed do
        if playerNorm == normName(allowed[i]) then
            return true
        end
    end
    return false
end

-- Split "Police, Military, EMS" into a list of non-empty trimmed names.
function AHG.Permissions.parseFactionTags(tag)
    local list = {}
    local raw = tostring(tag or "")
    for part in string.gmatch(raw .. ",", "([^,]*),") do
        local name = trim(part)
        if name ~= "" then
            table.insert(list, name)
        end
    end
    return list
end

local function getVanillaFactionName(playerObj)
    local playerFactionName = nil
    pcall(function()
        if Faction and Faction.getPlayerFaction then
            local faction = Faction.getPlayerFaction(playerObj)
            if faction and faction.getName then
                playerFactionName = faction:getName()
            end
        end
    end)
    return playerFactionName
end

local function loadPlzFactionMod()
    if plzLoadAttempted then
        return plzFactionMod
    end
    plzLoadAttempted = true
    local ok, mod = pcall(require, "PLZ_Factions/Faction")
    if ok and mod and mod.getPlayerFaction then
        plzFactionMod = mod
    else
        plzFactionMod = nil
    end
    return plzFactionMod
end

local function warnPlzMissingOnce()
    if plzMissingWarned then return end
    plzMissingWarned = true
    print("[AHG] WARNING: Permission Provider is PLZ_Membership but PLZ_Factions is not available; tagged gate triggers are denied.")
end

-- Returns factionDef, role or nil, nil.
local function getPlzFactionAndRole(playerObj)
    local PlzFaction = loadPlzFactionMod()
    if not PlzFaction then
        warnPlzMissingOnce()
        return nil, nil
    end

    local username = nil
    pcall(function()
        username = playerObj:getUsername()
    end)
    if not username or username == "" then
        return nil, nil
    end

    local result = nil
    local ok = pcall(function()
        result = PlzFaction.getPlayerFaction(username)
    end)
    if not ok or not result or not result.factionDef then
        return nil, nil
    end

    local role = nil
    pcall(function()
        role = result.factionDef:getMemberRole(username)
    end)
    return result.factionDef, role
end

local function canOperateVanilla(playerObj, allowed)
    local playerFactionName = getVanillaFactionName(playerObj)
    if not playerFactionName then
        return false
    end
    return tagMatches(playerFactionName, allowed)
end

local function canOperatePlz(playerObj, allowed)
    local factionDef, role = getPlzFactionAndRole(playerObj)
    if not factionDef or not role then
        return false
    end

    local PlzFaction = plzFactionMod
    local garagePerm = PlzFaction and PlzFaction.Permissions and PlzFaction.Permissions.USE_VEHICLE_GARAGE
    if not garagePerm then
        return false
    end

    local hasGarage = false
    pcall(function()
        hasGarage = role:hasPermission(garagePerm) and true or false
    end)
    if not hasGarage then
        return false
    end

    local factionName = factionDef.name
    if not factionName then
        return false
    end
    return tagMatches(factionName, allowed)
end

function AHG.Permissions.canOperate(playerObj, gateRecord)
    if not playerObj or not gateRecord then return false end

    local allowed = AHG.Permissions.parseFactionTags(gateRecord.tag)
    if #allowed == 0 then
        return true -- public
    end

    -- Solo worlds have no MP factions / access levels.
    if not isClient() and not isServer() then
        return true
    end

    -- Admin / Moderator bypass faction checks.
    if AHG.accessRank(AHG.getPlayerAccessLevel(playerObj)) >= STAFF_BYPASS_RANK then
        return true
    end

    local provider = tonumber(AHG.opt("PermissionProvider")) or PROVIDER_VANILLA
    if provider == PROVIDER_PLZ then
        return canOperatePlz(playerObj, allowed)
    end
    return canOperateVanilla(playerObj, allowed)
end
