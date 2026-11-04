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
    bank3 = 0, motion3 = 4294967295, bank4 = 2, motion4 = 1100, restart4 = 255 })
msg = assert(protocol.decode(raw))
assert(msg.type == "ANIM_STATE" and msg.seq == 7 and msg.banks_id == 3)
assert(msg.bank0 == 1 and msg.motion0 == 190 and msg.frame0 == 12.5)
assert(msg.interp0 == 24 and msg.imode0 == 3 and msg.icurve0 == 1)
assert(msg.motion3 == 4294967295 and msg.motion1 == 0)
assert(msg.bank4 == 2 and msg.motion4 == 1100 and msg.restart4 == 255 and msg.motion5 == 0)
assert(#raw == 1 + 4 + 2 + protocol.ANIM_LAYERS * (2 + 4 + 4 + 4 + 1 + 1 + 1) + 4 + 12 * 4, "unerwartete Groesse " .. #raw)

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

-- Gegner, Tod und Items (IDs 10..26), VERSION bleibt 3
assert(protocol.VERSION == 3, "VERSION erst bei Nutzung im Spiel erhoehen")
local new_ids = { ENEMY_SPAWN = 10, ENEMY_STATE = 11, ENEMY_HP = 12, ENEMY_DEAD = 13, ENEMY_DESPAWN = 14,
    ENEMY_HIT = 15, PLAYER_HIT = 16, ENEMY_HANDOVER = 17, PLAYER_DOWN = 18, REVIVE_REQUEST = 19,
    REVIVE_EVENT = 20, GAME_OVER = 21, ITEM_PICKUP = 22, ITEM_TAKEN = 23, ITEM_GRANT = 24,
    ITEM_DISCARD = 25, HOST_SAVED = 26 }
for name, id in pairs(new_ids) do
    assert(protocol.MSG[name] == id, name .. " hat falsche ID")
    assert(protocol.decode(protocol.encode(name, {})).type == name, name .. " leer")
end
-- Bestehende IDs unveraendert
for name, id in pairs({ HELLO = 1, PLAYER_STATE = 2, CHAT = 3, ANIM_BANKS = 4, ANIM_STATE = 5,
    SAVE_REQUEST = 6, SAVE_BEGIN = 7, SAVE_CHUNK = 8, INPUT_STATE = 9 }) do
    assert(protocol.MSG[name] == id, name .. " verschoben")
end

raw = protocol.encode("ENEMY_SPAWN", { eid = 513, kind = "zombie", key = "k1", zone = 112, x = 1.5, y = 2, z = -3,
    yaw = 0.5, hp = 120, hp_max = 200, flags = 1 })
msg = assert(protocol.decode(raw))
assert(msg.eid == 513 and msg.kind == "zombie" and msg.key == "k1" and msg.zone == 112)
assert(msg.x == 1.5 and msg.z == -3 and msg.hp == 120 and msg.hp_max == 200 and msg.flags == 1)
assert(#raw == 1 + 2 + 7 + 3 + 2 + 6 * 4 + 1, "ENEMY_SPAWN Groesse " .. #raw)

msg = assert(protocol.decode(protocol.encode("ENEMY_STATE", { seq = 9, zone = 65535, data = string.rep("\7", 1041) })))
assert(msg.seq == 9 and msg.zone == 65535 and #msg.data == 1041)
msg = assert(protocol.decode(protocol.encode("ENEMY_HIT", { hit_seq = 77, eid = 4, damage = 37.5, part = 3, weapon = 1000, flags = 2 })))
assert(msg.hit_seq == 77 and msg.eid == 4 and msg.damage == 37.5 and msg.part == 3 and msg.weapon == 1000 and msg.flags == 2)
assert(#protocol.encode("ENEMY_HIT", {}) == 15)
msg = assert(protocol.decode(protocol.encode("PLAYER_HIT", { eid = 4, damage = 10, kind = 1, dir = -1.25 })))
assert(msg.damage == 10 and msg.kind == 1 and msg.dir == -1.25)
msg = assert(protocol.decode(protocol.encode("REVIVE_EVENT", { event = 4, who = 1, by = 2, time_left = 12.5 })))
assert(msg.event == 4 and msg.who == 1 and msg.by == 2 and msg.time_left == 12.5)
msg = assert(protocol.decode(protocol.encode("GAME_OVER", { reason = 2, slot = -1 })))
assert(msg.reason == 2 and msg.slot == -1, "slot vorzeichenbehaftet")
msg = assert(protocol.decode(protocol.encode("ITEM_PICKUP", { item_key = "st4_101/item3", item_id = 4000000000, count = 15, zone = 112 })))
assert(msg.item_key == "st4_101/item3" and msg.item_id == 4000000000 and msg.count == 15 and msg.zone == 112)
msg = assert(protocol.decode(protocol.encode("HOST_SAVED", { slot = 21, session_id = 0xCAFEBABE })))
assert(msg.slot == 21 and msg.session_id == 0xCAFEBABE)

-- Kaputte Daten
assert(protocol.decode("") == nil)
assert(protocol.decode("\250") == nil)
local bad, err = protocol.decode(string.char(protocol.MSG.PLAYER_STATE) .. "kurz")
assert(bad == nil and err:find("beschaedigt"))

print("protocol_test: alles ok")
