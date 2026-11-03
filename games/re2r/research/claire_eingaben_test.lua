-- Versuch vom 3. November 2026 (im Spiel bestaetigt): Claire als echte zweite
-- Spielfigur erzeugen und von den Eingaben des lokalen Spielers trennen.
--
-- Ausfuehren ueber die Entwickler-Konsole:
--   python tools/re2r_console.py -f games/re2r/research/claire_eingaben_test.lua
-- Vorher speichern, Versuche koennen abstuerzen. Die Hooks bleiben bis
-- "Reset Scripts" aktiv (REFramework kann Hooks nicht entfernen), deshalb
-- steuern Schalter in console.store.claire_input das Verhalten.
--
-- Kernidee: Die Engine aktualisiert die Figuren parallel in mehreren Threads.
-- Wir merken pro Thread, ob er gerade eine Komponente von Claire aktualisiert,
-- und beantworten nur dann die Abfragen des InputSystem selbst.

local st = console.store
local isys = sdk.get_managed_singleton(game.ns("InputSystem"))

-- 1. Claire erzeugen (Player-Prefab, im Ordner des Spielers) ----------------
local function spawn_claire()
    local pf = sdk.create_instance("via.Prefab", true):add_ref()
    pf:call("set_Path", "ObjectRoot/Prefab/Character/Player/pl1000.pfb")
    pf:call("set_Standby", true)
    st.claire_prefab = pf
    local t0 = coopnet.time()
    task(function()
        if not pf:call("get_Ready") then
            return coopnet.time() - t0 < 20
        end
        local player = game.get_player()
        local tr = player:call("get_Transform")
        local p, f = tr:call("get_Position"), tr:call("get_AxisZ")
        local go = pf:call("instantiate(via.vec3, via.Quaternion, via.Folder)",
            Vector3f.new(p.x + f.x * 2, p.y, p.z + f.z * 2), tr:call("get_Rotation"), player:call("get_Folder"))
        local cc = go:call("getComponent(System.Type)", sdk.typeof(game.ns("survivor.SurvivorCostumeChanger")))
        cc:call("change(app.ropeway.SurvivorDefine.SurvivorType, app.ropeway.SurvivorDefine.Costume)", 1, 0)
        st.claire = go
        st.claire_input.addrs = {}
        for _, comp in ipairs(go:call("get_Components"):get_elements()) do
            if comp:get_type_definition():get_full_name():find("^app%.ropeway%.survivor") then
                st.claire_input.addrs[comp:get_address()] = true
            end
        end
        return false
    end)
end

-- 2. Hooks (nur einmal pro Lua-Zustand) ------------------------------------
st.claire_input = st.claire_input or { enabled = true, inside = {}, addrs = {}, bool = 0, stick = 0 }
local C = st.claire_input
C.dummy_addr = isys:get_field("DummyStick"):get_address()

local UPDATE_TYPES = {
    "survivor.SurvivorController", "survivor.SurvivorActionOrderer", "survivor.SurvivorCondition",
    "survivor.SurvivorUserVariablesUpdater", "survivor.SurvivorCharacterController", "survivor.Equipment",
    "survivor.SurvivorWallHitChecker", "survivor.SurvivorBuriedArmCorrector", "survivor.SurvivorIKLeftArmController",
    "survivor.player.PlayerForbidAimController", "LookAtBase", "MotionSpeedController",
}

if not C.installed then
    local hooked = {}
    local function hook_update(m)
        if m == nil then return end
        local key = m:get_declaring_type():get_full_name() .. "." .. m:get_name()
        if hooked[key] then return end
        hooked[key] = true
        sdk.hook(m, function(args)
            local s = thread.get_hook_storage()
            s.mark = false
            if C.addrs[sdk.to_int64(args[2])] then
                local id = thread.get_id()
                C.inside[id] = (C.inside[id] or 0) + 1
                s.mark = true
            end
        end, function(r)
            local s = thread.get_hook_storage()
            if s.mark then
                local id = thread.get_id()
                C.inside[id] = C.inside[id] - 1
            end
            return r
        end)
    end
    for _, short in ipairs(UPDATE_TYPES) do
        local td = sdk.find_type_definition(game.ns(short))
        if td then
            hook_update(td:get_method("update"))
            hook_update(td:get_method("lateUpdate"))
        end
    end

    local td = sdk.find_type_definition(game.ns("InputSystem"))
    for _, m in ipairs(td:get_methods()) do
        local n = m:get_name()
        local rt = m:get_return_type():get_full_name()
        local kind
        if rt == "System.Boolean" and ((n:match("^is[A-Z]") and (n:find("On") or n:find("Down") or n:find("Up")
            or n:find("Front") or n:find("Back") or n:find("Left") or n:find("Right"))) or n == "checkCommand") then
            kind = "bool"
        elseif rt == game.ns("InputSystem.AnalogStick") then
            kind = "stick"
        end
        if kind then
            sdk.hook(m, function(args) end, function(retval)
                if C.enabled and (C.inside[thread.get_id()] or 0) > 0 then
                    if kind == "bool" then
                        C.bool = C.bool + 1
                        return sdk.to_ptr(0)
                    end
                    C.stick = C.stick + 1
                    return sdk.to_ptr(C.dummy_addr)
                end
                return retval
            end)
        end
    end
    C.installed = true
end

if st.claire == nil or game.try_call(st.claire, "get_Valid") ~= true then
    spawn_claire()
    out("Claire wird erzeugt, Eingaben getrennt")
else
    out("Claire existiert schon, Eingaben getrennt")
end
