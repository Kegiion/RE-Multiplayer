-- RE0 HD Koop (RE:Multiplayer) - Einstiegspunkt
--
-- Wird von der RE:Multiplayer-Runtime automatisch geladen (remultiplayer/autorun/).
-- Menue: Taste Einfg oder F8 -> Abschnitt "RE0 Koop".
--
-- Aufbau:
--   remultiplayer_coop/*          gemeinsame Lua-Bibliothek (wie bei RE2)
--   re0hd_coop/game.lua    RE0-spezifischer Zugriff auf Spieldaten (Figuren, Kamera, Partner-Tasten)
--   re0hd_coop/puppet.lua  Partner als Puppe des Mitspielers (laeuft dessen Weg nach)
--   re0hd_coop/savesync.lua Spielstand des Hosts uebertragen (Join)
--   re0hd_coop/memtool.lua Speicher-Werkzeug fuer die Forschung
--   re0hd_coop/explorer.lua MT-Explorer: Klassen und Objekte der Engine (Forschung)
--   re0hd_coop/devconsole.lua Entwickler-Konsole fuer Claude (standardmaessig aus)

local MOD_VERSION = "0.8.0"
local CONFIG_FILE = "re0hd_coop_config.json"

if coopnet == nil then
    re.on_draw_ui(function()
        if imgui.tree_node("RE0 Koop") then
            imgui.text_colored("Netzwerk-API (coopnet) fehlt - falsche Runtime-Version?", 0xFF4040FF)
            imgui.tree_pop()
        end
    end)
    return
end

local Session = require("remultiplayer_coop.session")
local game = require("re0hd_coop.game")
local memtool = require("re0hd_coop.memtool")
local explorer = mt and require("re0hd_coop.explorer") -- mt.* gibt es ab Runtime 0.2.0
local devconsole = require("re0hd_coop.devconsole")
local Puppet = require("re0hd_coop.puppet")
local savesync = require("re0hd_coop.savesync")

local SEND_INTERVAL = 1 / 30 -- 30 Positionsupdates pro Sekunde
local SWITCH_RETRY = 3.0     -- s zwischen zwei automatischen Figurwechseln
local SWITCH_PRESS = 0.15    -- s, so lange wird V gedrueckt
local DOOR_WALK_MAX = 5.0    -- s, so lange laeuft der Partner hoechstens zur Tuer, bevor er verschwindet
local REMOTE_TIMEOUT = 1.0   -- s ohne Daten: Partner wieder der KI ueberlassen
local SOLO_DELAY = 2.0       -- s Abstand beim Spur-Test allein

-- --- Einstellungen ---------------------------------------------------------

local config = {
    name = "Spieler",
    address = "127.0.0.1",
    port = 27350,
    watches = {}, -- { {name=, expr=, type=}, ... } fuer das Speicher-Werkzeug
    devconsole = false, -- Entwickler-Konsole fuer Claude
    puppet = true,      -- Mitspieler steuert den Partner
    join_slot = 20,     -- Platz (1..20) fuer den Spielstand des Hosts
    auto_switch = true, -- als Mitspieler automatisch die andere Figur nehmen
}

local function load_config()
    local ok, data = pcall(json.load_file, CONFIG_FILE)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            if config[k] ~= nil and type(v) == type(config[k]) then
                config[k] = v
            end
        end
    end
end

local function save_config()
    pcall(json.dump_file, CONFIG_FILE, config)
end

load_config()

-- --- Sitzung -----------------------------------------------------------

local session = Session.new({
    net = coopnet,
    game = game.ID,
    mod_version = MOD_VERSION,
    name = config.name,
    max_peers = 1, -- Story-Koop: zwei Spieler
})

session:on("CHAT", function(s, peer, msg)
    s:log("%s: %s", peer.name or "?", msg.text)
end)

-- --- Geister-Koop: eigene Figur senden, Partner folgt dem Mitspieler -----

local coop = {
    puppet = Puppet.new(game, { delay = 0.2, adaptive = true }),
    solo = Puppet.new(game, { delay = SOLO_DELAY }),
    door = Puppet.new(game, { delay = 0 }), -- laeuft zur Tuer, durch die der Mitspieler gegangen ist
    solo_active = false,  -- Spur-Test allein (nicht gespeichert)
    seq = 0,
    last_send = 0,
    local_state = nil,
    remote = nil,         -- letzter Zustand des Mitspielers
    remote_seq = nil,
    remote_time = 0,
    same_character = false,
    local_area = nil,     -- eigener Raum (z. B. "Tr04") oder nil
    same_room = nil,      -- true/false, nil = unbekannt
    switch_until = nil,   -- V wird gerade gedrueckt (bis zu diesem Zeitpunkt)
    last_switch = -100,
    switches = 0,
    exit_point = nil,     -- letzte Position des Mitspielers in meinem Raum, bevor er ihn verlassen hat
    away = nil,           -- Mitspieler in anderem Raum: { phase = "tuer"|"weg", since=, exit=, hide= }
}

-- Steuern beide dieselbe Figur (typisch direkt nach dem Join auf den Spielstand
-- des Hosts), wechselt der Mitspieler (nicht der Host) automatisch mit V.
local function auto_switch_frame(now)
    if coop.switch_until then
        if now >= coop.switch_until then
            game.set_change_key(false)
            coop.switch_until = nil
        end
        return
    end
    if config.auto_switch and coop.same_character and not session.is_host
        and now - coop.last_switch >= SWITCH_RETRY then
        coop.last_switch = now
        coop.switch_until = now + SWITCH_PRESS
        coop.switches = coop.switches + 1
        game.set_change_key(true)
        session:log("Ihr steuert dieselbe Figur - wechsle automatisch (V)")
    end
end

session:on("PLAYER_STATE", function(s, peer, msg)
    -- Veraltete (ueberholte) Pakete verwerfen; Ueberlauf der Nummer beachten
    if coop.remote_seq and ((msg.seq - coop.remote_seq) % 4294967296) > 2147483648 then
        return
    end
    coop.remote_seq = msg.seq
    if coop.remote and coop.remote.area ~= msg.area then
        -- Verlaesst er meinen Raum, ist seine letzte Position dort die Tuer
        if coop.local_area and coop.remote.area == coop.local_area then
            coop.exit_point = coop.remote
        end
        coop.puppet:reset() -- Spur aus dem alten Raum gilt nicht mehr
    end
    coop.remote = msg
    coop.remote_time = s:time()
    coop.puppet:push(msg, s:time())
end)

session:subscribe("peer_left", function()
    coop.remote, coop.remote_seq = nil, nil
    coop.exit_point = nil
    coop.puppet:reset()
end)

-- Mitspieler ist in einem anderen Raum: Partner geht zur Tuer und verschwindet dort
local function away_frame(now)
    if not coop.away then
        local exit = coop.exit_point
        coop.exit_point = nil
        coop.away = { phase = exit and "tuer" or "weg", since = now, exit = exit }
        coop.door:reset()
        if exit then
            coop.door:push(exit, now)
        end
        session:log("Mitspieler ist in einem anderen Raum - Partner %s",
            exit and "geht zur Tuer" or "wird ausgeblendet")
    end
    local away = coop.away
    if away.phase == "tuer" then
        coop.door:update(now)
        if coop.door.mode == "stehen" or coop.door.mode == "warten" or now - away.since > DOOR_WALK_MAX then
            away.phase = "weg"
            coop.door:release()
        end
        return
    end
    -- versteckt: an der Stelle unter den Boden, wo er zuletzt stand
    if not away.hide then
        local p = game.read_state(game.partner_object())
        if not p then
            return
        end
        away.hide = { x = p.x, y = p.y, z = p.z }
    end
    game.hide_partner(away.hide.x, away.hide.y, away.hide.z)
end

-- Partner wieder sichtbar machen: an die Position des Mitspielers, falls er da
-- ist, sonst neben die eigene Figur (z. B. Verbindung weg)
local function end_away(target)
    local away = coop.away
    coop.away = nil
    coop.door:release()
    if not away or away.phase ~= "weg" or not away.hide then
        return
    end
    local ls = coop.local_state
    target = target or (ls and { x = ls.x + 60, y = ls.y, z = ls.z })
    if target then
        game.place_partner({ x = target.x, y = target.y, z = target.z, qx = target.qx, qy = target.qy,
            qz = target.qz, qw = target.qw })
    end
end

local function coop_frame(now)
    coop.local_state = game.get_local_state()
    local ls = coop.local_state
    local area = ls and ls.area
    if ls and area ~= coop.local_area then
        -- Eigener Raumwechsel: Koordinaten der alten Spuren passen nicht mehr
        coop.local_area = area
        coop.puppet:reset()
        coop.solo:reset()
    end

    if ls and session:is_active() and #session:ready_peers() > 0 and now - coop.last_send >= SEND_INTERVAL then
        coop.last_send = now
        coop.seq = (coop.seq + 1) % 4294967296
        session:send("PLAYER_STATE", {
            seq = coop.seq, area = area or "", x = ls.x, y = ls.y, z = ls.z,
            qx = ls.qx, qy = ls.qy, qz = ls.qz, qw = ls.qw, character = ls.character, flags = 0,
        }, false)
    end

    local remote_fresh = coop.remote ~= nil and now - coop.remote_time < REMOTE_TIMEOUT
    coop.same_character = remote_fresh and ls ~= nil and coop.remote.character ~= 0
        and coop.remote.character == ls.character
    coop.same_room = nil
    if remote_fresh then
        coop.same_room = game.same_room(area, coop.remote.area)
    end

    auto_switch_frame(now)

    if coop.solo_active then
        if coop.away then
            end_away(nil)
        end
        coop.puppet:release()
        coop.solo:push(ls, now)
        coop.solo:update(now)
    elseif config.puppet and remote_fresh and not coop.same_character and coop.same_room == false then
        coop.solo:release()
        coop.puppet:release()
        away_frame(now)
    elseif config.puppet and remote_fresh and not coop.same_character then
        coop.solo:release()
        if coop.away then
            end_away(coop.remote) -- wieder im selben Raum: am Mitspieler auftauchen
        end
        coop.puppet:update(now)
    else
        coop.solo:release()
        coop.puppet:release()
        if coop.away then
            end_away(nil) -- Koop aus oder Verbindung weg: Partner zurueck neben mich
        end
    end
end

-- --- Join auf den Spielstand des Hosts ---------------------------------------
--
-- Der Mitspieler fragt den Spielstand an (SAVE_REQUEST). Der Host schickt seinen
-- zuletzt geladenen bzw. gespeicherten Platz. Die Mod legt ihn beim Mitspieler in
-- config.join_slot und haelt ihn dort, bis er geladen ist: Das Spiel liest beim
-- Laden die Datei neu ein, deshalb wird der Platz nach jedem Einlesen erneut
-- geschrieben (im Spiel bestaetigt am 3. November 2026).

local join = {
    state = "idle",   -- idle, waiting, receiving, holding, done, error
    text = "",
    receiver = nil,
    data = nil,
    seen_title = false, -- schon im Titel/Ladebildschirm gewesen (keine Figur)?
    transfer = 0,
}

local function join_fail(text)
    join.state, join.text, join.receiver, join.data = "error", text, nil, nil
    session:log("Spielstand: %s", text)
end

session:on("SAVE_REQUEST", function(s, peer)
    local slot = game.current_save_slot()
    local data = slot and game.read_save_slot(slot)
    join.transfer = (join.transfer + 1) % 4294967296
    if not data then
        s:send("SAVE_BEGIN", { transfer = join.transfer, size = 0, chunks = 0, checksum = 0,
            info = "Der Host hat noch keinen Spielstand geladen oder gespeichert." }, true, peer.id)
        s:log("Spielstand angefragt, aber kein Platz geladen")
        return
    end
    local info = string.format("Platz %d, %s", slot + 1, game.describe_save(data))
    local begin, chunks = savesync.split(data, join.transfer, info)
    s:send("SAVE_BEGIN", begin, true, peer.id)
    for _, chunk in ipairs(chunks) do
        s:send("SAVE_CHUNK", chunk, true, peer.id)
    end
    s:log("Spielstand an %s geschickt (%s)", peer.name or "?", info)
end)

session:on("SAVE_BEGIN", function(s, peer, msg)
    if join.state ~= "waiting" then
        return
    end
    if msg.size == 0 then
        join_fail(msg.info)
        return
    end
    if msg.size ~= game.SAVE_SLOT_SIZE then
        join_fail(string.format("Spielstand hat falsche Groesse (%d Bytes) - andere Spielversion?", msg.size))
        return
    end
    join.receiver = savesync.receiver(msg)
    join.state, join.text = "receiving", msg.info
end)

session:on("SAVE_CHUNK", function(s, peer, msg)
    if join.state ~= "receiving" or not join.receiver:add(msg) or not join.receiver:complete() then
        return
    end
    local data, err = join.receiver:result()
    if not data then
        join_fail("Uebertragung fehlerhaft: " .. err)
        return
    end
    join.data, join.receiver = data, nil
    join.state, join.seen_title = "holding", false
    s:log("Spielstand empfangen (%s), liegt in Platz %d", join.text, config.join_slot)
end)

local function join_request()
    if not mem.write_bytes then
        join_fail("Die Runtime ist zu alt (ab 0.4.0) - bitte ueber den Mod-Manager aktualisieren.")
        return
    end
    join.state, join.text, join.data = "waiting", "", nil
    session:send("SAVE_REQUEST", {}, true)
end

-- Jeden Frame: empfangenen Spielstand im Platz halten, bis er geladen ist
local function join_frame()
    if join.state ~= "holding" then
        return
    end
    local slot = config.join_slot - 1
    if not game.save_slot_matches(slot, join.data) then
        game.write_save_slot(slot, join.data)
    end
    if coop.local_state == nil then
        join.seen_title = true
    elseif join.seen_title and game.current_save_slot() == slot then
        join.state, join.data = "done", nil
        session:log("Spielstand des Hosts geladen")
    end
end

local last_error = nil
local function report_error(text)
    if text ~= last_error then -- jede Meldung nur einmal
        last_error = text
        session:log("FEHLER: %s", text)
    end
end

devconsole.enabled = config.devconsole

re.on_frame(function()
    local now = session:time()
    devconsole.update(now)
    local ok, err = pcall(session.update, session)
    if not ok then
        report_error(tostring(err))
    end
    ok, err = pcall(coop_frame, now)
    if not ok then
        report_error("Koop: " .. tostring(err))
        coop.puppet:release()
        coop.solo:release()
    end
    ok, err = pcall(join_frame)
    if not ok then
        report_error("Spielstand: " .. tostring(err))
    end
end)

-- --- Menue ---------------------------------------------------------------

local ui = {
    chat = "",
    expr = "re0hd.exe+0",
    type = "u32",
    watch_name = "",
    diag_label = "",
    diag_result = nil,
}

local MODE_TEXT = {
    idle = "Nicht verbunden",
    hosting = "Host - warte auf Mitspieler",
    connecting = "Verbinde ...",
    connected = "Verbunden",
}

local function draw_connection_ui(status)
    local changed
    changed, config.name = imgui.input_text("Dein Name", config.name)
    if changed then
        session.name = config.name
        save_config()
    end

    if status.mode == "idle" then
        changed, config.address = imgui.input_text("IP des Hosts", config.address)
        if changed then save_config() end

        local port_text
        changed, port_text = imgui.input_text("Port", tostring(config.port))
        if changed then
            local port = tonumber(port_text)
            if port and port >= 1 and port <= 65535 then
                config.port = math.floor(port)
                save_config()
            end
        end

        if imgui.button("Hosten") then
            session:host(config.port)
        end
        imgui.same_line()
        if imgui.button("Beitreten") then
            session:join(config.address, config.port)
        end
    elseif imgui.button("Trennen") then
        session:leave()
    end
end

local function draw_status_ui(status)
    local text = MODE_TEXT[status.mode] or status.mode
    if status.mode == "hosting" then
        text = text .. string.format(" (Port %d)", config.port)
    end
    imgui.text("Status: " .. text)
    if status.error then
        imgui.text_colored("Letzter Fehler: " .. status.error, 0xFF4040FF)
    end

    for _, peer in ipairs(status.peers or {}) do
        local p = session.peers[peer.id]
        local name = p and p.name or "(Handshake ...)"
        if p and p.incompatible then
            name = name .. " - INKOMPATIBEL, siehe Log"
        end
        imgui.text(string.format("  Mitspieler: %s  [%s]  Ping %d ms", name, peer.address, peer.rtt))
    end

    if session:is_active() then
        local changed
        changed, ui.chat = imgui.input_text("Nachricht", ui.chat)
        imgui.same_line()
        if imgui.button("Senden") and ui.chat ~= "" then
            session:send("CHAT", { text = ui.chat }, true)
            session:log("Du: %s", ui.chat)
            ui.chat = ""
        end
    end
end

local CHARACTER_NAMES = { [0] = "?", [1] = "Rebecca", [2] = "Billy" }

local function draw_coop_ui()
    if not game.supported then
        imgui.text_colored("Diese re0hd.exe-Version kennt die Mod noch nicht (Zeitstempel "
            .. string.format("0x%08X", remultiplayer.exe_timestamp) .. ") - Koop aus.", 0xFF4040FF)
        return
    end
    local ls = coop.local_state
    imgui.text("Du steuerst: " .. (ls and CHARACTER_NAMES[ls.character] or "(keine Figur - Menue/Ladebildschirm?)")
        .. "   Raum: " .. (coop.local_area or "?"))
    if coop.remote then
        local age = session:time() - coop.remote_time
        local remote_area = coop.remote.area ~= "" and coop.remote.area or "?"
        imgui.text(string.format("Mitspieler steuert: %s   Raum: %s  (letzte Daten vor %.1f s)",
            CHARACTER_NAMES[coop.remote.character] or "?", remote_area, age))
    end
    if coop.same_room == false then
        imgui.text("Ihr seid in verschiedenen Raeumen - dein Partner ist ausgeblendet ("
            .. (coop.away and coop.away.phase == "tuer" and "geht zur Tuer" or "weg") .. ").")
    end
    if coop.same_character then
        if config.auto_switch and not session.is_host then
            imgui.text_colored("Ihr steuert beide dieselbe Figur - die Mod wechselt automatisch (V).", 0xFF40E0FF)
        else
            imgui.text_colored("Ihr steuert beide dieselbe Figur! Einer muss mit V die Figur wechseln.", 0xFF4040FF)
        end
    end

    local changed
    changed, config.puppet = imgui.checkbox("Mitspieler steuert meinen Partner", config.puppet)
    if changed then save_config() end
    changed, config.auto_switch = imgui.checkbox("Als Mitspieler automatisch die andere Figur nehmen", config.auto_switch)
    if changed then save_config() end
    if config.puppet and coop.remote then
        local net = coop.puppet.net
        imgui.text(string.format("  Partner: %s, Abstand %s", coop.puppet.mode,
            coop.puppet.dist and string.format("%.0f", coop.puppet.dist) or "-"))
        imgui.text(string.format("  Netz: Paket alle %s ms, Schwankung %.0f ms, Puffer %.0f ms",
            net.interval and string.format("%.0f", net.interval * 1000) or "-", net.jitter * 1000,
            coop.puppet:delay() * 1000))
    end

    changed, coop.solo_active = imgui.checkbox("Spur-Test allein (Partner laeuft dir mit 2 s Abstand nach)", coop.solo_active)
    if changed and not coop.solo_active then
        coop.solo:reset()
    end
    if coop.solo_active then
        imgui.text(string.format("  Partner: %s, Abstand %s", coop.solo.mode,
            coop.solo.dist and string.format("%.0f", coop.solo.dist) or "-"))
    end
end

local function draw_join_ui()
    if not game.supported then
        return
    end
    imgui.text("Spielstand des Hosts (Join):")
    if not session:is_active() or #session:ready_peers() == 0 then
        imgui.text("  Erst verbinden. Der Host schickt seinen zuletzt geladenen bzw. gespeicherten Platz.")
    elseif join.state == "idle" or join.state == "done" or join.state == "error" then
        if imgui.button("Spielstand vom Host holen") then
            join_request()
        end
        imgui.same_line()
        imgui.text(string.format("(kommt in Platz %d)", config.join_slot))
    end
    local changed, text = imgui.input_text("Platz fuer den Host-Spielstand (1-20)", tostring(config.join_slot))
    if changed then
        local n = tonumber(text)
        if n and n >= 1 and n <= game.SAVE_SLOTS then
            config.join_slot = math.floor(n)
            save_config()
        end
    end
    if join.state == "waiting" then
        imgui.text("  Warte auf den Host ...")
    elseif join.state == "receiving" then
        imgui.text(string.format("  Empfange %s: %d von %d", join.text, join.receiver.count, join.receiver.begin.chunks))
    elseif join.state == "holding" then
        imgui.text_colored(string.format("  Empfangen: %s", join.text), 0xFF40FF40)
        imgui.text(string.format("  Jetzt: Titelbildschirm -> Spiel laden -> Platz %d laden.", config.join_slot))
        imgui.text("  Der Platz wird nur im Speicher ersetzt. Speicherst du danach, landet er in deiner Spielstand-Datei.")
        if imgui.button("Abbrechen") then
            join.state, join.data = "idle", nil
        end
    elseif join.state == "done" then
        imgui.text_colored("  Spielstand des Hosts geladen.", 0xFF40FF40)
    elseif join.state == "error" then
        imgui.text_colored("  Fehler: " .. join.text, 0xFF4040FF)
    end
    local slot = game.current_save_slot()
    if slot then
        imgui.text(string.format("Dein aktueller Platz: %d (das schickst du als Host)", slot + 1))
    end
end

local function write_diag(status)
    local label = ui.diag_label:gsub("[^%w_%-]", "_")
    if label == "" then
        label = "ohne_name"
    end
    local file = "re0hd_diag_" .. label .. ".json"
    local data = {
        label = ui.diag_label,
        time = os.date("%Y-%m-%d %H:%M:%S"),
        runtime_version = remultiplayer.version,
        mod_version = MOD_VERSION,
        exe = {
            base = string.format("0x%08X", remultiplayer.exe_base),
            size = string.format("0x%X", remultiplayer.exe_size),
            timestamp = string.format("0x%08X", remultiplayer.exe_timestamp),
        },
        watches = memtool.snapshot(config.watches),
        coop_status = status,
    }
    local ok, err = json.dump_file(file, data)
    if ok then
        return true, "remultiplayer/data/" .. file
    end
    return false, tostring(err)
end

local function draw_memtool_ui()
    local changed
    changed, ui.expr = imgui.input_text("Adresse", ui.expr)
    imgui.text("Typ:")
    for _, t in ipairs(memtool.TYPES) do
        imgui.same_line()
        if imgui.button(t == ui.type and ("[" .. t .. "]") or t) then
            ui.type = t
        end
    end
    local v, err, addr = memtool.read(ui.expr, ui.type)
    if v ~= nil then
        imgui.text(string.format("0x%08X = %s", addr, memtool.format(v, ui.type)))
    else
        imgui.text_colored(tostring(err), 0xFF4040FF)
    end

    changed, ui.watch_name = imgui.input_text("Name", ui.watch_name)
    if imgui.button("Merken") then
        local name = ui.watch_name ~= "" and ui.watch_name or ui.expr
        table.insert(config.watches, { name = name, expr = ui.expr, type = ui.type })
        ui.watch_name = ""
        save_config()
    end

    local remove_index = nil
    for i, w in ipairs(config.watches) do
        if imgui.button("X##watch" .. i) then
            remove_index = i
        end
        imgui.same_line()
        imgui.text(memtool.describe(w))
    end
    if remove_index then
        table.remove(config.watches, remove_index)
        save_config()
    end

    imgui.separator()
    changed, ui.diag_label = imgui.input_text("Situation (z. B. rebecca_zug)", ui.diag_label)
    if imgui.button("Diagnose speichern") then
        local ok, result = write_diag(session:status())
        ui.diag_result = ok and ("Gespeichert: " .. result) or ("Fehler: " .. result)
    end
    if ui.diag_result then
        imgui.text(ui.diag_result)
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("RE0 Koop") then
        return
    end
    local ok, err = pcall(function()
        local status = session:status()
        draw_connection_ui(status)
        imgui.separator()
        draw_status_ui(status)
        imgui.separator()
        draw_coop_ui()
        imgui.separator()
        draw_join_ui()
        imgui.separator()

        local changed
        changed, config.devconsole = imgui.checkbox("Entwickler-Konsole fuer Claude", config.devconsole)
        if changed then
            devconsole.enabled = config.devconsole
            save_config()
        end
        imgui.same_line()
        imgui.text("(" .. devconsole.status_text() .. ")")

        if explorer and imgui.tree_node("MT-Explorer (Forschung)") then
            explorer.draw()
            imgui.tree_pop()
        end

        if imgui.tree_node("Speicher-Werkzeug (Forschung)") then
            draw_memtool_ui()
            imgui.tree_pop()
        end

        if imgui.tree_node("Log") then
            for i = math.max(1, #session.log_lines - 25), #session.log_lines do
                imgui.text(session.log_lines[i])
            end
            imgui.tree_pop()
        end
        imgui.text("coopnet " .. coopnet.version() .. "   Mod " .. MOD_VERSION)
    end)
    if not ok then
        imgui.text_colored("UI-Fehler: " .. tostring(err), 0xFF4040FF)
    end
    imgui.tree_pop()
end)

session:log("RE0 Koop %s geladen (coopnet %s, Runtime %s)", MOD_VERSION, coopnet.version(), remultiplayer.version)
