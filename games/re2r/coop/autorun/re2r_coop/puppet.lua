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
--   - Im ActorFolder (get_Folder liefert nil) loescht das Spiel die Puppe beim
--     Nachladen von Bereichen, ca. 0,8 s lang auch jede neu erzeugte. Im
--     Ordner des Spielers (set_FolderSelf, RopewayManagers/TemporaryObjects/
--     Survivor/Player) bleibt sie erhalten (87 s ohne Neuerzeugung).
-- Animation: siehe re2r_coop/anim.lua (Leon im Spiel bestaetigt).
-- UNBESTAETIGT: andere Figuren als Leon, Verhalten bei Szenenwechseln.

local game = require("re2r_coop.game")
local tr = require("re2r_coop.text")
local anim = require("re2r_coop.anim")
local weapon = require("re2r_coop.weapon")

local puppet = {}

puppet.PREFAB_PATH = "ObjectRoot/Prefab/Character/Survivor/Actor/%s.pfb"
puppet.COSTUME = 0
puppet.RETRY_AFTER = 5.0       -- Sekunden bis zum naechsten Versuch nach Fehler
puppet.LOAD_TIMEOUT = 20.0     -- Sekunden, die das Prefab zum Laden haben darf
puppet.RESPAWN_DELAY = 1.0     -- Sekunden Pause, wenn das Spiel die Puppe geloescht hat

-- instances[peer_id] = { state=, character=, prefab=, go=, transform=, motion=, since=, error=,
--                        banks_key=, banks_id=, anim_error=, anim_changes= }
-- state: "loading" -> "ready" | "failed"; "deleted" = vom Spiel geloescht, wartet RESPAWN_DELAY
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

local function drop_weapon(inst)
    weapon.destroy(inst.weapon_go)
    inst.weapon_go, inst.weapon_key = nil, nil
end

local function destroy_go(go)
    if is_valid(go) then
        pcall(go.call, go, "destroy", go)
    end
end

local function fail(inst, now, err)
    drop_weapon(inst)
    destroy_go(inst.go)
    inst.go, inst.transform = nil, nil
    inst.state, inst.error, inst.since = "failed", tostring(err), now
end

local function start_loading(inst, now)
    anim.forget(inst.motion)
    drop_weapon(inst)
    inst.go, inst.transform, inst.motion, inst.error = nil, nil, nil, nil
    inst.weapon_error = nil
    inst.banks_key, inst.banks_id, inst.anim_error, inst.vars_seq = nil, nil, nil, nil
    inst.restarts_seen = nil
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
    -- In den Ordner des Spielers, sonst raeumt das Spiel sie beim Nachladen auf.
    local player_folder = try_call(game.get_player(), "get_Folder")
    if player_folder ~= nil then
        try_call(go, "set_FolderSelf", player_folder)
    end
    inst.transform = try_call(go, "get_Transform")
    inst.motion = anim.get_motion(go)
    inst.anim_changes = 0

    local changer = try_call(go, "getComponent(System.Type)", sdk.typeof(game.ns("survivor.SurvivorCostumeChanger")))
    if changer == nil then
        return fail(inst, now, "SurvivorCostumeChanger fehlt")
    end
    changer:call("change(app.ropeway.SurvivorDefine.SurvivorType, app.ropeway.SurvivorDefine.Costume)",
        inst.character, puppet.COSTUME)
    inst.state, inst.since = "ready", now
end

-- Geglaettete Drehung aus ghost (r.rot), sonst die zuletzt empfangene.
function puppet.rotation_of(r)
    local q = r.rot
    if q ~= nil then
        return Quaternion.new(q.w, q.x, q.y, q.z)
    end
    local t = r.target or {}
    return Quaternion.new(t.qw or 1, t.qx or 0, t.qy or 0, t.qz or 0)
end

-- Waffenmodell in der Hand an die Waffe des Mitspielers anpassen.
local function sync_weapon(inst, a)
    local key = weapon.key(a.weapon)
    if inst.weapon_key == key and (inst.weapon_go == nil or try_call(inst.weapon_go, "get_Valid") == true) then
        return
    end
    drop_weapon(inst)
    inst.weapon_key = key
    if a.weapon ~= nil then
        inst.weapon_go = weapon.attach(inst.transform, a.weapon)
    end
end

-- Animationen des Mitspielers uebernehmen (a = Eintrag aus remote_anim).
local function sync_anim(inst, a)
    if a == nil or a.banks == nil or inst.motion == nil then
        return
    end
    local ok, err = pcall(sync_weapon, inst, a)
    if not ok then
        inst.weapon_error = tostring(err)
    end
    local key = anim.banks_key(a.banks)
    if inst.banks_key ~= key then
        -- Nur einmal pro Bank-Satz versuchen, auch wenn es fehlschlaegt.
        inst.banks_key, inst.banks_id = key, a.banks_id
        local ok, err = pcall(anim.apply_banks, inst.motion, a.banks)
        inst.anim_error = (not ok) and tostring(err) or nil
    end
    inst.banks_id = a.banks_id
    if inst.anim_error == nil and a.state ~= nil and a.state.banks_id == a.banks_id then
        if inst.vars_seq ~= a.state.seq then
            inst.vars_seq = a.state.seq
            anim.apply_vars(inst.motion, a.state)
        end
        inst.restarts_seen = inst.restarts_seen or {}
        inst.anim_changes = inst.anim_changes + anim.apply_layers(inst.motion, a.state, inst.restarts_seen)
    end
end

local function sync(peer_id, r, visible, now, a)
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

    if inst.state == "deleted" then
        if now - inst.since >= puppet.RESPAWN_DELAY then
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
        anim.forget(inst.motion)
        drop_weapon(inst)
        inst.go, inst.transform, inst.motion = nil, nil, nil
        inst.state, inst.since = "deleted", now
        inst.respawns = (inst.respawns or 0) + 1
        return
    end
    pcall(inst.go.call, inst.go, "set_DrawSelf", visible)
    if visible and inst.transform ~= nil then
        inst.transform:call("set_Position", Vector3f.new(r.pos.x, r.pos.y, r.pos.z))
        inst.transform:call("set_Rotation", puppet.rotation_of(r))
        local ok, err = pcall(sync_anim, inst, a)
        if not ok then
            inst.anim_error = tostring(err)
        end
    end
end

-- Jeden Frame pro Mitspieler aufrufen. r ist der Eintrag aus ghost.remote,
-- visible = ob die Figur gerade zu sehen sein soll, a (optional) die
-- Animationsdaten { banks=, banks_id=, state= } aus ANIM_BANKS/ANIM_STATE.
-- Fehler im Spielzugriff setzen die Puppe auf "failed" (neuer Versuch nach
-- RETRY_AFTER), Animationsfehler nur auf anim_error.
function puppet.sync(peer_id, r, visible, now, a)
    local ok, err = pcall(sync, peer_id, r, visible, now, a)
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
        anim.forget(inst.motion)
        drop_weapon(inst)
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
        return tr("debug.none")
    end
    if inst.state == "failed" then
        return tr("status.error", { error = tostring(inst.error) })
    end
    if inst.state == "ready" then
        if inst.anim_error ~= nil then
            return tr("debug.puppet_anim_error", { error = inst.anim_error })
        elseif inst.weapon_error ~= nil then
            return tr("debug.puppet_weapon_error", { error = inst.weapon_error })
        elseif inst.banks_key ~= nil then
            return tr("debug.puppet_animated", { changes = inst.anim_changes or 0, respawns = inst.respawns or 0 })
        end
        return tr("debug.puppet_no_anim")
    end
    return inst.state
end

return puppet
