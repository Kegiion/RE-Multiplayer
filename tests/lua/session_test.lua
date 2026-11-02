local Session = require("remultiplayer_coop.session")
local PORT = 47901

local function pump(sessions, cond, timeout)
    local deadline = net_a.time() + (timeout or 3)
    while net_a.time() < deadline do
        for _, s in ipairs(sessions) do s:update() end
        if cond() then return true end
        sleep_ms(5)
    end
    return false
end

-- Normaler Ablauf: Host + Client, Handshake, Nachricht, Trennen
local host = Session.new({ net = net_a, game = "re2r", mod_version = "0.1.0", name = "Leon" })
local client = Session.new({ net = net_b, game = "re2r", mod_version = "0.1.0", name = "Claire" })

local joined_host, joined_client, left_host = nil, nil, nil
host:subscribe("peer_joined", function(_, p) joined_host = p end)
client:subscribe("peer_joined", function(_, p) joined_client = p end)
host:subscribe("peer_left", function(_, p) left_host = p end)

local states = {}
host:on("PLAYER_STATE", function(_, peer, msg) table.insert(states, { peer = peer, msg = msg }) end)

assert(host:host(PORT))
assert(client:join("127.0.0.1", PORT))
assert(pump({ host, client }, function() return joined_host and joined_client end), "Handshake fehlgeschlagen")
assert(joined_host.name == "Claire", joined_host.name)
assert(joined_client.name == "Leon")
assert(#host:ready_peers() == 1 and #client:ready_peers() == 1)

assert(client:send("PLAYER_STATE", { seq = 1, x = 3, y = 4, z = 5, qw = 1 }, false))
assert(pump({ host, client }, function() return #states > 0 end), "PLAYER_STATE nicht angekommen")
assert(states[1].msg.x == 3 and states[1].peer.name == "Claire")

-- Simuliertes "Reset Scripts" beim Client: neue Lua-Session auf derselben Verbindung
local client2 = Session.new({ net = net_b, game = "re2r", mod_version = "0.1.0", name = "Claire" })
local rejoined = nil
client2:subscribe("peer_joined", function(_, p) rejoined = p end)
assert(pump({ host, client2 }, function() return rejoined ~= nil end), "Wiederaufnahme nach Reset fehlgeschlagen")
assert(rejoined.name == "Leon")

client2:leave()
assert(pump({ host }, function() return left_host ~= nil end), "Host hat Trennung nicht bemerkt")
assert(left_host.name == "Claire")
host:leave()

-- Falsches Spiel wird erkannt
local h = Session.new({ net = net_a, game = "re2r", name = "A" })
local c = Session.new({ net = net_b, game = "re3r", name = "B" })
assert(h:host(PORT + 1))
assert(c:join("127.0.0.1", PORT + 1))
assert(pump({ h, c }, function()
    for _, p in pairs(h.peers) do if p.incompatible then return true end end
    return false
end), "falsches Spiel nicht erkannt")
assert(#h:ready_peers() == 0)
c:leave()
h:leave()

print("session_test: alles ok")
