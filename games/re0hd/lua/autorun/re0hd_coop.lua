-- RE0 HD Koop (RE:Multiplayer) - Einstiegspunkt
--
-- Wird von der RE:Multiplayer-Runtime automatisch geladen (remultiplayer/autorun/).
-- Menue: Taste Einfg oder F8 -> Abschnitt "RE0 Koop".
--
-- Aufbau:
--   remultiplayer_coop/*          gemeinsame Lua-Bibliothek (wie bei RE2)
--   re0hd_coop/game.lua    RE0-spezifischer Zugriff auf Spieldaten (Figuren, Kamera, Partner-Tasten)
--   re0hd_coop/puppet.lua  Partner als Puppe des Mitspielers (laeuft dessen Weg nach)
--   re0hd_coop/memtool.lua Speicher-Werkzeug fuer die Forschung
--   re0hd_coop/explorer.lua MT-Explorer: Klassen und Objekte der Engine (Forschung)
--   re0hd_coop/devconsole.lua Entwickler-Konsole fuer Claude (standardmaessig aus)

local MOD_VERSION = "0.5.0"
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

local SEND_INTERVAL = 0.05   -- 20 Positionsupdates pro Sekunde
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
    puppet = Puppet.new(game, { delay = 0.2 }),
    solo = Puppet.new(game, { delay = SOLO_DELAY }),
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
}

session:on("PLAYER_STATE", function(s, peer, msg)
    -- Veraltete (ueberholte) Pakete verwerfen; Ueberlauf der Nummer beachten
    if coop.remote_seq and ((msg.seq - coop.remote_seq) % 4294967296) > 2147483648 then
        return
    end
    coop.remote_seq = msg.seq
    if coop.remote and coop.remote.area ~= msg.area then
        coop.puppet:reset() -- Spur aus dem alten Raum gilt nicht mehr
    end
    coop.remote = msg
    coop.remote_time = s:time()
    coop.puppet:push(msg, s:time())
end)

session:subscribe("peer_left", function()
    coop.remote, coop.remote_seq = nil, nil
    coop.puppet:reset()
end)

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

    if coop.solo_active then
        coop.puppet:release()
        coop.solo:push(ls, now)
        coop.solo:update(now)
    elseif config.puppet and remote_fresh and not coop.same_character and coop.same_room ~= false then
        coop.solo:release()
        coop.puppet:update(now)
    else
        coop.solo:release()
        coop.puppet:release()
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
        imgui.text("Ihr seid in verschiedenen Raeumen - dein Partner folgt solange der Spiel-KI.")
    end
    if coop.same_character then
        imgui.text_colored("Ihr steuert beide dieselbe Figur! Einer muss mit V die Figur wechseln.", 0xFF4040FF)
    end

    local changed
    changed, config.puppet = imgui.checkbox("Mitspieler steuert meinen Partner", config.puppet)
    if changed then save_config() end
    if config.puppet and coop.remote then
        imgui.text(string.format("  Partner: %s, Abstand %s", coop.puppet.mode,
            coop.puppet.dist and string.format("%.0f", coop.puppet.dist) or "-"))
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
