-- Automatic / Hotkey Gates - permission hook
--
-- Called on the SERVER for every gate trigger when sandbox option
-- "Enforce Permission Hook" is enabled. With the option off, everyone
-- may operate registered gates regardless of this file.
--
-- Default policy (tag = faction ACL):
--   - Empty / whitespace tag     -> public (anyone)
--   - Solo sandbox               -> always allow
--   - Admin / Moderator          -> always allow (bypass)
--   - Otherwise                  -> player's vanilla faction name must match
--                                  one of the comma-separated names in the tag
--                                  (each entry: trim + case-insensitive)
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

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normName(s)
    return string.lower(trim(s))
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

    local playerFactionName = nil
    pcall(function()
        if Faction and Faction.getPlayerFaction then
            local faction = Faction.getPlayerFaction(playerObj)
            if faction and faction.getName then
                playerFactionName = faction:getName()
            end
        end
    end)

    if not playerFactionName then
        return false
    end

    local playerNorm = normName(playerFactionName)
    for i = 1, #allowed do
        if playerNorm == normName(allowed[i]) then
            return true
        end
    end
    return false
end
