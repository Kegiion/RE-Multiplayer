-- re2r_coop/puppet.lua
--
-- Meilenstein 2: Mitspieler als echte Spielfigur ("Puppe"). Wir erzeugen das
-- Actor-Prefab der Figur (das nutzt das Spiel fuer Zwischensequenzen: keine
-- Steuerung, keine Kollision, kein Inventar) und setzen es jeden Frame auf
-- die empfangene Position.
--
-- Bestaetigt im Spiel am 2. November 2026 (Entwickler-Konsole):
--   - SurvivorManager.PrefabInfoList: Actor-Prefabs unter
--     ObjectRoot/Prefab/Character/Survivor/Actor/<pl0000>.pfb
--   - eigenes via.Prefab per sdk.create_instance + set_Path + set_Standby(true),
--     get_Ready() wird sofort true (Leon war schon geladen)
--   - instantiate(via.vec3, via.Quaternion, via.Folder) mit
--     SurvivorManager.get_ActorFolder() erzeugt GameObject "pl0000"
--   - ohne Modell, bis SurvivorCostumeChanger.change(SurvivorType, Costume)
--     Hair/Face/Body nachlaedt; danach sichtbar
--   - via.GameObject.destroy(go): ab dem naechsten Frame get_Valid() == false
-- UNBESTAETIGT: andere Figuren als Leon, Verhalten bei Szenenwechseln,
--   Animation (die Puppe steht noch still).

local game = require("re2r_coop.game")

local puppet = {}

puppet.PREFAB_PATH = "ObjectRoot/Prefab/Character/Survivor/Actor/%s.pfb"
puppet.COSTUME = 0
puppet.RETRY_AFTER = 5.0       -- Sekunden bis zum naechsten Versuch nach Fehler
puppet.LOAD_TIMEOUT = 20.0     -- Sekunden, die das Prefab zum Laden haben darf

-- instances[peer_id] = { state=, character=, prefab=, go=, transform=, since=, error= }
-- state: "loading" -> "costume" -> "ready" | "failed"
puppet.instances = {}

local try_call = game.try_call

-- Prefab-Pfad fuer eine Figur-ID (SurvivorType), nil wenn unbekannt.
function puppet.prefab_path(character)
    if character == nil or character == game.CHARACTER_UNKNOWN then
        return nil
    end
    local name = game.enum_name(game.ENUM_SURVIVOR_TYPE, character)
    if not name:match("^PL%d%d%d%d$") then
        return nil
    end
    return string.format(puppet.PREFAB_PATH, name:lower())
end

local function is_valid(go)
    return go ~= nil and try_call(go, "get_Valid") == true
end

local function destroy_go(go)
    if is_valid(go) then
        pcall(go.call, go, "destroy", go)
    end
end

local function fail(inst, now, err)
    destroy_go(inst.go)
    inst.go, inst.transform = nil, nil
    inst.state, inst.error, inst.since = "failed", tostring(err), now
end

local function start_loading(inst, now)
    inst.go, inst.transform, inst.error = nil, nil, nil
    inst.since = now
    local path = puppet.prefab_path(inst.character)
    if path == nil then
        return fail(inst, now, "keine Actor-Figur fuer ID " .. tostring(inst.character))
    end
    local prefab = sdk.create_instance("via.Prefab", true)
    if prefab == nil then
        return fail(inst, now, "via.Prefab nicht erzeugt")
    end
    if prefab.add_ref then
        prefab = prefab:add_ref()
    end
    prefab:call("set_Path", path)
    prefab:call("set_Standby", true)
    inst.prefab, inst.path, inst.state = prefab, path, "loading"
end

local function spawn(inst, r, now)
    local sm = sdk.get_managed_singleton(game.ns("SurvivorManager"))
    local folder = try_call(sm, "get_ActorFolder")
    local pos = Vector3f.new(r.pos.x, r.pos.y, r.pos.z)
    local rot = puppet.rotation_of(r)
    local go
    if folder ~= nil then
        go = inst.prefab:call("instantiate(via.vec3, via.Quaternion, via.Folder)", pos, rot, folder)
    else
        go = inst.prefab:call("instantiate(via.vec3, via.Quaternion)", pos, rot)
    end
    if go == nil then
        return fail(inst, now, "instantiate lieferte nil")
    end
    inst.go = go
    inst.transform = try_call(go, "get_Transform")

    local changer = try_call(go, "getComponent(System.Type)", sdk.typeof(game.ns("survivor.SurvivorCostumeChanger")))
    if changer == nil then
        return fail(inst, now, "SurvivorCostumeChanger fehlt")
    end
    changer:call("change(app.ropeway.SurvivorDefine.SurvivorType, app.ropeway.SurvivorDefine.Costume)",
        inst.character, puppet.COSTUME)
    inst.state, inst.since = "ready", now
end

function puppet.rotation_of(r)
    local t = r.target or {}
    return Quaternion.new(t.qw or 1, t.qx or 0, t.qy or 0, t.qz or 0)
end

local function sync(peer_id, r, visible, now)
    local inst = puppet.instances[peer_id]
    local character = r.character

    if inst ~= nil and inst.character ~= character then
        puppet.remove(peer_id)
        inst = nil
    end
    if inst == nil then
        if not visible or puppet.prefab_path(character) == nil then
            return
        end
        inst = { character = character }
        puppet.instances[peer_id] = inst
        start_loading(inst, now)
    end

    if inst.state == "failed" then
        if visible and now - inst.since >= puppet.RETRY_AFTER then
            start_loading(inst, now)
        end
        return
    end

    if inst.state == "loading" then
        if try_call(inst.prefab, "get_Ready") then
            spawn(inst, r, now)
        elseif now - inst.since > puppet.LOAD_TIMEOUT then
            fail(inst, now, "Prefab laedt nicht: " .. tostring(inst.path))
        end
        return
    end

    -- ready: Das Spiel kann die Figur z. B. beim Szenenwechsel loeschen.
    if not is_valid(inst.go) then
        start_loading(inst, now)
        return
    end
    pcall(inst.go.call, inst.go, "set_DrawSelf", visible)
    if visible and inst.transform ~= nil then
        inst.transform:call("set_Position", Vector3f.new(r.pos.x, r.pos.y, r.pos.z))
        inst.transform:call("set_Rotation", puppet.rotation_of(r))
    end
end

-- Jeden Frame pro Mitspieler aufrufen. r ist der Eintrag aus ghost.remote,
-- visible = ob die Figur gerade zu sehen sein soll. Fehler im Spielzugriff
-- setzen die Puppe auf "failed" (neuer Versuch nach RETRY_AFTER).
function puppet.sync(peer_id, r, visible, now)
    local ok, err = pcall(sync, peer_id, r, visible, now)
    if not ok then
        local inst = puppet.instances[peer_id]
        if inst ~= nil then
            fail(inst, now, err)
        end
    end
end

function puppet.remove(peer_id)
    local inst = puppet.instances[peer_id]
    if inst ~= nil then
        destroy_go(inst.go)
        puppet.instances[peer_id] = nil
    end
end

function puppet.clear()
    for id in pairs(puppet.instances) do
        puppet.remove(id)
    end
end

-- Kurzer Status fuer die Debug-Anzeige.
function puppet.status_text(peer_id)
    local inst = puppet.instances[peer_id]
    if inst == nil then
        return "keine"
    end
    if inst.state == "failed" then
        return "Fehler: " .. tostring(inst.error)
    end
    return inst.state
end

return puppet
