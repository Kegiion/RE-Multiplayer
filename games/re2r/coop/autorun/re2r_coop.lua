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

local MOD_VERSION = "0.11.6"
local CONFIG_FILE = "re2r_coop_config.json"
local SEND_INTERVAL = 0.05 -- Sekunden -> 20 Positionsupdates pro Sekunde
local BANKS_CHECK_INTERVAL = 0.5 -- Sekunden: eigene Animationsdateien auf Aenderung pruefen
local BANKS_RESEND_INTERVAL = 3.0 -- Sekunden: ANIM_BANKS zur Sicherheit wiederholen
local INPUT_INTERVAL = 1 / 60 -- Sekunden: eigene Eingaben bis 60x pro Sekunde senden

local i18n = require("remultiplayer_coop.i18n")
local tr = require("re2r_coop.text")
local MENU_ID = "##re2r_coop" -- feste imgui-ID, damit ein Sprachwechsel das Menue nicht zuklappt

-- Ohne Plugin geht nichts: nur eine Hilfe im Menue anzeigen.
if coopnet == nil then
    local ok, data = pcall(json.load_file, CONFIG_FILE)
    if ok and type(data) == "table" and type(data.language) == "string" then
        i18n.set_setting(data.language)
    end
    re.on_draw_ui(function()
        if imgui.tree_node(tr("re2r.menu_title") .. MENU_ID) then
            imgui.text_colored(tr("re2r.plugin_missing"), 0xFF4040FF)
            imgui.text(tr("re2r.plugin_where"))
            imgui.text(tr("re2r.plugin_restart"))
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
local titlemenu = require("re2r_coop.titlemenu")
local diag = require("re2r_coop.diag")
local devconsole = require("re2r_coop.devconsole")

ghost.character_name = game.character_name

-- --- Einstellungen ---------------------------------------------------------

local config = {
    name = "", -- leer = Standardname der Sprache (conn.default_name)
    address = "127.0.0.1",
    port = 27350,
    show_ghosts = true,
    show_puppets = true, -- Mitspieler als Spielfigur
    real_partner = false, -- VERSUCH: Mitspieler als echte, steuerbare Spielfigur
    show_debug = false,
    devconsole = false, -- Entwickler-Konsole fuer Claude
    auto_join = true, -- beim Beitreten automatisch den Spielstand des Hosts laden
    title_window = true, -- Multiplayer-Fenster im Titelbildschirm
    language = "auto", -- "auto" (Spielsprache), "de", "en", ...
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

-- Sprache: Einstellung aus der Konfiguration, "Automatisch" fragt das Spiel.
i18n.set_game_language_getter(game.get_game_language)
if not i18n.set_setting(config.language) then
    config.language = "auto"
    i18n.set_setting("auto")
end
if config.name == "" then
    config.name = tr("conn.default_name")
end

-- Reihenfolge im Umschalter: Automatisch, dann alle Sprachen.
local function language_choices()
    local list = { { code = "auto", name = tr("lang.auto") } }
    for _, l in ipairs(i18n.languages()) do
        list[#list + 1] = l
    end
    return list
end

local function set_language(code)
    if i18n.set_setting(code) then
        config.language = code
        save_config()
    end
end

local function f2(v) return string.format("%.2f", v) end
local function f3(v) return string.format("%.3f", v) end

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

-- Host hat gespeichert: Mitspieler sichert Inventar und Kiste (Game Over)
session:on("HOST_SAVED", function(s)
    if not s.is_host then
        pcall(savejoin.on_host_saved, s)
    end
end)

session:on("CHAT", function(s, peer, msg)
    s:logt("chat.line", { name = peer.name or "?", text = msg.text })
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
-- Eintrag "Multiplayer" im Hauptmenue des Titelbildschirms
pcall(titlemenu.install)

-- Zeilen des Untermenues "Multiplayer" im Titelbildschirm (Spielstil).
local function peer_name()
    for _, p in pairs(session.peers) do
        if p.ready then
            return p.name or tr("tm.partner")
        end
    end
    return nil
end

titlemenu.rows = function()
    local st = session:status()
    local rows = {}
    if st.mode == "idle" then
        rows[#rows + 1] = { id = "host", label = tr("tm.host"),
            help = tr("tm.host_help", { port = config.port }) }
        rows[#rows + 1] = { id = "join", label = tr("tm.join"),
            help = tr("tm.join_help") }
        rows[#rows + 1] = { id = "address", edit = "address", label = tr("tm.address", { value = config.address }),
            label_edit = function(b) return tr("tm.address", { value = b .. "_" }) end,
            help = tr("tm.address_help") }
        rows[#rows + 1] = { id = "name", edit = "name", label = tr("tm.name", { value = config.name }),
            label_edit = function(b) return tr("tm.name", { value = b .. "_" }) end,
            help = tr("tm.name_help") }
    elseif st.mode == "hosting" then
        local friend = peer_name()
        rows[#rows + 1] = { id = "status",
            label = friend and tr("tm.friend_connected", { name = friend }) or tr("tm.waiting"),
            help = friend and tr("tm.load_now_help") or tr("tm.give_ip_help", { port = config.port }) }
        rows[#rows + 1] = { id = "leave", label = tr("tm.stop_hosting"), help = tr("tm.stop_hosting_help") }
    elseif st.mode == "connecting" then
        rows[#rows + 1] = { id = "status", label = tr("tm.connecting", { address = config.address }), help = tr("tm.moment") }
        rows[#rows + 1] = { id = "leave", label = tr("tm.cancel"), help = "" }
    else
        local host = peer_name()
        local text = savejoin.message ~= "" and savejoin.text() or tr("tm.fetching")
        if savejoin.state == "receiving" then
            text = tr("tm.receiving", { percent = math.floor(savejoin.progress() * 100) })
        end
        rows[#rows + 1] = { id = "status", label = host and tr("tm.connected_with", { name = host }) or tr("tm.connected"), help = text }
        rows[#rows + 1] = { id = "leave", label = tr("tm.disconnect"), help = "" }
    end
    rows[#rows + 1] = { id = "back", label = tr("tm.back"), help = tr("tm.back_help") }
    return rows
end

titlemenu.on_action = function(id)
    if id == "host" then
        session:host(config.port)
    elseif id == "join" then
        session:join(config.address, config.port)
    elseif id == "leave" then
        session:leave()
    end
end

titlemenu.get_field = function(name)
    return config[name]
end

titlemenu.set_field = function(name, value)
    value = value:match("^%s*(.-)%s*$")
    if value == "" then
        return
    end
    config[name] = value
    if name == "name" then
        session.name = value
    end
    save_config()
end
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
        session:logt("re2r.error_log", { text = text })
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
        local own = state.local_state and state.local_state.character
        r.figure = partner.figure_for(r.character, own, session.is_host)
        partner.sync(id, r, real, now)
        local visible = config.show_puppets and present and not partner.has(id)
        puppet.sync(id, r, visible, now, remote_anim[id])
    end
    if config.show_ghosts then
        ghost.draw(state.local_state, now)
    end
end

local draw_title_window -- Titel-Fenster, weiter unten

re.on_frame(function()
    local ok, err = pcall(devconsole.update, session:time())
    if not ok then
        report_error("devconsole", err)
    end
    ok, err = pcall(frame)
    if not ok then
        report_error("frame", err)
    end
    ok, err = pcall(draw_title_window)
    if not ok then
        report_error("titelfenster", err)
    end
end)

-- --- Menue ---------------------------------------------------------------

local ui = {
    chat = "",
    diag_result = nil,
    diag_label = "",
}

-- Anzeigetext fuer status.mode (idle, hosting, connecting, connected)
local function mode_text(status)
    local text = tr("status." .. tostring(status.mode))
    if status.mode == "hosting" then
        text = text .. tr("status.port_suffix", { port = config.port })
    end
    return text
end

-- Umschalter fuer die Sprache (imgui.combo, Liste ab 1).
local function draw_language_ui()
    if not imgui.combo then
        return
    end
    local list = language_choices()
    local names, current = {}, 1
    for i, l in ipairs(list) do
        names[i] = l.name
        if l.code == config.language then
            current = i
        end
    end
    local changed, index = imgui.combo(tr("lang.label") .. "##language", current, names)
    if changed and list[index] then
        set_language(list[index].code)
    end
end

local function draw_connection_ui(status)
    local changed
    changed, config.name = imgui.input_text(tr("conn.name") .. "##name", config.name)
    if changed then
        session.name = config.name
        save_config()
    end

    if status.mode == "idle" then
        changed, config.address = imgui.input_text(tr("conn.address") .. "##address", config.address)
        if changed then save_config() end

        local port_text
        changed, port_text = imgui.input_text(tr("conn.port") .. "##port", tostring(config.port))
        if changed then
            local port = tonumber(port_text)
            if port and port >= 1 and port <= 65535 then
                config.port = math.floor(port)
                save_config()
            end
        end

        if imgui.button(tr("conn.host")) then
            session:host(config.port)
        end
        imgui.same_line()
        if imgui.button(tr("conn.join")) then
            session:join(config.address, config.port)
        end
    else
        if imgui.button(tr("conn.disconnect")) then
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
    imgui.text(tr("status.line", { text = mode_text(status) }))
    if status.error then
        imgui.text_colored(tr("status.last_error", { error = status.error }), 0xFF4040FF)
    end

    for _, peer in ipairs(status.peers or {}) do
        local p = session.peers[peer.id]
        local name = p and p.name or tr("status.handshake")
        if p and p.incompatible then
            name = tr("status.incompatible", { name = name })
        end
        imgui.text(tr("status.peer_line", { name = name, address = peer.address, ms = peer.rtt }))
    end

    if session:is_active() then
        local changed
        changed, ui.chat = imgui.input_text(tr("chat.input") .. "##chat", ui.chat)
        imgui.same_line()
        if imgui.button(tr("chat.send")) and ui.chat ~= "" then
            session:send("CHAT", { text = ui.chat }, true)
            session:logt("chat.you", { text = ui.chat })
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
    imgui.text(tr("join.title"))
    local changed
    changed, config.auto_join = imgui.checkbox(tr("join.auto") .. "##auto_join", config.auto_join)
    if changed then
        savejoin.auto = config.auto_join
        save_config()
    end
    local st = savejoin.state
    if st == "idle" or st == "failed" or st == "applied" then
        if imgui.button(tr("join.fetch")) then
            savejoin.request(session)
        end
    elseif st == "requested" or st == "receiving" then
        imgui.text(tr("join.receiving", { percent = math.floor(savejoin.progress() * 100) }))
        imgui.same_line()
        if imgui.button(tr("ui.cancel")) then
            savejoin.cancel()
        end
    elseif st == "ready" then
        if imgui.button(tr("ui.cancel")) then
            savejoin.cancel()
        end
    end
    if savejoin.message ~= "" then
        imgui.text(savejoin.text())
    end
    if st == "ready" and not config.auto_join then
        imgui.text(tr("join.manual_hint"))
    end
end

-- --- Multiplayer-Fenster im Titelbildschirm ------------------------------
--
-- Wie bei RE0: Wer das Einfg-Menue nicht kennt, findet im Titelbildschirm
-- (MainState 3) unten rechts ein Fenster zum Hosten und Beitreten.
-- Bestaetigt am 4. November 2026: Das Fenster erscheint im Titelbildschirm.
-- UNBESTAETIGT: ob es bei geschlossenem Overlay Mausklicks bekommt.

local TITLE_WINDOW_FLAGS = 2 | 32 | 64 | 256 -- NoResize, NoCollapse, AlwaysAutoResize, NoSavedSettings
local GREEN = 0xFF60E060 -- ABGR
local YELLOW = 0xFF40E0FF
local GREY = 0xFFB0B0B0

draw_title_window = function()
    local main = savejoin.main_state()
    if titlemenu.installed then
        titlemenu.update(main)
    end
    if not config.title_window or main ~= savejoin.MAIN_TITLE then
        return
    end
    -- Mit Menueeintrag laeuft alles im Spielmenue (re2r_coop/titlemenu.lua),
    -- das Fenster ist nur der Ersatz, falls der Eintrag nicht klappt.
    if titlemenu.installed then
        return
    end
    local size = imgui.get_display_size and imgui.get_display_size()
    if size and imgui.set_next_window_pos then
        imgui.set_next_window_pos(Vector2f.new(size.x - 24, size.y - 24), 1, Vector2f.new(1, 1))
    end
    if not imgui.begin_window(tr("title.window") .. "###re2r_title", nil, TITLE_WINDOW_FLAGS) then
        imgui.end_window()
        return
    end
    -- end_window muss auch bei Fehlern im Inhalt kommen
    local ok, err = pcall(function()
        local status = session:status()
        draw_connection_ui(status)
        imgui.separator()
        imgui.text_colored(mode_text(status), status.mode == "connected" and GREEN or YELLOW)
        if status.error then
            imgui.text_colored(tr("status.error", { error = status.error }), 0xFF4040FF)
        end
        for _, peer in ipairs(status.peers or {}) do
            local p = session.peers[peer.id]
            imgui.text(tr("status.peer_short", { name = p and p.name or "...", ms = peer.rtt }))
        end
        if session.is_host and #session:ready_peers() > 0 then
            imgui.text(tr("title.host_hint"))
        end
        draw_join_ui(status)
        draw_language_ui()
        imgui.text_colored(tr("title.more_settings"), GREY)
    end)
    imgui.end_window()
    if not ok then
        error(err, 0)
    end
end

local function draw_debug_ui(status)
    local changed
    changed, config.show_ghosts = imgui.checkbox(tr("opt.show_ghosts") .. "##show_ghosts", config.show_ghosts)
    if changed then save_config() end
    changed, config.show_puppets = imgui.checkbox(tr("opt.show_puppets") .. "##show_puppets", config.show_puppets)
    if changed then save_config() end
    changed, config.real_partner = imgui.checkbox(tr("opt.real_partner") .. "##real_partner", config.real_partner)
    if changed then save_config() end
    changed, config.title_window = imgui.checkbox(tr("opt.title_window") .. "##title_window", config.title_window)
    if changed then save_config() end
    changed, config.show_debug = imgui.checkbox(tr("opt.show_debug") .. "##show_debug", config.show_debug)
    if changed then save_config() end

    changed, config.devconsole = imgui.checkbox(tr("opt.devconsole") .. "##devconsole", config.devconsole)
    if changed then
        devconsole.enabled = config.devconsole
        save_config()
    end
    imgui.same_line()
    imgui.text("(" .. devconsole.status_text() .. ")")

    changed, ui.diag_label = imgui.input_text(tr("diag.label") .. "##diag_label", ui.diag_label)
    if imgui.button(tr("diag.save")) then
        local ok, result = diag.write({ coop_status = status, mod_version = MOD_VERSION }, ui.diag_label)
        ui.diag_result = ok and tr("diag.saved", { file = result }) or tr("status.error", { error = result })
    end
    if not coopnet.find_types then
        imgui.text(tr("diag.no_find_types"))
    end
    if ui.diag_result then
        imgui.text(ui.diag_result)
    end

    if config.show_debug then
        imgui.text(tr("debug.titlemenu", { state = tr(titlemenu.installed and "debug.active" or "debug.console_off") })
            .. (titlemenu.error and (" - " .. tr(titlemenu.error)) or ""))
        local ls = state.local_state
        if ls then
            imgui.text(tr("debug.player", { name = tostring(ls.object_name), source = tostring(game.player_source) }))
            imgui.text(tr("debug.position", { x = f2(ls.x), y = f2(ls.y), z = f2(ls.z) }))
            imgui.text(tr("debug.rotation", { x = f3(ls.qx), y = f3(ls.qy), z = f3(ls.qz), w = f3(ls.qw) }))
            local c = ls.condition
            if c then
                imgui.text(tr("debug.character", { name = game.character_name(ls.character),
                    survivor = tostring(c.survivor_name), type = tostring(c.survivor_type) }))
                imgui.text(tr("debug.area_scene", { name = tostring(c.scene_area_name), id = tostring(c.scene_area_id) }))
                imgui.text(tr("debug.area_space", { name = tostring(c.space_area_name), id = tostring(c.space_area_id) }))
                imgui.text(tr("debug.map_area", { name = tostring(c.map_area_name), id = tostring(c.map_area) }))
            else
                imgui.text(tr("debug.no_condition"))
            end
        else
            imgui.text(tr("debug.no_player"))
        end
        for id, r in pairs(ghost.remote) do
            imgui.text(tr("debug.remote", { id = id, name = tostring(r.name), x = f2(r.pos.x), y = f2(r.pos.y), z = f2(r.pos.z),
                seq = r.seq or 0, character = game.character_name(r.character), area = tostring(r.area) }))
            imgui.text(tr("debug.remote_puppet", { text = puppet.status_text(id) }))
            imgui.text(tr("debug.remote_partner", { text = partner.status_text(id) }))
        end
        local st = status.stats or {}
        imgui.text(tr("debug.stats", { sent = st.messages_sent or 0, sent_bytes = st.bytes_sent or 0,
            received = st.messages_received or 0, received_bytes = st.bytes_received or 0 }))
        imgui.text(tr("debug.versions", { coopnet = coopnet.version(), mod = MOD_VERSION }))
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node(tr("re2r.menu_title") .. MENU_ID) then
        return
    end
    local ok, err = pcall(function()
        local status = session:status()
        draw_language_ui()
        draw_connection_ui(status)
        imgui.separator()
        draw_status_ui(status)
        draw_join_ui(status)
        imgui.separator()
        draw_debug_ui(status)

        if imgui.tree_node(tr("ui.log") .. "##log") then
            for i = math.max(1, #session.log_lines - 25), #session.log_lines do
                imgui.text(session.log_lines[i])
            end
            imgui.tree_pop()
        end
    end)
    if not ok then
        imgui.text_colored(tr("ui.error", { error = tostring(err) }), 0xFF4040FF)
    end
    imgui.tree_pop()
end)

session:logt("re2r.loaded", { version = MOD_VERSION, coopnet = coopnet.version() })
