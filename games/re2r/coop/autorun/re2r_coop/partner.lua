-- re2r_coop/partner.lua
--
-- VERSUCH: Mitspieler als echte zweite Spielfigur (wie der Partner in RE0)
-- statt als Puppe. Wir erzeugen das Player-Prefab der Figur in der Welt des
-- lokalen Spielers. Das Spiel steuert sie mit seinen eigenen Ablaeufen, die
-- Eingaben kommen ueber remote_input.lua vom Mitspieler.
--
-- Bestaetigt im Spiel am 3. November 2026 (Konsole): Claire
-- (Player/pl1000.pfb) laesst sich in Leons Spiel im Ordner des Spielers
-- erzeugen, SurvivorCostumeChanger.change(1, 0) laedt ihr Modell,
-- PlayerManager.get_CurrentPlayer bleibt Leon.
-- UNBESTAETIGT: Positionskorrektur per Transform.set_Position (der
-- CharacterController koennte sie ueberschreiben), Kamera, HUD, Inventar,
-- Gegner, Treffer.

local game = require("re2r_coop.game")
local remote_input = require("re2r_coop.remote_input")

local partner = {}

partner.PREFAB_PATH = "ObjectRoot/Prefab/Character/Player/%s.pfb"
partner.COSTUME = 0
partner.CORRECT_DISTANCE = 1.5 -- Meter Abweichung, ab der wir auf die Netzwerkposition setzen
partner.RETRY_AFTER = 5.0
partner.LOAD_TIMEOUT = 20.0

-- instances[peer_id] = { state=, character=, prefab=, go=, transform=, since=, error= }
partner.instances = {}

local try_call = game.try_call

function partner.prefab_path(character)
    if character == nil or character == game.CHARACTER_UNKNOWN then
        return nil
    end
    local name = game.enum_name(game.ENUM_SURVIVOR_TYPE, character)
    if not name:match("^PL%d%d%d%d$") then
        return nil
    end
    return string.format(partner.PREFAB_PATH, name:lower())
end

local function is_valid(go)
    return go ~= nil and try_call(go, "get_Valid") == true
end

local function destroy(inst)
    if is_valid(inst.go) then
        pcall(inst.go.call, inst.go, "destroy", inst.go)
    end
    inst.go, inst.transform = nil, nil
    remote_input.attach(nil)
end

local function fail(inst, now, err)
    destroy(inst)
    inst.state, inst.error, inst.since = "failed", tostring(err), now
end

local function start_loading(inst, now)
    inst.error, inst.since = nil, now
    local path = partner.prefab_path(inst.character)
    if path == nil then
        return fail(inst, now, "keine Spielfigur fuer ID " .. tostring(inst.character))
    end
    local prefab = sdk.create_instance("via.Prefab", true)
    if prefab == nil then
        return fail(inst, now, "via.Prefab nicht erzeugt")
    end
    prefab = prefab:add_ref()
    prefab:call("set_Path", path)
    prefab:call("set_Standby", true)
    inst.prefab, inst.path, inst.state = prefab, path, "loading"
end

local function rotation_of(r)
    local t = r.target or {}
    return Quaternion.new(t.qw or 1, t.qx or 0, t.qy or 0, t.qz or 0)
end

local function spawn(inst, r, now)
    local player = game.get_player()
    local folder = player and try_call(player, "get_Folder")
    if folder == nil then
        return fail(inst, now, "Ordner des Spielers nicht gefunden")
    end
    local go = inst.prefab:call("instantiate(via.vec3, via.Quaternion, via.Folder)",
        Vector3f.new(r.pos.x, r.pos.y, r.pos.z), rotation_of(r), folder)
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
        inst.character, partner.COSTUME)
    remote_input.install()
    remote_input.attach(go)
    inst.state, inst.since = "ready", now
end

local function sync(peer_id, r, enabled, now)
    local inst = partner.instances[peer_id]
    if inst ~= nil and inst.character ~= r.character then
        partner.remove(peer_id)
        inst = nil
    end
    if not enabled then
        if inst ~= nil then
            partner.remove(peer_id)
        end
        return
    end
    if inst == nil then
        if partner.prefab_path(r.character) == nil or r.target == nil then
            return
        end
        inst = { character = r.character }
        partner.instances[peer_id] = inst
        start_loading(inst, now)
    end

    if inst.state == "failed" then
        if now - inst.since >= partner.RETRY_AFTER then
            start_loading(inst, now)
        end
        return
    end
    if inst.state == "loading" then
        if try_call(inst.prefab, "get_Ready") then
            spawn(inst, r, now)
        elseif now - inst.since > partner.LOAD_TIMEOUT then
            fail(inst, now, "Prefab laedt nicht: " .. tostring(inst.path))
        end
        return
    end

    -- ready: vom Spiel geloescht (z. B. Bereichswechsel)? Dann neu erzeugen.
    if not is_valid(inst.go) then
        destroy(inst)
        start_loading(inst, now)
        return
    end
    -- Weicht die Figur zu weit ab, auf die Netzwerkposition setzen.
    local p = inst.transform and inst.transform:call("get_Position")
    if p ~= nil then
        local dx, dy, dz = p.x - r.pos.x, p.y - r.pos.y, p.z - r.pos.z
        inst.drift = math.sqrt(dx * dx + dy * dy + dz * dz)
        if inst.drift > partner.CORRECT_DISTANCE then
            inst.transform:call("set_Position", Vector3f.new(r.pos.x, r.pos.y, r.pos.z))
            inst.transform:call("set_Rotation", rotation_of(r))
            inst.corrections = (inst.corrections or 0) + 1
        end
    end
end

-- Jeden Frame pro Mitspieler. r = Eintrag aus ghost.remote.
function partner.sync(peer_id, r, enabled, now)
    local ok, err = pcall(sync, peer_id, r, enabled, now)
    if not ok then
        local inst = partner.instances[peer_id]
        if inst ~= nil then
            fail(inst, now, err)
        end
    end
end

function partner.has(peer_id)
    local inst = partner.instances[peer_id]
    return inst ~= nil and inst.state == "ready"
end

function partner.remove(peer_id)
    local inst = partner.instances[peer_id]
    if inst ~= nil then
        destroy(inst)
        partner.instances[peer_id] = nil
    end
end

function partner.clear()
    for id in pairs(partner.instances) do
        partner.remove(id)
    end
end

function partner.status_text(peer_id)
    local inst = partner.instances[peer_id]
    if inst == nil then
        return "keine"
    end
    if inst.state == "failed" then
        return "Fehler: " .. tostring(inst.error)
    end
    if inst.state == "ready" then
        return string.format("ready, Abweichung %.2f m, %d Korrekturen", inst.drift or 0, inst.corrections or 0)
    end
    return inst.state
end

return partner
