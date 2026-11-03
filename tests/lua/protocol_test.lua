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

-- Roundtrip ANIM_STATE: leere Ebene = 0xFFFFFFFF
raw = protocol.encode("ANIM_STATE", { seq = 7, banks_id = 3, bank0 = 1, motion0 = 190, frame0 = 12.5,
    interp0 = 24, imode0 = 3, icurve0 = 1,
    bank3 = 0, motion3 = 4294967295 })
msg = assert(protocol.decode(raw))
assert(msg.type == "ANIM_STATE" and msg.seq == 7 and msg.banks_id == 3)
assert(msg.bank0 == 1 and msg.motion0 == 190 and msg.frame0 == 12.5)
assert(msg.interp0 == 24 and msg.imode0 == 3 and msg.icurve0 == 1)
assert(msg.motion3 == 4294967295 and msg.motion1 == 0)
assert(#raw == 1 + 4 + 2 + 4 * (2 + 4 + 4 + 4 + 1 + 1) + 4 + 12 * 4, "unerwartete Groesse " .. #raw)

-- Roundtrip ANIM_BANKS
msg = assert(protocol.decode(protocol.encode("ANIM_BANKS", { banks_id = 65535,
    main = "SectionRoot/Animation/Player/common/pl_common.motbank", dyn1 = "a.motbank" })))
assert(msg.banks_id == 65535 and msg.main:find("pl_common") and msg.dyn1 == "a.motbank" and msg.dyn4 == "")

-- Fehlende Felder werden zu 0 / ""
msg = assert(protocol.decode(protocol.encode("PLAYER_STATE", {})))
assert(msg.x == 0 and msg.area == "")

-- Zu lange Strings werden gekuerzt statt zu crashen
msg = assert(protocol.decode(protocol.encode("CHAT", { text = string.rep("x", 300) })))
assert(#msg.text == 255)

-- Spielstand-Stueck: s2 traegt bis 65535 Bytes, laengeres wird gekuerzt
local blob = string.rep("\0\1\255", 3000)
msg = assert(protocol.decode(protocol.encode("SAVE_CHUNK", { transfer = 7, index = 3, data = blob })))
assert(msg.transfer == 7 and msg.index == 3 and msg.data == blob, "SAVE_CHUNK falsch")
msg = assert(protocol.decode(protocol.encode("SAVE_CHUNK", { data = string.rep("y", 70000) })))
assert(#msg.data == 65535)
msg = assert(protocol.decode(protocol.encode("SAVE_BEGIN", { transfer = 1, size = 116816, chunks = 15, checksum = 0xDEADBEEF, info = "Platz 3" })))
assert(msg.size == 116816 and msg.chunks == 15 and msg.checksum == 0xDEADBEEF and msg.info == "Platz 3")
assert(protocol.decode(protocol.encode("SAVE_REQUEST", {})).type == "SAVE_REQUEST")

-- Kaputte Daten
assert(protocol.decode("") == nil)
assert(protocol.decode("\250") == nil)
local bad, err = protocol.decode(string.char(protocol.MSG.PLAYER_STATE) .. "kurz")
assert(bad == nil and err:find("beschaedigt"))

print("protocol_test: alles ok")
