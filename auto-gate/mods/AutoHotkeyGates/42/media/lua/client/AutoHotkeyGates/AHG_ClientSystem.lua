-- Automatic / Hotkey Gates - client mirror of the gate registry
-- Receives registered-gate GlobalObjects from the server so the client can
-- find nearby gates cheaply without scanning squares.

require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "AutoHotkeyGates/AHG_Shared"

CAHGGlobalObject = CGlobalObject:derive("CAHGGlobalObject")

function CAHGGlobalObject:new(luaSystem, globalObject)
    return CGlobalObject.new(self, luaSystem, globalObject)
end

CAHGSystem = CGlobalObjectSystem:derive("CAHGSystem")

function CAHGSystem:new()
    return CGlobalObjectSystem.new(self, AHG.SystemName)
end

function CAHGSystem:newLuaObject(globalObject)
    return CAHGGlobalObject:new(self, globalObject)
end

function CAHGSystem:isValidIsoObject(isoObject)
    return AHG.isRegisteredObject(isoObject)
end

CGlobalObjectSystem.RegisterSystemClass(CAHGSystem)
