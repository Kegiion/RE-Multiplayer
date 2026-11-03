-- re0hd_coop/lobby.lua - Multiplayer-Bereich auf dem Titelbildschirm und Status-Anzeige im Spiel.
--
-- Fuer Spieler, die das Einfg-Menue nicht kennen: Im Titelbildschirm erscheint
-- unten rechts ein Fenster mit "Spiel hosten" und "Freund beitreten". Beim
-- Beitreten holt die Mod den Spielstand des Hosts und startet das Spiel selbst.
-- Im Spiel zeigt oben rechts eine kleine Anzeige, mit wem man verbunden ist.
--
--   local lobby = Lobby.new(ctx)   -- ctx: session, config, save_config, game, join, join_request, join_cancel
--   lobby:frame(now)               -- jeden Frame (in re.on_frame), zeichnet auch die Fenster

local Lobby = {}
Lobby.__index = Lobby

local GREEN = 0xFF60E060   -- ABGR
local YELLOW = 0xFF40E0FF
local RED = 0xFF4040FF
local GREY = 0xFFB0B0B0

function Lobby.new(ctx)
    local self = setmetatable({}, Lobby)
    self.ctx = ctx
    self.mode = "start"      -- start, join (Adresse eingeben)
    self.auto_join = false   -- nach dem Verbinden automatisch den Spielstand holen
    self.ips = nil
    return self
end

local function flags()
    local f = imgui.flags or {}
    return (f.no_title or 0) | (f.no_resize or 0) | (f.no_move or 0) | (f.no_collapse or 0)
        | (f.auto_resize or 0) | (f.no_saved_settings or 0)
end

-- Hat die Runtime alles, was die Fenster brauchen (ab Runtime 0.5.0)?
local function supported()
    return imgui.set_next_window_pos ~= nil and imgui.display_size ~= nil and remultiplayer.show_cursor ~= nil
end

function Lobby:_peer_name()
    local s = self.ctx.session
    for _, p in pairs(s.peers) do
        if p.ready then
            return p.name or "Mitspieler"
        end
    end
    return nil
end

function Lobby:_ping()
    local st = self.ctx.session:status()
    local p = st.peers and st.peers[1]
    return p and p.rtt or nil
end

-- Logik pro Frame: nach dem Verbinden automatisch den Spielstand anfordern
function Lobby:_logic()
    local s, join = self.ctx.session, self.ctx.join
    if self.auto_join and s:mode() == "connected" and #s:ready_peers() > 0 and join.state == "idle" then
        self.ctx.join_request(true)
    end
    if s:mode() == "idle" then
        self.auto_join = false
    end
end

function Lobby:_big_button(label, sc)
    return imgui.button(label, 300 * sc, 40 * sc)
end

function Lobby:_draw_title(sc)
    local ctx = self.ctx
    local s, config, join = ctx.session, ctx.config, ctx.join
    local mode = s:mode()
    local changed

    imgui.text_colored("RE:Multiplayer", YELLOW)
    imgui.same_line()
    imgui.text("Koop fuer Resident Evil 0")
    imgui.separator()

    if mode == "idle" and self.mode == "start" then
        changed, config.name = imgui.input_text("Dein Name", config.name)
        if changed then
            s.name = config.name
            ctx.save_config()
        end
        if self:_big_button("Spiel hosten", sc) then
            s:host(config.port)
        end
        if self:_big_button("Freund beitreten", sc) then
            self.mode = "join"
        end
        imgui.text_colored("Erweiterte Einstellungen: Taste Einfg oder F8", GREY)
    elseif mode == "idle" and self.mode == "join" then
        imgui.text("Adresse deines Freundes (IP):")
        changed, config.address = imgui.input_text("##address", config.address)
        if changed then ctx.save_config() end
        local port_text
        changed, port_text = imgui.input_text("Port##port", tostring(config.port))
        if changed then
            local port = tonumber(port_text)
            if port and port >= 1 and port <= 65535 then
                config.port = math.floor(port)
                ctx.save_config()
            end
        end
        if self:_big_button("Verbinden", sc) then
            self.auto_join = true
            s:join(config.address, config.port)
        end
        if imgui.button("Zurueck") then
            self.mode = "start"
        end
    elseif mode == "hosting" then
        local friend = self:_peer_name()
        if friend then
            imgui.text_colored(friend .. " ist verbunden.", GREEN)
            imgui.text_wrapped("Lade jetzt deinen Spielstand (Spiel laden). Dein Freund bekommt ihn automatisch und startet mit dir.")
        else
            imgui.text("Du hostest. Warte auf deinen Freund ...")
            if not self.ips then
                self.ips = remultiplayer.local_ips and remultiplayer.local_ips() or {}
            end
            imgui.text("Deine Adresse im Heimnetz:")
            for _, ip in ipairs(self.ips) do
                imgui.text_colored("  " .. ip .. "   Port " .. config.port, YELLOW)
            end
            imgui.text_wrapped("Uebers Internet braucht dein Freund deine oeffentliche IP, und im Router muss UDP-Port "
                .. config.port .. " freigegeben sein (oder ihr nutzt ein VPN wie Radmin VPN oder ZeroTier).")
        end
        if imgui.button("Hosten beenden") then
            s:leave()
            self.ips = nil
        end
    elseif mode == "connecting" then
        imgui.text("Verbinde mit " .. config.address .. " ...")
        if imgui.button("Abbrechen") then
            s:leave()
        end
    elseif mode == "connected" then
        local host = self:_peer_name() or "Host"
        imgui.text_colored("Verbunden mit " .. host, GREEN)
        local st = join.state
        if st == "idle" then
            imgui.text("Hole den Spielstand ...")
        elseif st == "waiting" then
            imgui.text("Frage den Spielstand an ...")
        elseif st == "waiting_host" then
            imgui.text_wrapped((join.text ~= "" and join.text or (host .. " hat noch keinen Spielstand geladen."))
                .. " Sobald es einen gibt, geht es automatisch los.")
        elseif st == "receiving" and join.receiver then
            imgui.text(string.format("Empfange Spielstand: %d von %d", join.receiver.count, join.receiver.begin.chunks))
        elseif st == "holding" then
            if config.auto_load then
                imgui.text("Spielstand empfangen - starte das Spiel ...")
            else
                imgui.text_wrapped(string.format("Spielstand empfangen. Lade jetzt Platz %d (Spiel laden).", config.join_slot))
            end
        elseif st == "error" then
            imgui.text_colored(join.text, RED)
            if imgui.button("Nochmal versuchen") then
                ctx.join_request(true)
            end
        end
        if imgui.button("Trennen") then
            ctx.join_cancel()
            s:leave()
            self.mode = "start"
        end
    end
end

function Lobby:_draw_badge(sc)
    local s = self.ctx.session
    local mode = s:mode()
    if mode == "idle" then
        return
    end
    local w = imgui.display_size()
    imgui.set_next_window_pos(w - 12 * sc, 12 * sc, 1, 0)
    imgui.set_next_window_bg_alpha(0.55)
    local f = imgui.flags or {}
    local badge_flags = (f.no_decoration or 0) | (f.auto_resize or 0) | (f.no_saved_settings or 0)
        | (f.no_focus_on_appearing or 0) | (f.no_nav or 0) | (f.no_inputs or 0)
    imgui.begin_window("##remultiplayer_badge", nil, badge_flags)
    local friend = self:_peer_name()
    if friend then
        local ping = self:_ping()
        imgui.text_colored(string.format("RE:Multiplayer - %s%s", friend, ping and string.format(" - %d ms", ping) or ""), GREEN)
    elseif mode == "hosting" then
        imgui.text_colored("RE:Multiplayer - warte auf Mitspieler", YELLOW)
    else
        imgui.text_colored("RE:Multiplayer - verbinde ...", YELLOW)
    end
    imgui.end_window()
end

function Lobby:frame(now)
    self:_logic()
    if not supported() or remultiplayer.menu_open() then
        return
    end
    local sc = remultiplayer.ui_scale()
    if self.ctx.game.is_title() then
        local w, h = imgui.display_size()
        imgui.set_next_window_pos(w - 24 * sc, h - 24 * sc, 1, 1)
        imgui.set_next_window_bg_alpha(0.85)
        imgui.begin_window("RE:Multiplayer##lobby", nil, flags())
        remultiplayer.show_cursor()
        self:_draw_title(sc)
        imgui.end_window()
    else
        self:_draw_badge(sc)
    end
end

return Lobby
