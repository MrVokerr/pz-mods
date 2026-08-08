-- Automatic / Hotkey Gates - client core
-- Finds nearby registered gates, sends trigger intents, shows feedback.

require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_ClientSystem"

AHG.Client = AHG.Client or {}

-- ---------------------------------------------------------------------------
-- Feedback
-- ---------------------------------------------------------------------------

function AHG.Client.showNotify(playerObj, text)
    if not AHG.opt("ShowHaloMessages") then return end
    playerObj = playerObj or getSpecificPlayer(0)
    if not playerObj or not text then return end
    text = tostring(text)

    -- B42 HaloTextHelper API (see vanilla ISReadABook / ISVehicleMenu):
    --   addText(player, text)
    --   addGoodText(player, text)
    --   addBadText(player, text)
    -- The old addText(player, text, ColorRGB) overload was removed and still
    -- increments the error counter even when called inside pcall.
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(playerObj, text)
        return
    end
    if HaloTextHelper and HaloTextHelper.addGoodText then
        HaloTextHelper.addGoodText(playerObj, text)
        return
    end
    if playerObj.setHaloNote then
        playerObj:setHaloNote(text)
        return
    end
    playerObj:Say(text)
end

function AHG.Client.showNotifyKey(playerObj, key, arg1, arg2)
    local text
    if arg2 ~= nil then
        text = AHG.text(key, arg1, arg2)
    elseif arg1 ~= nil then
        text = AHG.text(key, arg1)
    else
        text = AHG.text(key)
    end
    AHG.Client.showNotify(playerObj, text)
end

local function OnServerCommand(module, command, args)
    if module ~= AHG.Module then return end
    if command == "Notify" and args and args.key then
        local playerObj = getPlayer and getPlayer() or getSpecificPlayer(0)
        AHG.Client.showNotifyKey(playerObj, args.key, args.arg1, args.arg2)
    end
end

Events.OnServerCommand.Add(OnServerCommand)

-- ---------------------------------------------------------------------------
-- Finding registered gates near the player
-- ---------------------------------------------------------------------------

local function considerCandidate(best, playerObj, x, y, z, gateId, tag, rangeSq)
    if not gateId or gateId == "" then return best end
    local d2 = AHG.distSq(playerObj:getX(), playerObj:getY(), playerObj:getZ(), x, y, z)
    if d2 > rangeSq then return best end
    if best and best.d2 <= d2 then return best end
    return { x = x, y = y, z = z, gateId = gateId, tag = tag or "", d2 = d2 }
end

-- Primary source: synced GlobalObjects (cheap). Fallback: ModData marker scan
-- around the player (covers SP and freshly-streamed areas).
function AHG.Client.findNearestGate(playerObj, range)
    if not playerObj then return nil end
    range = tonumber(range) or 15
    local rangeSq = range * range
    local best = nil

    local sys = (CAHGSystem and CAHGSystem.instance) or (SAHGSystem and SAHGSystem.instance)
    if sys then
        for i = 1, sys:getLuaObjectCount() do
            local rec = sys:getLuaObjectByIndex(i)
            if rec then
                best = considerCandidate(best, playerObj, rec.x, rec.y, rec.z, rec.gateId, rec.tag, rangeSq)
            end
        end
    end

    if not best then
        local px = math.floor(playerObj:getX())
        local py = math.floor(playerObj:getY())
        local pz = math.floor(playerObj:getZ())
        local cell = getCell()
        if not cell then return nil end
        for dx = -range, range do
            for dy = -range, range do
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq then
                    for j = 0, sq:getObjects():size() - 1 do
                        local obj = sq:getObjects():get(j)
                        if AHG.isRegisteredObject(obj) then
                            best = considerCandidate(best, playerObj,
                                obj:getX(), obj:getY(), obj:getZ(),
                                AHG.getGateIdFromObject(obj), AHG.getTagFromObject(obj), rangeSq)
                        end
                    end
                end
            end
        end
    end

    return best
end

-- ---------------------------------------------------------------------------
-- Triggering
-- ---------------------------------------------------------------------------

-- source: "hotkey" | "radial" | "context"
function AHG.Client.operateNearest(playerNum, source)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:isDead() then return end

    if AHG.opt("OperateFromVehicleOnly") and not playerObj:getVehicle() and source ~= "context" then
        AHG.Client.showNotifyKey(playerObj, "IGUI_AHG_VehicleOnly")
        return
    end

    local range = tonumber(AHG.opt("TriggerRange")) or 15
    local gate = AHG.Client.findNearestGate(playerObj, range)
    if not gate then
        AHG.Client.showNotifyKey(playerObj, "IGUI_AHG_NoGateInRange")
        return
    end

    AHG.sendCommand(playerObj, "Trigger", {
        gateId = gate.gateId,
        x = gate.x, y = gate.y, z = gate.z,
        source = source or "hotkey",
    })
end

-- Trigger a specific gate object (context menu path).
function AHG.Client.operateGateObject(gateObj, playerObj)
    if not gateObj or not playerObj then return end
    AHG.sendCommand(playerObj, "Trigger", {
        gateId = AHG.getGateIdFromObject(gateObj),
        x = gateObj:getX(), y = gateObj:getY(), z = gateObj:getZ(),
        index = AHG.getObjectIndex(gateObj),
        source = "context",
    })
end
