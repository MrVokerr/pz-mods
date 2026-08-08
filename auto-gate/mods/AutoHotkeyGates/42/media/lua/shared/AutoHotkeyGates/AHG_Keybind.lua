-- Automatic / Hotkey Gates - keybind registration
-- Adds an "Automatic Hotkey Gates" section with an Operate Gate binding to
-- Options > Key Bindings. Labels come from UI_optionscreen_binding_<ID>.

local function ensureBinding(id, defaultKey)
    if not keyBinding or not Keyboard then return end
    for i = 1, #keyBinding do
        if keyBinding[i] and keyBinding[i].value == id then
            return
        end
    end
    table.insert(keyBinding, { value = id, key = defaultKey or 0 })
end

local function ensureSection(header)
    if not keyBinding then return end
    for i = 1, #keyBinding do
        if keyBinding[i] and keyBinding[i].value == header and keyBinding[i].key == nil then
            return
        end
    end
    table.insert(keyBinding, { value = header })
end

local function registerAHGBindings()
    if not keyBinding or not Keyboard then return end
    ensureSection("[AHG_Keybinds]")
    ensureBinding("AHG_OperateGate", Keyboard.KEY_G)
end

-- Defer until game boot so translations are loaded when the options screen builds.
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(registerAHGBindings)
else
    registerAHGBindings()
end
