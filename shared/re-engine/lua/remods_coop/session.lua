-- remods_coop/session.lua
--
-- Spielunabhaengige Sitzungslogik ueber der `coopnet`-API des Plugins:
-- Verbindungsaufbau, Handshake (HELLO), Versionspruefung, Nachrichten-
-- verteilung an Handler und ein kleines Log fuer die UI.
--
-- Benutzung:
--   local Session = require("remods_coop.session")
--   local s = Session.new({ net = coopnet, game = "re2r", mod_version = "0.1.0", name = "Leon" })
--   s:on("PLAYER_STATE", function(session, peer, msg) ... end)
--   s:host(27015)  oder  s:join("1.2.3.4", 27015)
--   -- jeden Frame:
--   s:update()

local protocol = require("remods_coop.protocol")

local Session = {}
Session.__index = Session

local LOG_SIZE = 60

function Session.new(opts)
    assert(opts and opts.net, "Session.new: opts.net (coopnet) fehlt")
    local self = setmetatable({}, Session)
    self.net = opts.net
    self.game = assert(opts.game, "Session.new: opts.game fehlt")
    self.mod_version = opts.mod_version or "0.0.0"
    self.name = opts.name or "Spieler"
    self.max_peers = opts.max_peers or 1
    self.handlers = {}
    self.listeners = { peer_joined = {}, peer_left = {} }
    -- peers[id] = { id=, name=, ready=bool, address= }
    self.peers = {}
    self.log_lines = {}
    self.is_host = false
    self:_sync_peers_from_plugin()
    return self
end

-- Zeit in Sekunden (monoton). Faellt auf os.clock zurueck, falls das Plugin
-- (noch) keine time()-Funktion hat.
function Session:time()
    if self.net.time then
        return self.net.time()
    end
    return os.clock()
end

function Session:log(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then
        text = tostring(fmt)
    end
    local line = string.format("[%7.1f] %s", self:time(), text)
    table.insert(self.log_lines, line)
    if #self.log_lines > LOG_SIZE then
        table.remove(self.log_lines, 1)
    end
    if log and log.info then -- REFramework-Log (reframework/re2_framework_log.txt)
        log.info("[remods_coop] " .. text)
    end
end

-- Handler fuer einen Nachrichtentyp registrieren: fn(session, peer, msg)
function Session:on(msg_name, fn)
    assert(protocol.MSG[msg_name], "unbekannte Nachricht: " .. tostring(msg_name))
    self.handlers[msg_name] = fn
end

-- Ereignis abonnieren: "peer_joined" (nach erfolgreichem HELLO) oder "peer_left".
function Session:subscribe(event, fn)
    table.insert(assert(self.listeners[event], "unbekanntes Ereignis " .. tostring(event)), fn)
end

function Session:_emit(event, ...)
    for _, fn in ipairs(self.listeners[event]) do
        local ok, err = pcall(fn, self, ...)
        if not ok then
            self:log("Fehler in Listener %s: %s", event, tostring(err))
        end
    end
end

function Session:status()
    return self.net.status()
end

function Session:mode()
    return self.net.status().mode
end

function Session:is_active()
    local mode = self:mode()
    return mode == "hosting" or mode == "connected"
end

-- Nach "Reset Scripts" laeuft die Verbindung im Plugin weiter, unsere
-- Lua-Tabellen sind aber leer. Wir uebernehmen die Peers und schicken ein
-- neues HELLO, damit beide Seiten wieder synchron sind.
function Session:_sync_peers_from_plugin()
    local status = self.net.status()
    self.is_host = status.mode == "hosting"
    for _, p in ipairs(status.peers or {}) do
        self.peers[p.id] = { id = p.id, address = p.address, ready = false }
        self:_send_hello(p.id, true)
    end
end

function Session:host(port)
    self.peers = {}
    local ok, err = self.net.host(port, self.max_peers)
    if ok then
        self.is_host = true
        self:log("Host gestartet auf Port %d", port)
    else
        self:log("Host fehlgeschlagen: %s", tostring(err))
    end
    return ok, err
end

function Session:join(address, port)
    self.peers = {}
    local ok, err = self.net.connect(address, port)
    if ok then
        self.is_host = false
        self:log("Verbinde zu %s:%d ...", address, port)
    else
        self:log("Verbinden fehlgeschlagen: %s", tostring(err))
    end
    return ok, err
end

function Session:leave()
    self.net.disconnect()
    for id, peer in pairs(self.peers) do
        self.peers[id] = nil
        if peer.ready then
            self:_emit("peer_left", peer)
        end
    end
    self:log("Verbindung beendet")
end

-- Nachricht senden. peer = nil -> an alle.
function Session:send(msg_name, data, reliable, peer)
    return self.net.send(protocol.encode(msg_name, data), reliable == true, peer or 0)
end

function Session:_send_hello(peer_id, want_reply)
    self:send("HELLO", {
        protocol = protocol.VERSION,
        game = self.game,
        mod_version = self.mod_version,
        name = self.name,
        want_reply = want_reply and 1 or 0,
    }, true, peer_id)
end

function Session:_handle_hello(peer, msg)
    if msg.want_reply == 1 then
        self:_send_hello(peer.id, false)
    end
    if msg.protocol ~= protocol.VERSION then
        self:log("Spieler %d hat Protokoll v%d, wir v%d - bitte gleiche Mod-Version nutzen!",
            peer.id, msg.protocol, protocol.VERSION)
        peer.incompatible = true
        return
    end
    if msg.game ~= self.game then
        self:log("Spieler %d spielt '%s', wir '%s' - falsches Spiel!", peer.id, msg.game, self.game)
        peer.incompatible = true
        return
    end
    local first_hello = not peer.ready
    peer.name = msg.name
    peer.mod_version = msg.mod_version
    peer.ready = true
    if msg.mod_version ~= self.mod_version then
        self:log("Hinweis: %s nutzt Mod-Version %s, wir %s", msg.name, msg.mod_version, self.mod_version)
    end
    if first_hello then
        self:log("%s ist beigetreten", msg.name)
        self:_emit("peer_joined", peer)
    end
end

-- Muss jeden Frame aufgerufen werden.
function Session:update()
    for _, ev in ipairs(self.net.poll()) do
        if ev.type == "connect" then
            local peer = { id = ev.peer, ready = false }
            self.peers[ev.peer] = peer
            self:log("Verbunden mit Peer %d", ev.peer)
            self:_send_hello(ev.peer)
        elseif ev.type == "disconnect" then
            local peer = self.peers[ev.peer]
            self.peers[ev.peer] = nil
            if peer then
                self:log("%s hat die Verbindung getrennt", peer.name or ("Peer " .. ev.peer))
                if peer.ready then
                    self:_emit("peer_left", peer)
                end
            else
                local err = self.net.status().error
                self:log("Verbindung getrennt%s", err and (": " .. err) or "")
            end
        elseif ev.type == "message" then
            self:_handle_message(ev)
        end
    end
end

function Session:_handle_message(ev)
    local peer = self.peers[ev.peer]
    if peer == nil then
        return
    end
    local msg, err = protocol.decode(ev.data)
    if msg == nil then
        self:log("Ungueltige Nachricht von Peer %d: %s", ev.peer, err)
        return
    end
    if msg.type == "HELLO" then
        self:_handle_hello(peer, msg)
        return
    end
    if not peer.ready or peer.incompatible then
        return -- erst nach gueltigem HELLO verarbeiten
    end
    local handler = self.handlers[msg.type]
    if handler then
        local ok, herr = pcall(handler, self, peer, msg)
        if not ok then
            self:log("Fehler im Handler %s: %s", msg.type, tostring(herr))
        end
    end
end

-- Liste der Peers mit abgeschlossenem Handshake.
function Session:ready_peers()
    local list = {}
    for _, peer in pairs(self.peers) do
        if peer.ready and not peer.incompatible then
            table.insert(list, peer)
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

return Session
