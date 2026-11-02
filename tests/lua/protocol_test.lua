local protocol = require("remultiplayer_coop.protocol")

-- Roundtrip HELLO
local raw = protocol.encode("HELLO", { protocol = protocol.VERSION, game = "re2r", mod_version = "0.1.0", name = "Leon", want_reply = 1 })
local msg = assert(protocol.decode(raw))
assert(msg.type == "HELLO")
assert(msg.protocol == protocol.VERSION)
assert(msg.game == "re2r" and msg.mod_version == "0.1.0" and msg.name == "Leon")
assert(msg.want_reply == 1)

-- Roundtrip PLAYER_STATE mit Floats
raw = protocol.encode("PLAYER_STATE", { seq = 4000000000, area = "RPD_1F", x = 1.5, y = -2.25, z = 100.125,
    qx = 0, qy = 0.7071, qz = 0, qw = 0.7071, character = 1, flags = 3 })
msg = assert(protocol.decode(raw))
assert(msg.type == "PLAYER_STATE")
assert(msg.seq == 4000000000)
assert(msg.area == "RPD_1F")
assert(msg.x == 1.5 and msg.y == -2.25 and msg.z == 100.125)
assert(math.abs(msg.qy - 0.7071) < 1e-4)
assert(msg.character == 1 and msg.flags == 3)
-- kompakt: 1 Typ + 4 seq + 1+6 area + 7*4 floats + 2 Bytes
assert(#raw == 1 + 4 + 7 + 28 + 2, "unerwartete Groesse " .. #raw)

-- Fehlende Felder werden zu 0 / ""
msg = assert(protocol.decode(protocol.encode("PLAYER_STATE", {})))
assert(msg.x == 0 and msg.area == "")

-- Zu lange Strings werden gekuerzt statt zu crashen
msg = assert(protocol.decode(protocol.encode("CHAT", { text = string.rep("x", 300) })))
assert(#msg.text == 255)

-- Kaputte Daten
assert(protocol.decode("") == nil)
assert(protocol.decode("\250") == nil)
local bad, err = protocol.decode(string.char(protocol.MSG.PLAYER_STATE) .. "kurz")
assert(bad == nil and err:find("beschaedigt"))

print("protocol_test: alles ok")
