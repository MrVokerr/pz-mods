-- Automatic / Hotkey Gates - vehicle radial menu integration
-- Adds an "Operate Gate" slice to the in-vehicle radial menu whenever a
-- registered gate is within trigger range.

require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_Client"

local sliceTexture = nil
local sliceTextureResolved = false

local function getSliceTexture()
    if sliceTextureResolved then return sliceTexture end
    sliceTextureResolved = true
    -- Paths used by vanilla ISVehicleMenu in B42.
    local candidates = {
        "media/ui/vehicles/vehicle_doorLocked.png",
        "media/ui/vehicles/vehicle_ignitionON.png",
        "media/ui/vehicles/vehicle_changeseats.png",
    }
    for i = 1, #candidates do
        local ok, tex = pcall(function() return getTexture(candidates[i]) end)
        if ok and tex then
            sliceTexture = tex
            break
        end
    end
    return sliceTexture
end

local function onRadialOperate(playerObj)
    if not playerObj then return end
    AHG.Client.operateNearest(playerObj:getPlayerNum(), "radial")
end

local function addGateSlice(playerObj)
    if not playerObj then return end
    if not AHG.opt("EnableVehicleRadial") then return end
    if not (playerObj.getVehicle and playerObj:getVehicle()) then return end

    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then return end

    local label = AHG.text("IGUI_AHG_RadialOperate")

    -- Avoid duplicate slices if the radial is rebuilt.
    local slices = menu.slices
    if slices then
        for i = 1, #slices do
            if slices[i] and tostring(slices[i].text or "") == label then return end
        end
    end

    local range = tonumber(AHG.opt("TriggerRange")) or 15
    if not AHG.Client.findNearestGate(playerObj, range) then return end

    menu:addSlice(label, getSliceTexture(), onRadialOperate, playerObj)
end

local function wrapVehicleRadial()
    if not ISVehicleMenu or ISVehicleMenu.__AHGWrapped then return end

    local origShow = ISVehicleMenu.showRadialMenu
    ISVehicleMenu.showRadialMenu = function(playerObj, ...)
        local res = nil
        if origShow then
            res = origShow(playerObj, ...)
        end
        pcall(addGateSlice, playerObj)
        return res
    end

    -- Outside radial (standing next to a vehicle) - optional; only when seated
    -- does addGateSlice actually inject, so this is a cheap no-op otherwise.
    if ISVehicleMenu.showRadialMenuOutside then
        local origOutside = ISVehicleMenu.showRadialMenuOutside
        ISVehicleMenu.showRadialMenuOutside = function(playerObj, ...)
            local res = nil
            if origOutside then
                res = origOutside(playerObj, ...)
            end
            pcall(addGateSlice, playerObj)
            return res
        end
    end

    ISVehicleMenu.__AHGWrapped = true
end

Events.OnGameStart.Add(wrapVehicleRadial)
