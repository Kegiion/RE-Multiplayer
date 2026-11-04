-- re2r_coop/game_adapter.lua
--
-- Alle Spielzugriffe fuer Gegner, Tod und Items (Konzept:
-- docs/re2r-konzept-gegner-tod-items.md). enemy_net.lua, revive.lua und
-- items_net.lua rufen das Spiel NUR ueber diese Funktionen auf.
--
-- ALLES HIER IST UNBESTAETIGT. Jede Funktion traegt die Nummer ihrer
-- Forschungsfrage (E = Gegner, T = Tod, I = Items). Solange sie nicht im
-- Spiel erforscht ist, gibt sie nil, "nicht erforscht (Nr.)" zurueck bzw.
-- registriert keinen Hook (Rueckgabe false). Die Forschung im Spiel ersetzt
-- nur den Rumpf und traegt die Nummer in `researched` ein.
--
-- Datenformen (vom Adapter geliefert bzw. erwartet):
--   enemy  = { ref = <Spielobjekt>, key = string|nil, kind = string,
--              x, y, z, yaw, hp, hp_max, mode, bank, motion, frame }
--   pose   = Datensatz aus enemy_net.unpack_states (x, y, z, yaw, mode, bank, motion, frame)
--   item   = { item_id = Zahl, count = Zahl, extra = Zahl, category = string|nil }
--   source = "local" (eigener Spieler), "partner" (Partner-Figur) oder "other"

local A = {}

-- Name der Funktion -> Forschungsnummer. Wird beim Erforschen gesetzt.
A.researched = {}

local function todo(nr)
    return nil, "nicht erforscht (" .. nr .. ")"
end

-- Ersetzt Funktionen (fuer Tests und fuer die Forschung im Spiel).
-- impl = { name = function ... }, nr = optionale Forschungsnummer
function A.install(impl, nr)
    for name, fn in pairs(impl) do
        assert(A[name] ~= nil and type(A[name]) == "function", "unbekannte Adapter-Funktion: " .. name)
        A[name] = fn
        A.researched[name] = nr or true
    end
end

-- Liste aller Adapter-Funktionen mit Forschungsnummer (fuer Menue/Diagnose).
A.LIST = {
    -- Gegner
    { "get_enemies", "E2" }, { "enemy_key", "E1" }, { "enemy_kind", "E3" },
    { "read_enemy", "E4/E13" }, { "set_enemy_hp", "E4" }, { "apply_damage", "E5" },
    { "kill_enemy", "E5" }, { "hook_enemy_damage", "E5/E6" }, { "freeze_ai", "E7" },
    { "set_enemy_pose", "E7/E13" }, { "mark_enemy_dead", "E8" }, { "set_chase_target", "E9" },
    { "loaded_zones", "E10" }, { "hook_player_damage", "E11" }, { "apply_player_damage", "E11" },
    { "find_chaser", "E14" }, { "hook_noise", "E14" },
    -- Tod
    { "get_player_hp", "T1" }, { "set_player_hp", "T1/T6" }, { "hook_player_death", "T1/T4" },
    { "set_downed", "T2" }, { "set_partner_downed", "T2" }, { "trigger_game_over", "T3" },
    { "in_cutscene", "T5" }, { "revive_button_held", "T7" },
    -- Items
    { "get_inventory", "I1" }, { "item_category", "I2" }, { "hook_item_pickup", "I3" },
    { "remove_world_item", "I4" }, { "give_item", "I5" }, { "put_in_box", "I5" },
    { "default_weapons", "I6" }, { "remove_item", "I8" }, { "hook_item_discard", "I8" },
    { "hook_host_saved", "I9" }, { "capture_inventory", "I1/I9" }, { "restore_inventory", "I1/I9" },
}

---------------------------------------------------------------------------
-- Gegner
---------------------------------------------------------------------------

-- E2: alle aktiven Gegner der Zone (Map.ID als Zahl) -> Liste von enemy.
function A.get_enemies(zone) return todo("E2") end

-- E1: stabile Kennung, in beiden Spielen gleich beim selben Stand. nil = keine.
function A.enemy_key(ref) return todo("E1") end

-- E3: Art des Gegners (z. B. Prefab-/GameObject-Name).
function A.enemy_kind(ref) return todo("E3") end

-- E4/E13: aktueller Zustand eines Gegners -> enemy (ohne ref) oder nil, wenn weg.
function A.read_enemy(ref) return todo("E4/E13") end

-- E4: Lebenspunkte setzen (Puppe beim Mitspieler, Uebernahme bei Rueckgabe).
function A.set_enemy_hp(ref, hp) return todo("E4") end

-- E5: Schaden ueber die Schadensverarbeitung des Spiels (Betaeuben, Umfallen,
-- Koerperteile wie gewohnt). part/weapon/flags wie in ENEMY_HIT.
function A.apply_damage(ref, damage, part, weapon, flags) return todo("E5") end

-- E5: Gegner sterben lassen (Puppe beim Mitspieler nach ENEMY_DEAD).
function A.kill_enemy(ref) return todo("E5") end

-- E5/E6: fn(ref, damage, part, weapon, flags, source) wird bei jedem Treffer an
-- einem Gegner gerufen. Gibt fn true zurueck, wird der Abzug verhindert
-- (SKIP_ORIGINAL), die Treffer-Reaktion soll trotzdem laufen.
function A.hook_enemy_damage(fn) return false end

-- E7: KI einfrieren (true) bzw. wieder laufen lassen (false), ohne dass der
-- Gegner verschwindet.
function A.freeze_ai(ref, frozen) return todo("E7") end

-- E7/E13: Position, Drehung und Animation einer eingefrorenen Puppe setzen.
function A.set_enemy_pose(ref, pose) return todo("E7/E13") end

-- E8: Gegner (stabile Kennung) in der eigenen Welt als tot eintragen, auch
-- wenn seine Zone nicht geladen ist.
function A.mark_enemy_dead(key, zone) return todo("E8") end

-- E9: Ziel der KI setzen: "host" (eigener Spieler) oder "client" (Partner-Figur).
function A.set_chase_target(ref, who) return todo("E9") end

-- E10: Zonen, die im eigenen Spiel geladen sind -> Liste von Map.ID-Zahlen.
function A.loaded_zones() return todo("E10") end

-- E11: fn(victim, damage, enemy_ref, kind, dir) bei Schaden an einer
-- Spielfigur. victim = "local" oder "partner". true = Abzug verhindern.
function A.hook_player_damage(fn) return false end

-- E11: dem eigenen Spieler Schaden zufuegen (nach PLAYER_HIT).
function A.apply_player_damage(damage, kind, dir) return todo("E11") end

-- E14: Mr. X finden -> ref oder nil (nicht in der Welt).
function A.find_chaser() return todo("E14") end

-- E14: fn(who) wenn ein Spieler Laerm macht, den Mr. X hoert ("host"/"client").
function A.hook_noise(fn) return false end

---------------------------------------------------------------------------
-- Tod
---------------------------------------------------------------------------

-- T1: Lebenspunkte des eigenen Spielers -> hp, hp_max.
function A.get_player_hp() return todo("T1") end

-- T1/T6: Lebenspunkte als Anteil (0..1) setzen, Danger-Zustand passend.
function A.set_player_hp(fraction) return todo("T1/T6") end

-- T1/T4: fn() wenn der eigene Spieler sterben wuerde. true = Tod verhindern
-- (Lebenspunkte bleiben bei 1, kein Game-Over-Bildschirm).
function A.hook_player_death(fn) return false end

-- T2: eigenen Spieler hinlegen (true) bzw. aufstehen lassen (false).
-- Liegend: keine Steuerung, kein Ziel fuer Gegner.
function A.set_downed(downed) return todo("T2") end

-- T2: Partner-Figur in der eigenen Welt hinlegen bzw. aufstehen lassen.
function A.set_partner_downed(downed) return todo("T2") end

-- T3: normales Game Over ausloesen. Rueckgabe: Speicherplatz, den
-- "Fortsetzen" laedt (oder -1).
function A.trigger_game_over() return todo("T3") end

-- T5: laeuft eine Zwischensequenz? Bestaetigt ist nur: Zone ist dann kurz
-- "Invalid" (research/README.md). Ein besseres Signal ist T5.
function A.in_cutscene()
    local ok, game = pcall(require, "re2r_coop.game")
    if not ok then
        return nil, "game.lua fehlt"
    end
    local okc, state = pcall(game.get_local_state)
    if not okc or state == nil then
        return nil, "kein Spieler"
    end
    return state.area == "Invalid"
end

-- T7: haelt der eigene Spieler die Aufheben-Taste?
function A.revive_button_held() return todo("T7") end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- I1: Inventar des eigenen Spielers -> Liste von item.
function A.get_inventory() return todo("I1") end

-- I2: Kategorie eines Items: "key", "consumable", "weapon" oder "other".
function A.item_category(item_id) return todo("I2") end

-- I3: fn(world_key, item_id, count, zone) wenn der eigene Spieler ein
-- Weltitem aufhebt (nach dem Aufheben, Item ist schon im Inventar).
function A.hook_item_pickup(fn) return false end

-- I4/I7: Weltitem (Kennung) in der eigenen Welt als aufgehoben markieren
-- und entfernen.
function A.remove_world_item(world_key, zone) return todo("I4") end

-- I5: Item ins Inventar legen. Rueckgabe true, oder nil, "full" bei vollem Inventar.
function A.give_item(item_id, count, extra) return todo("I5") end

-- I5: Item in die eigene Itemkiste legen.
function A.put_in_box(item_id, count, extra) return todo("I5") end

-- I6: Startwaffen der Figur (SurvivorType) -> Liste von item.
function A.default_weapons(character) return todo("I6") end

-- I8: Item aus dem Inventar entfernen ("wird nicht mehr benoetigt").
function A.remove_item(item_id) return todo("I8") end

-- I8: fn(item_id) wenn das Spiel ein Schluessel-Item wegwirft.
function A.hook_item_discard(fn) return false end

-- I9: fn(slot) wenn der eigene Spieler speichert (Schreibmaschine, Autosave).
function A.hook_host_saved(fn) return false end

-- I1/I9: eigenes Inventar und Itemkiste als Daten (z. B. die Teile
-- InventoryManager/ItemLockerManager aus savestate.capture_live).
function A.capture_inventory() return todo("I1/I9") end

-- I1/I9: Daten aus capture_inventory wieder einspielen.
function A.restore_inventory(data) return todo("I1/I9") end

-- Status fuer Menue/Diagnose: Liste { name, nr, erforscht }.
function A.status()
    local out = {}
    for _, e in ipairs(A.LIST) do
        out[#out + 1] = { name = e[1], nr = e[2], researched = A.researched[e[1]] ~= nil }
    end
    return out
end

return A
