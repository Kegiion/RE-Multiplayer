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
-- Bestaetigt mit Testbot (3. November 2026): Die Figur laeuft aus eigener
-- Kraft mit den Eingaben des Mitspielers (Gehen-Animationen), bleibt aber
-- nicht exakt auf seiner Position (0,3 bis 1 m, wachsend). Transform.set_Position
-- wirkt trotz CharacterController. Hartes Zuruecksetzen ab 1,5 m sah aus wie
-- staendiges Teleportieren, deshalb jetzt sanftes Nachziehen.
-- Sanfte Korrektur bestaetigt (keine Spruenge mehr), mit richtigem
-- Kamera-Vorzeichen mittlere Abweichung 0,25 m, hoechstens 1,0 m.
-- UNBESTAETIGT: Kamera, HUD, Inventar, Gegner, Treffer.

local game = require("re2r_coop.game")
local tr = require("re2r_coop.text")
local remote_input = require("re2r_coop.remote_input")

local partner = {}

partner.PREFAB_PATH = "ObjectRoot/Prefab/Character/Player/%s.pfb"
partner.COSTUME = 0
partner.SOFT_MIN_DISTANCE = 0.1 -- Meter: darunter nicht korrigieren
partner.SOFT_RATE = 3.0         -- Anteil der Abweichung pro Sekunde, der nachgezogen wird
partner.SNAP_DISTANCE = 3.0     -- Meter: ab hier direkt auf die Netzwerkposition setzen
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

-- err: Textschluessel (debug.err_*) oder rohe Fehlermeldung, siehe puppet.lua
local function fail(inst, now, err, params)
    destroy(inst)
    inst.state, inst.error, inst.error_params, inst.since = "failed", tostring(err), params, now
end

local function start_loading(inst, now)
    inst.error, inst.since = nil, now
    local path = partner.prefab_path(inst.character)
    if path == nil then
        return fail(inst, now, "debug.err_no_character", { id = tostring(inst.character) })
    end
    local prefab = sdk.create_instance("via.Prefab", true)
    if prefab == nil then
        return fail(inst, now, "debug.err_no_prefab")
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
        return fail(inst, now, "debug.err_no_player_folder")
    end
    local go = inst.prefab:call("instantiate(via.vec3, via.Quaternion, via.Folder)",
        Vector3f.new(r.pos.x, r.pos.y, r.pos.z), rotation_of(r), folder)
    if go == nil then
        return fail(inst, now, "debug.err_instantiate")
    end
    inst.go = go
    inst.transform = try_call(go, "get_Transform")
    local changer = try_call(go, "getComponent(System.Type)", sdk.typeof(game.ns("survivor.SurvivorCostumeChanger")))
    if changer == nil then
        return fail(inst, now, "debug.err_costume")
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
            fail(inst, now, "debug.err_prefab_timeout", { path = tostring(inst.path) })
        end
        return
    end

    -- ready: vom Spiel geloescht (z. B. Bereichswechsel)? Dann neu erzeugen.
    if not is_valid(inst.go) then
        destroy(inst)
        start_loading(inst, now)
        return
    end
    -- Abweichung von der Netzwerkposition sanft nachziehen, bei grossem
    -- Abstand (Teleport, Raumwechsel) direkt setzen.
    local dt = inst.last_sync and math.min(now - inst.last_sync, 0.1) or 0
    inst.last_sync = now
    local p = inst.transform and inst.transform:call("get_Position")
    if p ~= nil then
        local ex, ey, ez = r.pos.x - p.x, r.pos.y - p.y, r.pos.z - p.z
        inst.drift = math.sqrt(ex * ex + ey * ey + ez * ez)
        if inst.drift > partner.SNAP_DISTANCE then
            inst.transform:call("set_Position", Vector3f.new(r.pos.x, r.pos.y, r.pos.z))
            inst.transform:call("set_Rotation", rotation_of(r))
            inst.corrections = (inst.corrections or 0) + 1
        elseif inst.drift > partner.SOFT_MIN_DISTANCE and dt > 0 then
            local k = math.min(1, partner.SOFT_RATE * dt)
            inst.transform:call("set_Position", Vector3f.new(p.x + ex * k, p.y + ey * k, p.z + ez * k))
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
        return tr("debug.none")
    end
    if inst.state == "failed" then
        return tr("status.error", { error = tr(tostring(inst.error), inst.error_params) })
    end
    if inst.state == "ready" then
        return tr("debug.partner_ready", { drift = string.format("%.2f", inst.drift or 0), jumps = inst.corrections or 0 })
    end
    return inst.state == "loading" and tr("debug.state_loading") or tostring(inst.state)
end

return partner
