-- Automatic / Hotkey Gates - vanilla door-linking safety net
--
-- Some multi-tile door/gate/garage assemblies end up with a "double door"
-- link chain longer than 4 pieces (map/mod tile placement issue). Vanilla's
-- IsoDoor.getDoubleDoorObject(obj, i) backs this with a fixed-size array of
-- 4 slots, so any code that walks a broken assembly throws
-- ArrayIndexOutOfBoundsException: "Index 5 out of bounds for length 4".
--
-- Two confirmed vanilla call sites have no error handling around this:
--   1) ISDestroyCursor:render() -> buildUtil.getDoubleDoorObjects(object),
--      called once per rendered frame while the destroy/build cursor hovers
--      a broken assembly. With no guard this floods the log with thousands
--      of identical exceptions in seconds.
--   2) ISDestroyStuffAction:complete() (shared/TimedActions/ISDestroyStuffAction.lua)
--      -> buildUtil.getDoubleDoorObjects(self.item), called BEFORE the
--      actual removal code runs. On a broken assembly this throws first,
--      so the sledgehammer "destroy" plays out (contents dumped, sound
--      played) but self.item is NEVER actually removed from the square -
--      the destroyed gate leaves a corrupted 1x1 remnant that reloads on
--      every server restart and keeps re-triggering the same bug (up to
--      and including crashing the server) on any further interaction.
--
-- AHG's own toggling (AHG_System.lua togglePiece) already pcall-wraps its
-- own ToggleDoor calls and degrades gracefully. This file plugs the same
-- hole in vanilla's own helpers so any caller - render, destroy action, or
-- future vanilla/mod code - gets an empty list instead of a crash for a
-- broken assembly, while leaving normal (non-broken) doors/gates/garage
-- doors completely unaffected.
--
-- Lives in shared/ (not client/) so it loads on dedicated servers and
-- coop hosts too, not just local rendering - ISDestroyStuffAction:complete()
-- runs server-authoritatively.

-- require() can itself fail to resolve/execute this module on some dedicated
-- server setups (seen in the wild: "require(BuildingObjects/ISBuildUtil)
-- failed"), which left the global `buildUtil` nil and made the very next
-- line ("buildUtil.__AHGSafetyPatched") throw "attempted index ... of
-- non-table: null" on every boot. Guard both the require and the global.
pcall(function() require "BuildingObjects/ISBuildUtil" end)

if buildUtil and not buildUtil.__AHGSafetyPatched then
    buildUtil.__AHGSafetyPatched = true

    local origGetDoubleDoorObjects = buildUtil.getDoubleDoorObjects
    function buildUtil.getDoubleDoorObjects(object)
        local ok, result = pcall(origGetDoubleDoorObjects, object)
        if ok and result then return result end
        return {}
    end

    local origGetGarageDoorObjects = buildUtil.getGarageDoorObjects
    function buildUtil.getGarageDoorObjects(object)
        local ok, result = pcall(origGetGarageDoorObjects, object)
        if ok and result then return result end
        return {}
    end
end
