-- RE0 HD Koop (REMods) - Einstiegspunkt
--
-- Wird von der REMods-Runtime automatisch geladen (remods/autorun/).
-- Menue: Taste Einfg oder F8 -> Abschnitt "RE0 Koop".
--
-- Aufbau:
--   remods_coop/*          gemeinsame Lua-Bibliothek (wie bei RE2)
--   re0hd_coop/game.lua    RE0-spezifischer Zugriff auf Spieldaten (noch leer)
--   re0hd_coop/memtool.lua Speicher-Werkzeug fuer die Forschung
--   re0hd_coop/explorer.lua MT-Explorer: Klassen und Objekte der Engine (Forschung)

local MOD_VERSION = "0.2.2"
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

local Session = require("remods_coop.session")
local game = require("re0hd_coop.game")
local memtool = require("re0hd_coop.memtool")
local explorer = mt and require("re0hd_coop.explorer") -- mt.* gibt es ab Runtime 0.2.0

-- --- Einstellungen ---------------------------------------------------------

local config = {
    name = "Spieler",
    address = "127.0.0.1",
    port = 27350,
    watches = {}, -- { {name=, expr=, type=}, ... } fuer das Speicher-Werkzeug
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

local last_error = nil

re.on_frame(function()
    local ok, err = pcall(session.update, session)
    if not ok and tostring(err) ~= last_error then
        last_error = tostring(err)
        session:log("FEHLER: %s", last_error)
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

local function write_diag(status)
    local label = ui.diag_label:gsub("[^%w_%-]", "_")
    if label == "" then
        label = "ohne_name"
    end
    local file = "re0hd_diag_" .. label .. ".json"
    local data = {
        label = ui.diag_label,
        time = os.date("%Y-%m-%d %H:%M:%S"),
        runtime_version = remods.version,
        mod_version = MOD_VERSION,
        exe = {
            base = string.format("0x%08X", remods.exe_base),
            size = string.format("0x%X", remods.exe_size),
            timestamp = string.format("0x%08X", remods.exe_timestamp),
        },
        watches = memtool.snapshot(config.watches),
        coop_status = status,
    }
    local ok, err = json.dump_file(file, data)
    if ok then
        return true, "remods/data/" .. file
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

session:log("RE0 Koop %s geladen (coopnet %s, Runtime %s)", MOD_VERSION, coopnet.version(), remods.version)
