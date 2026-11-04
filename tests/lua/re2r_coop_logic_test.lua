-- RE2: reine Koop-Logik ohne Spiel (re2r_coop/revive.lua, re2r_coop/enemy_net.lua)
local AUTORUN = assert(os.getenv("REMULTIPLAYER_RE2R_AUTORUN"), "Umgebungsvariable REMULTIPLAYER_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

local revive = require("re2r_coop.revive")
local enemy_net = require("re2r_coop.enemy_net")

local function types(events)
    local t = {}
    for i, e in ipairs(events) do t[i] = e.type end
    return table.concat(t, ",")
end

local function check(cond, msg)
    if not cond then error(msg, 2) end
end

local function new_match()
    local r = revive.new({ bleedout = 30, revive_time = 3, revive_range = 1.5 })
    r:add_player("host")
    r:add_player("client")
    return r
end

-- Aufheben klappt
do
    local r = new_match()
    check(types(r:down("client", 10)) == "DOWNED", "down")
    check(r:state("client") == "down", "state down")
    check(types(r:begin("client", "host", 12, 5.0)) == "", "zu weit weg")
    check(types(r:begin("client", "host", 12, 1.0)) == "REVIVE_BEGIN", "begin")
    check(types(r:update(14)) == "", "noch nicht fertig")
    local ev = r:update(15)
    check(types(ev) == "REVIVED" and ev[1].by == "host", "revived")
    check(r:state("client") == "alive" and not r:is_over(), "wieder stehend")
end

-- Frist laeuft ab
do
    local r = new_match()
    r:down("host", 0)
    check(types(r:update(29.9)) == "", "Frist noch nicht um")
    local ev = r:update(30)
    check(types(ev) == "GAME_OVER" and ev[1].reason == "bleedout", "bleedout")
    check(types(r:update(31)) == "", "nur einmal Game Over")
end

-- Beide fallen
do
    local r = new_match()
    r:down("host", 0)
    local ev = r:down("client", 1)
    check(types(ev) == "DOWNED,GAME_OVER" and ev[2].reason == "both_down", "both_down")
end

-- Helfer faellt beim Aufheben: Abbruch und Game Over
do
    local r = new_match()
    r:down("client", 0)
    r:begin("client", "host", 1, 1.0)
    local ev = r:down("host", 2)
    check(types(ev) == "REVIVE_CANCEL,DOWNED,GAME_OVER", "Helfer faellt: " .. types(ev))
end

-- Abbruch nach abgelaufener Frist: Gnadenfrist 2 s
do
    local r = new_match()
    r:down("client", 0)
    r:begin("client", "host", 28, 1.0)
    check(types(r:update(30.5)) == "", "waehrend des Aufhebens keine Frist")
    check(types(r:cancel("client", 30.6)) == "REVIVE_CANCEL", "cancel")
    check(types(r:update(32.0)) == "", "Gnadenfrist")
    check(types(r:update(32.6)) == "GAME_OVER", "nach der Gnadenfrist")
end

-- Zwischensequenz: Liegende stehen automatisch auf, Frist pausiert
do
    local r = new_match()
    r:down("client", 0)
    local ev = r:cutscene(true, 5)
    check(types(ev) == "REVIVED" and ev[1].by == "auto", "auto revive")
    check(types(r:down("host", 6)) == "DOWNED", "faellt waehrend Sequenz")
    check(types(r:update(100)) == "", "keine Frist in der Sequenz")
    r:cutscene(false, 100)
    check(types(r:update(129)) == "", "Frist verschoben")
    check(types(r:update(130)) == "GAME_OVER", "Frist nach der Sequenz")
end

-- Verbindungsabbruch
do
    local r = new_match()
    r:down("client", 0)
    local ev = r:remove_player("client")
    check(types(ev) == "SOLO" and ev[1].pid == "host", "Liegender geht: Host spielt allein")
    check(not r:is_over(), "kein Game Over")

    r = new_match()
    r:down("client", 0)
    ev = r:remove_player("host")
    check(types(ev) == "SOLO,GAME_OVER", "Helfer geht: " .. types(ev))
end

-- Reset nach dem Laden
do
    local r = new_match()
    r:down("host", 0)
    r:update(40)
    check(r:is_over(), "over")
    r:reset()
    check(not r:is_over() and r:state("host") == "alive", "reset")
end

-- Gegner-Datensaetze
do
    check(enemy_net.RECORD_SIZE == 26, "Datensatz 26 Bytes, ist " .. enemy_net.RECORD_SIZE)
    local list = {}
    for i = 1, 40 do
        list[i] = { eid = i, x = i * 1.5, y = 0.25, z = -i, yaw = -3.1415, mode = 3, target = enemy_net.TARGET_CLIENT,
            bank = 2, motion = 1100, frame = 12.3 }
    end
    local data = enemy_net.pack_states(list)
    check(#data == 1 + 40 * 26, "Groesse")
    local back = assert(enemy_net.unpack_states(data))
    check(#back == 40, "Anzahl")
    local e = back[7]
    check(e.eid == 7 and math.abs(e.x - 10.5) < 1e-5 and math.abs(e.yaw + 3.1415) < 1e-4, "Werte")
    check(e.target == 2 and e.motion == 1100 and math.abs(e.frame - 12.3) < 1e-6, "Werte 2")
    check(enemy_net.unpack_states(data:sub(1, -2)) == nil, "kaputte Laenge erkannt")
    check(#enemy_net.unpack_states(enemy_net.pack_states({})) == 0, "leer")
end

-- Besitz pro Zone
do
    check(enemy_net.zone_owner(112, { 112, 113 }, 112) == "host", "Host hat Vorrang")
    check(enemy_net.zone_owner(113, { 112, 113 }, 200) == "host", "geladen beim Host")
    check(enemy_net.zone_owner(200, { 112 }, 200) == "client", "nur Mitspieler")
    check(enemy_net.zone_owner(300, { 112 }, 200) == "none", "niemand")
end

-- Mr. X: Zielwahl mit Hysterese
do
    local c = enemy_net.Chaser.new({ margin = 3, hold = 2, noise_hold = 8 })
    check(c:update({ host = 10, client = 20 }, 0) == "host", "naechster")
    check(c:update({ host = 10, client = 8 }, 1) == "host", "nur 2 m naeher: bleibt")
    check(c:update({ host = 10, client = 6 }, 2) == "host", "4 m naeher, aber erst seit 0 s")
    check(c:update({ host = 10, client = 6 }, 3.9) == "host", "erst 1,9 s")
    check(c:update({ host = 10, client = 6 }, 4) == "client", "Wechsel nach 2 s")
    c:noise("host", 5)
    check(c:update({ host = 30, client = 1 }, 10) == "host", "Laerm haelt das Ziel")
    check(c:update({ host = 30, client = 1 }, 13) == "host", "Hysterese nach dem Laerm")
    check(c:update({ host = 30, client = 1 }, 15) == "client", "danach Wechsel")
    check(c:update({ host = 5, client = nil }, 16) == "host", "Ziel unerreichbar: sofort wechseln")
end

print("re2r_coop_logic_test: ok")
