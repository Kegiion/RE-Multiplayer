-- RE2: Gegner-, Tod- und Item-Abgleich ohne Spiel. Host und Mitspieler
-- laufen gegen einen nachgebauten Adapter (re2r_coop/game_adapter.lua),
-- alle Nachrichten gehen durch protocol.encode/decode.
local AUTORUN = assert(os.getenv("REMULTIPLAYER_RE2R_AUTORUN"), "Umgebungsvariable REMULTIPLAYER_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

sdk = {} -- game.lua fragt sdk.game_namespace ab; Spielzugriffe sind hier ersetzt
local protocol = require("remultiplayer_coop.protocol")
local game_adapter = require("re2r_coop.game_adapter")
local enemy_net = require("re2r_coop.enemy_net")
local revive = require("re2r_coop.revive")
local items_net = require("re2r_coop.items_net")

local function check(cond, msg)
    if not cond then error(msg, 2) end
end

-- ---- Adapter-Standard: alles "nicht erforscht" ---------------------------
do
    local seen = {}
    for _, e in ipairs(game_adapter.LIST) do
        local name, nr = e[1], e[2]
        check(type(game_adapter[name]) == "function", "Adapter-Funktion fehlt: " .. name)
        check(not seen[name], "doppelt: " .. name)
        seen[name] = true
        if name:match("^hook_") then
            check(game_adapter[name](function() end) == false, name .. " darf ohne Forschung nichts anmelden")
        elseif name ~= "in_cutscene" then
            local v, err = game_adapter[name]()
            check(v == nil and err == "nicht erforscht (" .. nr .. ")", name .. ": " .. tostring(err))
        end
    end
    -- in_cutscene nutzt die bestaetigte Invalid-Zone; ohne Spieler: nil
    check(game_adapter.in_cutscene() == nil, "in_cutscene ohne Spiel")
    check(not pcall(game_adapter.install, { gibt_es_nicht = function() end }), "unbekannte Funktion abgelehnt")
    for _, s in ipairs(game_adapter.status()) do
        check(s.researched == false, "nichts erforscht: " .. s.name)
    end
end

-- ---- Nachgebauter Adapter -------------------------------------------------
local function fake_adapter()
    local A = { calls = {}, hooks = {}, enemies = {}, held = false, cutscene = false }
    for _, e in ipairs(game_adapter.LIST) do
        local name = e[1]
        if name:match("^hook_") then
            A[name] = function(fn) A.hooks[name] = fn; return true end
        else
            A[name] = function(...)
                A.calls[#A.calls + 1] = { name, ... }
                return nil, "fake"
            end
        end
    end
    local function find(ref)
        for _, list in pairs(A.enemies) do
            for _, e in ipairs(list) do
                if e.ref == ref then return e end
            end
        end
    end
    A.get_enemies = function(zone)
        local out = {}
        for _, e in ipairs(A.enemies[zone] or {}) do
            if not e.gone then out[#out + 1] = e end
        end
        return out
    end
    A.read_enemy = function(ref) return find(ref) end
    A.apply_damage = function(ref, dmg)
        A.calls[#A.calls + 1] = { "apply_damage", ref, dmg }
        local e = find(ref)
        e.hp = e.hp - dmg
        return true
    end
    A.revive_button_held = function() return A.held end
    A.in_cutscene = function() return A.cutscene end
    return A
end

local function calls(A, name)
    local out = {}
    for _, c in ipairs(A.calls) do
        if c[1] == name then out[#out + 1] = c end
    end
    return out
end

-- Verbindung: Nachrichten gehen kodiert zur Gegenseite
local function link()
    local L = { q = { host = {}, client = {} }, count = {} }
    function L.sender(from)
        local to = from == "host" and "client" or "host"
        return function(name, data, reliable)
            local msg = assert(protocol.decode(protocol.encode(name, data)))
            table.insert(L.q[to], msg)
            L.count[name] = (L.count[name] or 0) + 1
        end
    end
    function L.deliver(to, obj, now, ctx)
        local q = L.q[to]
        L.q[to] = {}
        for _, msg in ipairs(q) do
            obj:handle(msg, now, ctx)
        end
        return #q
    end
    return L
end

-- ---- Gegner ----------------------------------------------------------------
do
    check(enemy_net.match_enemy({ key = "", kind = "zombie", x = 0, y = 0, z = 0 },
        { { ref = "a", kind = "zombie", x = 3, y = 0, z = 0 }, { ref = "b", kind = "zombie", x = 1, y = 0, z = 0 } }).ref == "b",
        "naechster derselben Art")
    check(enemy_net.match_enemy({ key = "", kind = "zombie", x = 0, y = 0, z = 0 },
        { { ref = "a", kind = "licker", x = 0.1, y = 0, z = 0 } }) == nil, "andere Art")
    check(enemy_net.match_enemy({ key = "", kind = "zombie", x = 0, y = 0, z = 0 },
        { { ref = "a", kind = "zombie", x = 0.5, y = 0, z = 0 } }, { a = true }) == nil, "schon vergeben")
    local ho = assert(enemy_net.unpack_handover(enemy_net.pack_handover({ { key = "k9", x = 1, y = 2, z = 3, hp = 40, dead = true } })))
    check(ho[1].key == "k9" and ho[1].hp == 40 and ho[1].dead, "Handover")
    check(enemy_net.unpack_handover("x") == nil, "kaputte Rueckgabe erkannt")

    local L = link()
    local HA, CA = fake_adapter(), fake_adapter()
    HA.enemies[112] = {
        { ref = "h1", key = "k1", kind = "zombie", x = 1, y = 0, z = 1, yaw = 0.5, hp = 100, hp_max = 100, bank = 1, motion = 160, frame = 3 },
        { ref = "h2", key = "k2", kind = "licker", x = 5, y = 0, z = 5, yaw = 0, hp = 200, hp_max = 200 },
    }
    CA.enemies[112] = {
        { ref = "c1", key = "k1", kind = "zombie", x = 1.2, y = 0, z = 1, hp = 100 },
        { ref = "c2", key = "k2", kind = "licker", x = 5.5, y = 0, z = 5, hp = 200 },
        { ref = "c3", key = "k3", kind = "zombie", x = 9, y = 0, z = 9, hp = 100, gone = true },
    }
    local host = enemy_net.Sync.new({ role = "host", send = L.sender("host"), adapter = HA })
    local client = enemy_net.Sync.new({ role = "client", send = L.sender("client"), adapter = CA })
    host:install()
    client:install()
    local together = { host_zones = { 112 }, client_zone = 112, host_pos = { x = 0, y = 0, z = 0 }, client_pos = { x = 2, y = 0, z = 2 } }

    host:update(0, together)
    client:update(0, together)
    check(L.count.ENEMY_SPAWN == 2 and L.count.ENEMY_STATE == 1, "Host meldet 2 Gegner")
    check(next(client.owned_zones) == nil, "Mitspieler besitzt die gemeinsame Zone nicht")
    L.deliver("client", client, 0)
    check(#calls(CA, "freeze_ai") == 2, "beide Puppen eingefroren")
    local pose = calls(CA, "set_enemy_pose")
    check(#pose == 2 and pose[1][2] == "c1" and pose[1][3].motion == 160, "Pose der Puppe gesetzt")

    -- Mitspieler trifft die Puppe c1: Abzug lokal verhindert, Host zieht ab
    check(CA.hooks.hook_enemy_damage("c1", 30, 2, 2000, 0, "local") == true, "Abzug an der Puppe verhindert")
    L.deliver("host", host, 0.05, together)
    check(#calls(HA, "apply_damage") == 1 and HA.enemies[112][1].hp == 70, "Host zieht 30 ab")
    -- Schuss der Partner-Figur beim Host zaehlt nicht
    check(HA.hooks.hook_enemy_damage("h1", 50, 0, 0, 0, "partner") == true, "Partner-Schaden unterdrueckt")
    check(HA.hooks.hook_enemy_damage("h1", 10, 0, 0, 0, "local") == false, "eigener Schuss zaehlt normal")
    -- Unplausibler Treffer
    CA.hooks.hook_enemy_damage("c1", 99999, 0, 0, 0, "local")
    L.deliver("host", host, 0.06, together)
    check(host.stats.hits_rejected == 1 and #calls(HA, "apply_damage") == 1, "unplausibler Treffer abgelehnt")

    host:update(0.1, together)
    L.deliver("client", client, 0.1)
    local hp = calls(CA, "set_enemy_hp")
    check(hp[#hp][2] == "c1" and hp[#hp][3] == 70, "Lebenspunkte an die Puppe")

    -- Tod
    HA.enemies[112][1].hp = 0
    host:update(0.2, together)
    L.deliver("client", client, 0.2)
    check(#calls(CA, "kill_enemy") == 1 and calls(CA, "kill_enemy")[1][2] == "c1", "Puppe stirbt")
    check(#calls(HA, "mark_enemy_dead") == 0, "Host traegt eigene Tode nicht extra ein")

    -- Gegner trifft die Partner-Figur beim Host
    check(HA.hooks.hook_player_damage("partner", 20, "h2", 0, 1.5) == true, "Partner-Schaden beim Host verhindert")
    check(HA.hooks.hook_player_damage("local", 20, "h2", 0, 1.5) == false, "eigener Schaden normal")
    L.deliver("client", client, 0.3)
    local ph = calls(CA, "apply_player_damage")
    check(#ph == 1 and ph[1][2] == 20, "Mitspieler nimmt den Schaden")

    -- Trennung: Host geht in Zone 113, Mitspieler bleibt in 112
    HA.enemies[113] = {}
    for _, e in ipairs(HA.enemies[112]) do e.gone = true end -- Zone beim Host entladen
    local apart = { host_zones = { 113 }, client_zone = 112, host_pos = { x = 0, y = 0, z = 0 }, client_pos = { x = 2, y = 0, z = 2 } }
    host:update(1.0, apart)
    L.deliver("client", client, 1.0)
    local unfreeze = {}
    for _, c in ipairs(calls(CA, "freeze_ai")) do
        if c[3] == false then unfreeze[#unfreeze + 1] = c[2] end
    end
    check(#unfreeze == 1 and unfreeze[1] == "c2", "Host gibt die Puppe frei")
    client:update(1.5, apart)
    check(client.owned_zones[112], "Mitspieler leiht sich Zone 112")
    check(client.own_by_ref.c2 >= 32768, "eigene Kennungen ab 32768")
    L.deliver("host", host, 1.5, apart)

    -- Mitspieler toetet c2 in seiner Zone -> Host traegt den Tod ein
    CA.enemies[112][2].hp = 0
    client:update(1.6, apart)
    L.deliver("host", host, 1.6, apart)
    local md = calls(HA, "mark_enemy_dead")
    check(#md == 1 and md[1][2] == "k2" and md[1][3] == 112, "Tod in die Host-Welt eingetragen")

    -- Rueckgabe: Host kommt zurueck, c3 ist angeschossen
    CA.enemies[112][3].gone, CA.enemies[112][3].hp = false, 40
    client:update(1.7, apart)
    for _, e in ipairs(HA.enemies[112]) do e.gone = false end
    HA.enemies[112][3] = { ref = "h3", key = "k3", kind = "zombie", x = 9, y = 0, z = 9, hp = 100, hp_max = 100 }
    host:update(2.0, together)
    L.deliver("client", client, 2.0)
    client:update(2.05, together)
    check(not client.owned_zones[112], "Mitspieler gibt die Zone zurueck")
    L.deliver("host", host, 2.05, together)
    local sh = calls(HA, "set_enemy_hp")
    check(#sh == 1 and sh[1][2] == "h3" and sh[1][3] == 40, "Lebenspunkte aus der Rueckgabe")

    -- Mr. X
    HA.find_chaser = function() return "mx" end
    HA.enemies[200] = { { ref = "mx", kind = "mrx", x = 10, y = 0, z = 0, hp = 1 } }
    local near_client = { host_zones = { 112 }, client_zone = 112, host_pos = { x = 8, y = 0, z = 0 }, client_pos = { x = 0, y = 0, z = 0 } }
    host:update(3.0, near_client) -- Host ist naeher
    near_client.host_pos, near_client.client_pos = { x = 0, y = 0, z = 0 }, { x = 9, y = 0, z = 0 }
    host:update(3.1, near_client)
    host:update(4.0, near_client)
    host:update(5.2, near_client)
    local tgt = calls(HA, "set_chase_target")
    check(#tgt == 2 and tgt[1][3] == "host" and tgt[2][3] == "client", "Mr. X wechselt zum Mitspieler")
    near_client.client_zone = 300
    host:update(5.3, near_client)
    tgt = calls(HA, "set_chase_target")
    check(tgt[#tgt][3] == "host", "Mitspieler ausserhalb der geladenen Zonen: zurueck zum Host")
end

-- ---- Tod und Wiederbeleben -------------------------------------------------
do
    local L = link()
    local HA, CA = fake_adapter(), fake_adapter()
    HA.trigger_game_over = function() HA.calls[#HA.calls + 1] = { "trigger_game_over" }; return 21 end
    local over_reason, over_slot
    local host = revive.Controller.new({ role = "host", send = L.sender("host"), adapter = HA })
    local client = revive.Controller.new({ role = "client", send = L.sender("client"), adapter = CA,
        on_game_over = function(r, s) over_reason, over_slot = r, s end })
    host:install()
    client:install()
    check(CA.hooks.hook_player_death() == false, "ohne Mitspieler normaler Tod")
    host:peer_joined()
    client:peer_joined()

    -- Mitspieler faellt, Host hebt ihn auf
    check(CA.hooks.hook_player_death() == true, "Tod verhindert")
    check(calls(CA, "set_downed")[1][2] == true and client.state.client == "down", "Mitspieler liegt")
    L.deliver("host", host, 1)
    check(host.state.client == "down" and calls(HA, "set_partner_downed")[1][2] == true, "Host sieht ihn liegen")
    L.deliver("client", client, 1)
    HA.held = true
    host:update(2, { partner_distance = 3 })
    check(host.state.client == "down", "zu weit weg")
    host:update(2, { partner_distance = 1 })
    check(host.state.client == "reviving", "Aufheben laeuft")
    host:update(5, { partner_distance = 1 })
    check(host.state.client == "alive", "aufgehoben")
    L.deliver("client", client, 5)
    check(client.state.client == "alive", "Mitspieler steht")
    local hp = calls(CA, "set_player_hp")
    check(#hp == 1 and hp[1][2] == 0.3, "30 % Lebenspunkte")
    HA.held = false
    host:update(5.1, { partner_distance = 1 })

    -- Host faellt, Mitspieler hebt ihn auf
    check(HA.hooks.hook_player_death() == true, "Host-Tod verhindert")
    L.deliver("client", client, 6)
    check(client.state.host == "down", "Mitspieler sieht Host liegen")
    CA.held = true
    client:update(7, { partner_distance = 1 })
    check(L.count.REVIVE_REQUEST == 1, "Anfrage geschickt")
    client:update(7.5, { partner_distance = 1 })
    check(L.count.REVIVE_REQUEST == 1, "nur einmal")
    L.deliver("host", host, 7.5)
    host:update(10.5, {})
    check(host.state.host == "alive", "Host aufgehoben")
    check(calls(HA, "set_player_hp")[1][2] == 0.3, "Host 30 %")
    L.deliver("client", client, 10.5)
    check(client.state.host == "alive" and not client.helping, "Mitspieler fertig")
    CA.held = false

    -- Zwischensequenz: Liegender steht automatisch auf
    CA.hooks.hook_player_death()
    L.deliver("host", host, 11)
    HA.cutscene = true
    host:update(12, {})
    L.deliver("client", client, 12)
    check(client.state.client == "alive" and #calls(CA, "set_player_hp") == 2, "automatisch aufgestanden")
    HA.cutscene = false
    host:update(13, {})

    -- Beide fallen: Game Over fuer beide, Platz des Hosts
    CA.hooks.hook_player_death()
    L.deliver("host", host, 14)
    HA.hooks.hook_player_death()
    check(host.game_over and #calls(HA, "trigger_game_over") == 1, "Host Game Over")
    L.deliver("client", client, 14)
    check(client.game_over and #calls(CA, "trigger_game_over") == 1, "Mitspieler Game Over")
    check(over_reason == "both_down" and over_slot == 21, "Platz des Hosts: " .. tostring(over_slot))
    check(HA.hooks.hook_player_death() == false, "nach Game Over normales Spiel")
    host:reset()
    client:reset()
    check(host.state.host == "alive" and not client.game_over, "reset")

    -- Frist laeuft ab
    CA.hooks.hook_player_death()
    L.deliver("host", host, 20)
    host:update(49, {})
    check(not host.game_over, "Frist noch nicht um")
    host:update(50, {})
    L.deliver("client", client, 50)
    check(host.game_over and over_reason == "bleedout", "Frist abgelaufen")
    host:reset()
    client:reset()

    -- Verbindungsabbruch, waehrend der Mitspieler liegt
    CA.hooks.hook_player_death()
    client:peer_left(60)
    check(client.game_over, "liegend allein: Game Over")
    L.deliver("host", host, 60)
    host:peer_left(61)
    check(not host.game_over and host.state.client == "alive", "Host spielt allein weiter")
    check(client:flags() == revive.FLAG_DOWN, "Flags am Boden")
end

-- ---- Items -------------------------------------------------------------------
do
    local L = link()
    local HA, CA = fake_adapter(), fake_adapter()
    local cats = { [1] = "weapon", [2] = "consumable", [3] = "key", [100] = "consumable", [200] = "key" }
    for _, A in ipairs({ HA, CA }) do
        A.item_category = function(id) return cats[id] end
    end
    local host = items_net.Sync.new({ role = "host", send = L.sender("host"), adapter = HA, session_id = 0xABCD })
    local client = items_net.Sync.new({ role = "client", send = L.sender("client"), adapter = CA })
    host:install()
    client:install()

    -- Host hebt Munition auf: verschwindet beim Mitspieler
    HA.hooks.hook_item_pickup("w1", 100, 15, 112)
    L.deliver("client", client, 0)
    local rw = calls(CA, "remove_world_item")
    check(#rw == 1 and rw[1][2] == "w1" and rw[1][3] == 112, "Weltitem beim Mitspieler entfernt")
    check(L.count.ITEM_GRANT == nil, "Munition nicht geteilt")

    -- Mitspieler hebt einen Schluessel auf: verschwindet beim Host, Host bekommt ihn
    CA.give_item = function(...) CA.calls[#CA.calls + 1] = { "give_item", ... }; return true end
    HA.give_item = function(...) HA.calls[#HA.calls + 1] = { "give_item", ... }; return true end
    CA.hooks.hook_item_pickup("w2", 200, 1, 112)
    L.deliver("host", host, 1)
    check(calls(HA, "remove_world_item")[1][2] == "w2", "Weltitem beim Host entfernt")
    check(calls(HA, "give_item")[1][2] == 200, "Host bekommt den Schluessel")
    L.deliver("client", client, 1)
    check(#calls(CA, "remove_world_item") == 1, "Bestaetigung entfernt nichts doppelt")

    -- Gleichzeitig: beide behalten
    HA.hooks.hook_item_pickup("w3", 100, 5, 112)
    CA.hooks.hook_item_pickup("w3", 100, 5, 112)
    L.deliver("host", host, 2)
    check(host.stats.conflicts == 1 and #calls(HA, "remove_world_item") == 1, "Konflikt ohne Zurueckdrehen")
    L.deliver("client", client, 2)

    -- Inventar voll: Schluessel in die Kiste
    CA.give_item = function() return nil, "full" end
    CA.put_in_box = function(...) CA.calls[#CA.calls + 1] = { "put_in_box", ... }; return true end
    HA.hooks.hook_item_pickup("w4", 3, 1, 112)
    L.deliver("client", client, 3)
    check(calls(CA, "put_in_box")[1][2] == 3 and #client.notices == 1, "in die Kiste")

    -- Schluessel nicht mehr benoetigt
    HA.hooks.hook_item_discard(3)
    HA.hooks.hook_item_discard(100)
    L.deliver("client", client, 4)
    local ri = calls(CA, "remove_item")
    check(#ri == 1 and ri[1][2] == 3, "nur Schluessel werden mit weggeworfen")

    -- Host speichert: Mitspieler sichert sein Inventar
    CA.capture_inventory = function() return { "inventar-v1" } end
    local restored
    CA.restore_inventory = function(d) restored = d; return true end
    HA.hooks.hook_host_saved(21)
    L.deliver("client", client, 5)
    check(client.last_saved.slot == 21 and client.last_saved.session_id == 0xABCD, "Kopie gemerkt")
    check(client:restore(0xABCD, 21) == true and restored[1] == "inventar-v1", "Inventar zurueck")
    check(client:restore(0xABCD, 3) == false, "keine Kopie fuer anderen Platz")

    -- Startausstattung
    CA.default_weapons = function(character) return character == 1 and { { item_id = 9, count = 1 } } or {} end
    local kit = items_net.starting_kit({ { item_id = 1 }, { item_id = 2, count = 30 }, { item_id = 3 }, { item_id = 4 } }, 1, CA)
    local ids = {}
    for i, it in ipairs(kit.inventory) do ids[i] = it.item_id end
    check(table.concat(ids, ",") == "9,2,3,4", "Startausstattung: " .. table.concat(ids, ","))
    check(kit.inventory[2].count == 30 and #kit.box == 0, "Munition bleibt, Kiste leer")

    -- Handkorrektur hat Vorrang
    items_net.OVERRIDES[100] = "key"
    check(items_net.is_key(100, CA), "Korrektur")
    items_net.OVERRIDES[100] = nil
    check(items_net.classify(555, fake_adapter()) == "unknown", "ohne Forschung unbekannt")
end

print("re2r_coop_net_test: ok")
