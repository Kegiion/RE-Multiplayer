-- RE2 Remake Koop (RE:Multiplayer) - Einstiegspunkt
--
-- Wird von REFramework automatisch geladen (reframework/autorun/).
-- Menue: REFramework-Overlay (Taste Einfg/Insert) -> Script Generated UI -> "RE2 Koop".
--
-- Aufbau:
--   remultiplayer_coop/*      gemeinsame Lua-Bibliothek fuer alle RE-Engine-Spiele
--   re2r_coop/game.lua RE2-spezifischer Zugriff auf Spieldaten
--   re2r_coop/ghost.lua Anzeige des Mitspielers (Markierung)
--   re2r_coop/puppet.lua Mitspieler als Spielfigur (Meilenstein 2)
--   re2r_coop/anim.lua Animationen lesen und auf die Puppe uebertragen
--   re2r_coop/partner.lua VERSUCH: Mitspieler als echte zweite Spielfigur
--   re2r_coop/remote_input.lua Eingaben fuer die echte zweite Spielfigur
--   re2r_coop/diag.lua Diagnose-Datei fuer die Entwicklung
--   re2r_coop/devconsole.lua Entwickler-Konsole fuer Claude (standardmaessig aus)

local MOD_VERSION = "0.9.0"
local CONFIG_FILE = "re2r_coop_config.json"
local SEND_INTERVAL = 0.05 -- Sekunden -> 20 Positionsupdates pro Sekunde
local BANKS_CHECK_INTERVAL = 0.5 -- Sekunden: eigene Animationsdateien auf Aenderung pruefen
local BANKS_RESEND_INTERVAL = 3.0 -- Sekunden: ANIM_BANKS zur Sicherheit wiederholen
local INPUT_INTERVAL = 1 / 60 -- Sekunden: eigene Eingaben bis 60x pro Sekunde senden

-- Ohne Plugin geht nichts: nur eine Hilfe im Menue anzeigen.
if coopnet == nil then
    re.on_draw_ui(function()
        if imgui.tree_node("RE2 Koop") then
            imgui.text_colored("Plugin remultiplayer_coopnet.dll nicht gefunden!", 0xFF4040FF)
            imgui.text("Es gehoert nach: <RE2-Ordner>/reframework/plugins/")
            imgui.text("Danach das Spiel neu starten.")
            imgui.tree_pop()
        end
    end)
    return
end

local Session = require("remultiplayer_coop.session")
local game = require("re2r_coop.game")
local ghost = require("re2r_coop.ghost")
local puppet = require("re2r_coop.puppet")
local anim = require("re2r_coop.anim")
local weapon = require("re2r_coop.weapon")
local partner = require("re2r_coop.partner")
local remote_input = require("re2r_coop.remote_input")
local savejoin = require("re2r_coop.savejoin")
local diag = require("re2r_coop.diag")
local devconsole = require("re2r_coop.devconsole")

ghost.character_name = game.character_name

-- --- Einstellungen ---------------------------------------------------------

local config = {
    name = "Spieler",
    address = "127.0.0.1",
    port = 27350,
    show_ghosts = true,
    show_puppets = true, -- Mitspieler als Spielfigur
    real_partner = false, -- VERSUCH: Mitspieler als echte, steuerbare Spielfigur
    show_debug = false,
    devconsole = false, -- Entwickler-Konsole fuer Claude
    auto_join = true, -- beim Beitreten automatisch den Spielstand des Hosts laden
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
devconsole.enabled = config.devconsole

-- --- Sitzung -----------------------------------------------------------

local session = Session.new({
    net = coopnet,
    game = game.ID,
    mod_version = MOD_VERSION,
    name = config.name,
    max_peers = 1, -- Story-Koop: zwei Spieler
})

session:on("PLAYER_STATE", function(s, peer, msg)
    ghost.on_state(peer, msg, s:time())
end)

-- remote_anim[peer_id] = { banks=, banks_id=, state=, seq= }
local remote_anim = {}

local function seq_newer(seq, last)
    if last == nil then
        return true
    end
    local diff = (seq - last) % 4294967296
    return diff ~= 0 and diff < 2147483648
end

session:on("ANIM_BANKS", function(_, peer, msg)
    local a = remote_anim[peer.id] or {}
    remote_anim[peer.id] = a
    a.banks, a.banks_id = anim.banks_from_msg(msg), msg.banks_id
    a.weapon = weapon.from_msg(msg)
end)

session:on("ANIM_STATE", function(_, peer, msg)
    local a = remote_anim[peer.id] or {}
    remote_anim[peer.id] = a
    if seq_newer(msg.seq, a.seq) then
        a.seq, a.state = msg.seq, msg
    end
end)

local remote_input_seq = {}

session:on("INPUT_STATE", function(_, peer, msg)
    if seq_newer(msg.seq, remote_input_seq[peer.id]) then
        remote_input_seq[peer.id] = msg.seq
        if partner.has(peer.id) then
            remote_input.receive(msg)
        end
    end
end)

-- Join auf den Spielstand des Hosts (re2r_coop/savejoin.lua)
-- Beantwortet wird jede Anfrage (normal fragt nur der Freund beim Host an,
-- der Testbot-Spiegel fragt aber auch beim Spiel an, wenn es beitritt).
session:on("SAVE_REQUEST", function(s, peer)
    savejoin.on_request(s, peer)
end)

session:on("SAVE_BEGIN", function(s, _, msg)
    savejoin.on_begin(s, msg)
end)

session:on("SAVE_CHUNK", function(s, _, msg)
    savejoin.on_chunk(s, msg)
end)

session:on("CHAT", function(s, peer, msg)
    s:log("%s: %s", peer.name or "?", msg.text)
end)

session:subscribe("peer_left", function(_, peer)
    ghost.remove(peer.id)
    puppet.remove(peer.id)
    partner.remove(peer.id)
    remote_anim[peer.id] = nil
    remote_input_seq[peer.id] = nil
    savejoin.forget_peer(peer.id)
end)

-- Lade-Hook fuer den Join (nur im Spiel, sdk.hook)
pcall(savejoin.install_hook)
savejoin.auto = config.auto_join

-- Wer beitritt, holt sich automatisch den Spielstand des Hosts.
session:subscribe("peer_joined", function(s)
    if not s.is_host and config.auto_join and savejoin.state ~= "ready" then
        savejoin.request(s)
    end
end)

-- Bei "Reset Scripts" bleiben erzeugte Figuren sonst verwaist in der Welt.
if re.on_script_reset then
    re.on_script_reset(function()
        puppet.clear()
        partner.clear()
    end)
end

-- --- Pro Frame -----------------------------------------------------------

local state = {
    seq = 0,
    last_send = 0,
    last_frame = nil,
    local_state = nil,
    last_error = nil,
    -- eigene Animationsdateien
    banks = nil,
    banks_key = nil,
    banks_id = os.time() % 65536, -- Startwert zufaellig, damit ein Reset nicht alte IDs wiederholt
    banks_checked = -math.huge,
    banks_sent = -math.huge,
    anim_tracker = {}, -- Neustarts der Aktions-Ebenen (anim.track)
    input_seq = 0,
    input_sent = -math.huge,
}

local function report_error(where, err)
    local text = where .. ": " .. tostring(err)
    if text ~= state.last_error then -- jede Meldung nur einmal loggen
        state.last_error = text
        session:log("FEHLER %s", text)
    end
end

-- Eigene Animationen senden: ANIM_BANKS bei Aenderung und regelmaessig,
-- ANIM_STATE zusammen mit PLAYER_STATE.
local function send_anim(now)
    local motion = anim.get_motion(game.get_player())
    if motion == nil then
        return
    end
    if now - state.banks_checked >= BANKS_CHECK_INTERVAL then
        state.banks_checked = now
        local banks = anim.read_banks(motion)
        if banks ~= nil then
            banks.weapon = weapon.read(game.get_player())
        end
        local key = anim.banks_key(banks) .. "#" .. weapon.key(banks and banks.weapon)
        if banks ~= nil and key ~= state.banks_key then
            state.banks, state.banks_key = banks, key
            state.banks_id = (state.banks_id + 1) % 65536
            state.banks_sent = -math.huge
        end
    end
    if state.banks == nil then
        return
    end
    if now - state.banks_sent >= BANKS_RESEND_INTERVAL then
        state.banks_sent = now
        session:send("ANIM_BANKS", weapon.to_msg(state.banks.weapon, anim.banks_to_msg(state.banks, state.banks_id)), true)
    end
    local msg = anim.read_layers(motion, state.anim_tracker)
    msg.seq, msg.banks_id = state.seq, state.banks_id
    session:send("ANIM_STATE", msg, false)
end

local function frame()
    local now = session:time()
    local dt = state.last_frame and (now - state.last_frame) or 0
    state.last_frame = now

    session:update()
    savejoin.update(session)
    if not session.is_host then
        savejoin.update_auto(now)
    end

    state.local_state = game.get_local_state()

    -- Neustarts von Schuss/Nachladen jeden Frame erkennen (gesendet wird nur 20x/s).
    if state.local_state ~= nil and session:is_active() then
        local ok, err = pcall(function()
            local motion = anim.get_motion(game.get_player())
            if motion ~= nil then
                anim.track(motion, state.anim_tracker)
            end
        end)
        if not ok then
            report_error("anim.track", err)
        end
    end

    if state.local_state ~= nil and session:is_active() and #session:ready_peers() > 0
        and now - state.last_send >= SEND_INTERVAL then
        state.last_send = now
        state.seq = (state.seq + 1) % 4294967296
        local msg = state.local_state
        msg.seq = state.seq
        session:send("PLAYER_STATE", msg, false)
        local ok, err = pcall(send_anim, now)
        if not ok then
            report_error("anim", err)
        end
    end

    -- Eigene Eingaben senden (fuer die echte zweite Spielfigur beim Gegenueber).
    if state.local_state ~= nil and session:is_active() and #session:ready_peers() > 0
        and now - state.input_sent >= INPUT_INTERVAL then
        state.input_sent = now
        local ok, err = pcall(function()
            local msg = remote_input.read_local()
            if msg ~= nil then
                state.input_seq = (state.input_seq + 1) % 4294967296
                msg.seq = state.input_seq
                session:send("INPUT_STATE", msg, false)
            end
        end)
        if not ok then
            report_error("input", err)
        end
    end

    ghost.update(dt)
    for id, r in pairs(ghost.remote) do
        local present = state.local_state ~= nil and r.target ~= nil
            and not ghost.is_stale(r, now) and not ghost.other_area(r, state.local_state)
        local real = config.real_partner and present
        partner.sync(id, r, real, now)
        local visible = config.show_puppets and present and not partner.has(id)
        puppet.sync(id, r, visible, now, remote_anim[id])
    end
    if config.show_ghosts then
        ghost.draw(state.local_state, now)
    end
end

re.on_frame(function()
    local ok, err = pcall(devconsole.update, session:time())
    if not ok then
        report_error("devconsole", err)
    end
    ok, err = pcall(frame)
    if not ok then
        report_error("frame", err)
    end
end)

-- --- Menue ---------------------------------------------------------------

local ui = {
    chat = "",
    diag_result = nil,
    diag_label = "",
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
    else
        if imgui.button("Trennen") then
            session:leave()
            ghost.clear()
            puppet.clear()
            partner.clear()
            for id in pairs(remote_anim) do
                remote_anim[id] = nil
            end
        end
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

-- Join auf den Spielstand des Hosts (nur beim Freund, der beigetreten ist).
local function draw_join_ui(status)
    if status.mode ~= "connected" or session.is_host or #session:ready_peers() == 0 then
        return
    end
    imgui.separator()
    imgui.text("Spielstand des Hosts uebernehmen")
    local changed
    changed, config.auto_join = imgui.checkbox("Beim Beitreten automatisch laden", config.auto_join)
    if changed then
        savejoin.auto = config.auto_join
        save_config()
    end
    local st = savejoin.state
    if st == "idle" or st == "failed" or st == "applied" then
        if imgui.button("Spielstand des Hosts holen") then
            savejoin.request(session)
        end
    elseif st == "requested" or st == "receiving" then
        imgui.text(string.format("Empfange ... %d %%", math.floor(savejoin.progress() * 100)))
        imgui.same_line()
        if imgui.button("Abbrechen") then
            savejoin.cancel()
        end
    elseif st == "ready" then
        if imgui.button("Abbrechen") then
            savejoin.cancel()
        end
    end
    if savejoin.message ~= "" then
        imgui.text(savejoin.message)
    end
    if st == "ready" and not config.auto_join then
        imgui.text("Pause -> Spiel laden -> beliebiger Spielstand. Du landest beim Host.")
    end
end

local function draw_debug_ui(status)
    local changed
    changed, config.show_ghosts = imgui.checkbox("Mitspieler-Markierung anzeigen", config.show_ghosts)
    if changed then save_config() end
    changed, config.show_puppets = imgui.checkbox("Mitspieler als Spielfigur anzeigen", config.show_puppets)
    if changed then save_config() end
    changed, config.real_partner = imgui.checkbox("VERSUCH: Mitspieler als echte Spielfigur (vorher speichern!)", config.real_partner)
    if changed then save_config() end
    changed, config.show_debug = imgui.checkbox("Debug-Infos", config.show_debug)
    if changed then save_config() end

    changed, config.devconsole = imgui.checkbox("Entwickler-Konsole fuer Claude", config.devconsole)
    if changed then
        devconsole.enabled = config.devconsole
        save_config()
    end
    imgui.same_line()
    imgui.text("(" .. devconsole.status_text() .. ")")

    changed, ui.diag_label = imgui.input_text("Situation (z. B. hauptmenue)", ui.diag_label)
    if imgui.button("Diagnose speichern") then
        local ok, result = diag.write({ coop_status = status, mod_version = MOD_VERSION }, ui.diag_label)
        ui.diag_result = ok and ("Gespeichert: " .. result) or ("Fehler: " .. result)
    end
    if not coopnet.find_types then
        imgui.text("(Erweiterte Klassensuche nicht verfuegbar - altes Plugin?)")
    end
    if ui.diag_result then
        imgui.text(ui.diag_result)
    end

    if config.show_debug then
        local ls = state.local_state
        if ls then
            imgui.text(string.format("Spieler: %s  via %s", tostring(ls.object_name), tostring(game.player_source)))
            imgui.text(string.format("Position: %.2f  %.2f  %.2f", ls.x, ls.y, ls.z))
            imgui.text(string.format("Rotation: %.3f  %.3f  %.3f  %.3f", ls.qx, ls.qy, ls.qz, ls.qw))
            local c = ls.condition
            if c then
                imgui.text(string.format("Figur: %s (%s, %s)", game.character_name(ls.character), c.survivor_name, tostring(c.survivor_type)))
                imgui.text(string.format("Bereich (Scene): %s (%s)", c.scene_area_name, tostring(c.scene_area_id)))
                imgui.text(string.format("Bereich (Space): %s (%s)", c.space_area_name, tostring(c.space_area_id)))
                imgui.text(string.format("Map-Area: %s (%s)", c.map_area_name, tostring(c.map_area)))
            else
                imgui.text("PlayerCondition: nicht gefunden")
            end
        else
            imgui.text("Spieler: nicht gefunden (Menue/Ladebildschirm?)")
        end
        for id, r in pairs(ghost.remote) do
            imgui.text(string.format("Remote %d (%s): %.2f %.2f %.2f  seq %d  Figur %s  Bereich %s",
                id, tostring(r.name), r.pos.x, r.pos.y, r.pos.z, r.seq or 0,
                game.character_name(r.character), tostring(r.area)))
            imgui.text("  Figur im Spiel: " .. puppet.status_text(id))
            imgui.text("  Echte Figur: " .. partner.status_text(id))
        end
        local st = status.stats or {}
        imgui.text(string.format("Gesendet: %d Nachr. / %d B   Empfangen: %d Nachr. / %d B",
            st.messages_sent or 0, st.bytes_sent or 0, st.messages_received or 0, st.bytes_received or 0))
        imgui.text("coopnet " .. coopnet.version() .. "   Mod " .. MOD_VERSION)
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("RE2 Koop") then
        return
    end
    local ok, err = pcall(function()
        local status = session:status()
        draw_connection_ui(status)
        imgui.separator()
        draw_status_ui(status)
        draw_join_ui(status)
        imgui.separator()
        draw_debug_ui(status)

        if imgui.tree_node("Log") then
            for i = math.max(1, #session.log_lines - 25), #session.log_lines do
                imgui.text(session.log_lines[i])
            end
            imgui.tree_pop()
        end
    end)
    if not ok then
        imgui.text_colored("UI-Fehler: " .. tostring(err), 0xFF4040FF)
    end
    imgui.tree_pop()
end)

session:log("RE2 Koop %s geladen (coopnet %s)", MOD_VERSION, coopnet.version())
