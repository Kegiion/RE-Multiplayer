-- Testbot: folgt mit Verzoegerung und seitlichem Versatz, beantwortet Chat.
TESTBOT_AS_MODULE = true
package.path = assert(os.getenv("REMULTIPLAYER_TOOLS")) .. "/testbot/?.lua;" .. package.path
local Bot = require("testbot")
local Session = require("remultiplayer_coop.session")
local PORT = 47931

Bot.DELAY = 0.2
local host = Session.new({ net = net_a, game = "re2r", name = "Leon" })
local from_bot, chats = {}, {}
host:on("PLAYER_STATE", function(_, _, msg) table.insert(from_bot, msg) end)
host:on("CHAT", function(_, _, msg) table.insert(chats, msg.text) end)
assert(host:host(PORT))

local bot = Bot.new(net_b, { print = function() end })
assert(bot.session:join("127.0.0.1", PORT))

local seq = 0
local deadline = net_a.time() + 4
while net_a.time() < deadline and #from_bot < 5 do
    host:update()
    bot:step()
    if #host:ready_peers() > 0 then
        seq = seq + 1
        host:send("PLAYER_STATE", { seq = seq, area = "test", x = 10, y = 1, z = 20, qw = 1 }, false)
    end
    sleep_ms(10)
end
assert(#from_bot >= 5, "Bot sendet nichts")
local m = from_bot[#from_bot]
assert(math.abs(m.x - (10 + Bot.SIDE_OFFSET)) < 1e-4 and m.y == 1 and m.z == 20, "falsche Bot-Position")
assert(m.area == "test")

host:send("CHAT", { text = "ping" }, true)
deadline = net_a.time() + 2
while net_a.time() < deadline and #chats == 0 do
    host:update(); bot:step(); sleep_ms(10)
end
assert(chats[1] == "Echo: ping", "kein Chat-Echo")

bot.session:leave()
host:leave()
print("testbot_test: alles ok")
