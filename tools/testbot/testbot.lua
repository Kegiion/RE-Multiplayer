-- RE:Multiplayer Testbot
--
-- Ein simulierter Mitspieler fuer Tests ohne zweiten PC: verbindet sich mit
-- deinem Spiel (dort "Hosten" klicken) und laeuft dir mit 1 Sekunde
-- Verzoegerung hinterher. Im Spiel siehst du ihn als Markierung "Testbot".
-- Animationen (ANIM_BANKS/ANIM_STATE) und Eingaben (INPUT_STATE) spielt er
-- mit derselben Verzoegerung nach, falls das Spiel welche sendet.
-- Chat-Nachrichten beantwortet er mit einem Echo.
--
-- Spielstand-Spiegel (Join-Test ohne zweiten PC, nur mit --host): Sobald das Spiel verbunden ist,
-- fordert der Bot dessen Spielstand an (SAVE_REQUEST) und merkt ihn sich.
-- Fragt das Spiel spaeter selbst an, schickt er ihm genau diesen Stand zurueck.
--
-- Aufruf: remultiplayer_luarun testbot.lua [ip] [port] [spiel]
--         remultiplayer_luarun testbot.lua --host [port] [spiel]
--         (Standard: 127.0.0.1 27350 re2r; mit --host wartet der Bot selbst
--         auf das Spiel, dort dann "Beitreten" klicken)

local Session = require("remultiplayer_coop.session")
local transfer = require("remultiplayer_coop.transfer")

local Bot = {}
Bot.__index = Bot

Bot.DELAY = 1.0          -- Sekunden Verzoegerung beim Hinterherlaufen
Bot.SIDE_OFFSET = 0.8    -- Meter seitlich versetzt, damit er sichtbar bleibt
Bot.SEND_INTERVAL = 0.05
Bot.BANKS_RESEND_INTERVAL = 3.0
Bot.HISTORY_SIZE = 400
Bot.INPUT_HISTORY_SIZE = 200 -- bis 60 Eingaben pro Sekunde, reicht fuer DELAY

function Bot.new(net, opts)
    opts = opts or {}
    local self = setmetatable({}, Bot)
    self.net = net
    self.print = opts.print or print
    self.history = {}
    self.anim_history = {}
    self.input_history = {}
    self.input_seq = 0
    self.input_last = nil
    self.banks = nil
    self.banks_sent = -math.huge
    self.seq = 0
    self.last_send = 0
    self.last_report = 0
    self.received = 0
    self.session = Session.new({
        net = net,
        game = opts.game or "re2r",
        mod_version = opts.mod_version or "testbot",
        name = opts.name or "Testbot",
    })
    -- Spielstand-Spiegel
    self.save_data, self.save_info, self.save_rx = nil, nil, nil
    self.save_out = {}
    self.mirror = opts.mirror -- nur im Host-Modus den Stand des Spiels anfordern
    self.session:subscribe("peer_joined", function(s, peer)
        if self.mirror and self.save_data == nil then
            s:send("SAVE_REQUEST", { reserved = 0 }, true, peer.id)
        end
    end)
    self.session:on("SAVE_BEGIN", function(_, _, msg)
        if msg.size > 0 then
            self.save_rx = transfer.receiver(msg)
        end
    end)
    self.session:on("SAVE_CHUNK", function(s, _, msg)
        if self.save_rx and self.save_rx:add(msg) and self.save_rx:complete() then
            local data, err = self.save_rx:result()
            self.save_rx = nil
            if data then
                self.save_data = data
                for _, id in ipairs(self.save_waiting) do
                    self:send_save(id)
                end
                self.save_waiting = {}
                self.print(string.format("Spielstand gespeichert (%d KB). Im Spiel jetzt \"Spielstand des Hosts holen\".", #data // 1024))
            else
                self.print("Spielstand fehlerhaft: " .. tostring(err))
            end
        end
    end)
    self.save_waiting = {} -- Anfragen, die eintrafen, bevor der Bot einen Stand hatte
    self.session:on("SAVE_REQUEST", function(s, peer)
        if self.save_data == nil then
            if self.mirror then
                self.save_waiting[#self.save_waiting + 1] = peer.id
            else
                s:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = "Testbot hat noch keinen Spielstand" }, true, peer.id)
            end
            return
        end
        self:send_save(peer.id)
    end)
    self.session:on("PLAYER_STATE", function(s, _, msg)
        self.received = self.received + 1
        table.insert(self.history, { t = s:time(), msg = msg })
        if #self.history > Bot.HISTORY_SIZE then
            table.remove(self.history, 1)
        end
    end)
    self.session:on("ANIM_STATE", function(s, _, msg)
        table.insert(self.anim_history, { t = s:time(), msg = msg })
        if #self.anim_history > Bot.HISTORY_SIZE then
            table.remove(self.anim_history, 1)
        end
    end)
    self.session:on("INPUT_STATE", function(s, _, msg)
        table.insert(self.input_history, { t = s:time(), msg = msg })
        if #self.input_history > Bot.INPUT_HISTORY_SIZE then
            table.remove(self.input_history, 1)
        end
    end)
    self.session:on("ANIM_BANKS", function(_, _, msg)
        self.banks = msg
        self.banks_sent = -math.huge -- sofort weitergeben
    end)
    self.session:on("CHAT", function(s, peer, msg)
        self.print(string.format("[Chat] %s: %s", peer.name or "?", msg.text))
        s:send("CHAT", { text = "Echo: " .. msg.text }, true)
    end)
    self.session:subscribe("peer_joined", function(_, peer)
        self.print("Verbunden mit " .. tostring(peer.name) .. " - laufe jetzt hinter dir her.")
    end)
    return self
end

-- Zustand von vor DELAY Sekunden (oder der aelteste, den wir haben).
function Bot:delayed_state(now, history)
    history = history or self.history
    local chosen = nil
    for _, entry in ipairs(history) do
        if now - entry.t >= Bot.DELAY then
            chosen = entry.msg
        else
            break
        end
    end
    return chosen or (history[1] and history[1].msg)
end

function Bot:send_save(peer_id)
    local begin, chunks = transfer.split(self.save_data, os.time() % 100000, "Testbot-Spiegel")
    self.session:send("SAVE_BEGIN", begin, true, peer_id)
    self.save_out[#self.save_out + 1] = { peer = peer_id, chunks = chunks, next = 1 }
    self.print(string.format("Schicke Spielstand zurueck (%d Stuecke)", #chunks))
end

function Bot:send_saves()
    for i = #self.save_out, 1, -1 do
        local out = self.save_out[i]
        for _ = 1, 8 do
            local c = out.chunks[out.next]
            if c == nil then
                break
            end
            self.session:send("SAVE_CHUNK", c, true, out.peer)
            out.next = out.next + 1
        end
        if out.next > #out.chunks then
            table.remove(self.save_out, i)
        end
    end
end

function Bot:step()
    local s = self.session
    s:update()
    self:send_saves()
    local now = s:time()

    if s:is_active() and #s:ready_peers() > 0 and now - self.last_send >= Bot.SEND_INTERVAL then
        local src = self:delayed_state(now)
        if src then
            self.last_send = now
            self.seq = (self.seq + 1) % 4294967296
            s:send("PLAYER_STATE", {
                seq = self.seq, area = src.area,
                x = src.x + Bot.SIDE_OFFSET, y = src.y, z = src.z,
                qx = src.qx, qy = src.qy, qz = src.qz, qw = src.qw,
                character = src.character, flags = src.flags,
            }, false)
            self:send_anim(now)
        end
    end

    if s:is_active() and #s:ready_peers() > 0 then
        self:send_input(now)
    end

    if now - self.last_report >= 2.0 then
        self.last_report = now
        local latest = self.history[#self.history]
        if latest then
            self.print(string.format("Deine Position: %.2f %.2f %.2f  (Bereich '%s', %d Updates empfangen)",
                latest.msg.x, latest.msg.y, latest.msg.z, latest.msg.area, self.received))
        end
    end
end

function Bot:send_anim(now)
    local s = self.session
    if self.banks ~= nil and now - self.banks_sent >= Bot.BANKS_RESEND_INTERVAL then
        self.banks_sent = now
        s:send("ANIM_BANKS", self.banks, true)
    end
    local src = self:delayed_state(now, self.anim_history)
    if src ~= nil then
        local msg = {}
        for k, v in pairs(src) do
            msg[k] = v
        end
        msg.seq = self.seq
        s:send("ANIM_STATE", msg, false)
    end
end

-- Eingaben verzoegert zurueckschicken, jede hoechstens einmal.
function Bot:send_input(now)
    local src = self:delayed_state(now, self.input_history)
    if src == nil or src == self.input_last then
        return
    end
    self.input_last = src
    local msg = {}
    for k, v in pairs(src) do
        msg[k] = v
    end
    self.input_seq = (self.input_seq + 1) % 4294967296
    msg.seq = self.input_seq
    self.session:send("INPUT_STATE", msg, false)
end

-- Als Modul geladen (Tests)? Dann nicht die Endlosschleife starten.
if TESTBOT_AS_MODULE then
    return Bot
end

local host_mode = arg and arg[1] == "--host"
local first = host_mode and 2 or 1
local address = (not host_mode and arg and arg[1]) or "127.0.0.1"
local port = tonumber(arg and arg[first + (host_mode and 0 or 1)]) or 27350
local game = arg and arg[first + (host_mode and 1 or 2)] or "re2r"

local bot = Bot.new(net_a, { game = game, mirror = host_mode })
local last_log = 0
local next_attempt = 0

if host_mode then
    print(string.format("RE:Multiplayer Testbot - hostet auf Port %d (Spiel %s). Im Spiel \"Beitreten\" auf 127.0.0.1:%d. Beenden mit Strg+C.", port, game, port))
    assert(bot.session:host(port))
else
    print(string.format("RE:Multiplayer Testbot - verbinde zu %s:%d (Spiel %s). Beenden mit Strg+C.", address, port, game))
end
while true do
    local now = bot.session:time()
    if not host_mode and bot.session:mode() == "idle" and now >= next_attempt then
        bot.history = {}
        bot.session:join(address, port)
        next_attempt = now + 3
    end
    bot:step()
    for i = last_log + 1, #bot.session.log_lines do
        print(bot.session.log_lines[i])
    end
    last_log = #bot.session.log_lines
    sleep_ms(10)
end
