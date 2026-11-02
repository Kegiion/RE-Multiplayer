-- RE:Multiplayer Testbot
--
-- Ein simulierter Mitspieler fuer Tests ohne zweiten PC: verbindet sich mit
-- deinem Spiel (dort "Hosten" klicken) und laeuft dir mit 1 Sekunde
-- Verzoegerung hinterher. Im Spiel siehst du ihn als Markierung "Testbot".
-- Chat-Nachrichten beantwortet er mit einem Echo.
--
-- Aufruf: remultiplayer_luarun testbot.lua [ip] [port] [spiel]
--         (Standard: 127.0.0.1 27350 re2r)

local Session = require("remultiplayer_coop.session")

local Bot = {}
Bot.__index = Bot

Bot.DELAY = 1.0          -- Sekunden Verzoegerung beim Hinterherlaufen
Bot.SIDE_OFFSET = 0.8    -- Meter seitlich versetzt, damit er sichtbar bleibt
Bot.SEND_INTERVAL = 0.05

function Bot.new(net, opts)
    opts = opts or {}
    local self = setmetatable({}, Bot)
    self.net = net
    self.print = opts.print or print
    self.history = {}
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
    self.session:on("PLAYER_STATE", function(s, _, msg)
        self.received = self.received + 1
        table.insert(self.history, { t = s:time(), msg = msg })
        if #self.history > 400 then
            table.remove(self.history, 1)
        end
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
function Bot:delayed_state(now)
    local chosen = nil
    for _, entry in ipairs(self.history) do
        if now - entry.t >= Bot.DELAY then
            chosen = entry.msg
        else
            break
        end
    end
    return chosen or (self.history[1] and self.history[1].msg)
end

function Bot:step()
    local s = self.session
    s:update()
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
        end
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

-- Als Modul geladen (Tests)? Dann nicht die Endlosschleife starten.
if TESTBOT_AS_MODULE then
    return Bot
end

local address = arg and arg[1] or "127.0.0.1"
local port = tonumber(arg and arg[2]) or 27350
local game = arg and arg[3] or "re2r"

local bot = Bot.new(net_a, { game = game })
local last_log = 0
local next_attempt = 0

print(string.format("RE:Multiplayer Testbot - verbinde zu %s:%d (Spiel %s). Beenden mit Strg+C.", address, port, game))
while true do
    local now = bot.session:time()
    if bot.session:mode() == "idle" and now >= next_attempt then
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
