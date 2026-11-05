-- re2r_coop/savejoin.lua
--
-- Join auf den Spielstand des Hosts. Der Freund fragt mit SAVE_REQUEST an,
-- der Host sammelt seinen Live-Stand ein (savestate.capture_live), wandelt ihn
-- in Bytes (remultiplayer_coop.serial) und schickt ihn in Stuecken
-- (SAVE_BEGIN/SAVE_CHUNK, remultiplayer_coop.transfer). Der Freund laedt danach
-- einen beliebigen eigenen Spielstand, beim Laden wird der Stand des Hosts auf
-- die frisch eingelesenen Objekte gespielt (Pre-Hook auf
-- SaveDataManager.loadGameSaveData, savestate.apply_to_list).
--
-- Bestaetigt am 3. November 2026 ohne Netzwerk (gleicher PC): Live-Stand der
-- Eingangshalle beim Laden der Strasse eingespielt -> Spieler steht exakt dort.
-- UNBESTAETIGT: Uebertragung zwischen zwei PCs, Spielstaende verschiedener
-- Konten, Raetsel-Daten generischer Typen (siehe research/README.md).

local transfer = require("remultiplayer_coop.transfer")
local serial = require("remultiplayer_coop.serial")
local savestate = require("re2r_coop.savestate")
local game = require("re2r_coop.game")
local tr = require("re2r_coop.text")

local M = {}

M.CHUNKS_PER_FRAME = 8     -- Host: so viele Stuecke je Frame senden (8 KB je Stueck)

-- Zustand beim Freund:
--   idle -> requested -> receiving -> ready (Stand liegt bereit, Laden abwarten)
--   -> applied | failed
M.state = "idle"
M.message = ""       -- Meldung in der Sprache beim Setzen (Log, Tests)
M.message_key = nil  -- Textschluessel (join.*) oder rohe Meldung, siehe M.text()
M.message_params = nil
M.receiver = nil
M.pending = nil      -- Teile, die beim naechsten Laden eingespielt werden
M.result = nil       -- stats/errors des letzten Einspielens

-- Host: laufende Sendungen { peer=, begin=, chunks=, next= }
M.outgoing = {}

-- Meldung setzen: Schluessel plus Werte merken, damit M.text() nach einem
-- Sprachwechsel neu uebersetzt. Unbekannte Schluessel (rohe Texte, z. B. vom
-- Host) kommen unveraendert zurueck.
local function say(key, params)
    M.message_key, M.message_params = key, params
    M.message = key ~= nil and tr(key, params) or ""
end

-- Meldung fuer die Anzeige in der aktuellen Sprache.
function M.text()
    if M.message_key == nil then
        return M.message
    end
    return tr(M.message_key, M.message_params)
end

-- Austauschbar fuer Tests.
M.capture = function()
    return savestate.capture_live()
end
M.apply = function(list, parts)
    return savestate.apply_to_list(list, parts)
end

local next_transfer = os.time() % 100000

-- Beschreibung des Host-Stands fuer die Anzeige beim Freund.
local function describe()
    local ok, ls = pcall(game.get_local_state)
    if not ok or ls == nil then
        return ""
    end
    return string.format("%s, %s", game.character_name(ls.character), tostring(ls.area))
end

-- --- Host --------------------------------------------------------------------

-- Antwort, wenn der Host noch nicht im Spiel ist (der Freund fragt dann
-- regelmaessig nach). Im Titel eingesammelt hat der Stand keinen gueltigen
-- Ort (LoadLocation 0), das Laden beim Freund haengt dann bei 10 %
-- (bestaetigt am 4. November 2026 mit dem Testbot-Spiegel).
M.HOST_NOT_READY = "Host ist noch nicht im Spiel"
-- Antwort, wenn der Host nichts einsammeln kann. Beide Texte gehen so ueber
-- das Netz (Feld info) und bleiben fuer aeltere Versionen unveraendert; der
-- Freund zeigt sie uebersetzt an.
M.HOST_NO_SAVE = "Host hat keinen Spielstand"
M.RETRY_INTERVAL = 5.0

function M.on_request(session, peer)
    local main = M.main_state()
    if main ~= nil and main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE then
        session:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = M.HOST_NOT_READY }, true, peer.id)
        return
    end
    local ok, parts = pcall(M.capture)
    if not ok then
        session:logt("join.log_capture_failed", { name = peer.name or "?", error = tostring(parts) })
        session:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = M.HOST_NO_SAVE }, true, peer.id)
        return
    end
    local data = serial.encode(parts)
    next_transfer = (next_transfer + 1) % 4294967296
    local begin, chunks = transfer.split(data, next_transfer, describe())
    session:send("SAVE_BEGIN", begin, true, peer.id)
    M.outgoing[#M.outgoing + 1] = { peer = peer.id, begin = begin, chunks = chunks, next = 1 }
    session:logt("join.log_sending", { name = peer.name or "?", kb = #data // 1024, info = begin.info })
end

-- Jeden Frame: ausstehende Stuecke verteilt senden, Speichern melden.
function M.update(session)
    if M.host_saved then
        M.send_host_saved(session)
    end
    for i = #M.outgoing, 1, -1 do
        local out = M.outgoing[i]
        for _ = 1, M.CHUNKS_PER_FRAME do
            local c = out.chunks[out.next]
            if c == nil then
                break
            end
            session:send("SAVE_CHUNK", c, true, out.peer)
            out.next = out.next + 1
        end
        if out.next > #out.chunks then
            table.remove(M.outgoing, i)
        end
    end
end

function M.forget_peer(peer_id)
    for i = #M.outgoing, 1, -1 do
        if M.outgoing[i].peer == peer_id then
            table.remove(M.outgoing, i)
        end
    end
end

-- --- Freund ------------------------------------------------------------------

function M.request(session)
    M.state, M.receiver, M.pending, M.result = "requested", nil, nil, nil
    say("join.wait_host")
    M.auto_retry_at, M.loader, M.session = nil, nil, session
    session:send("SAVE_REQUEST", { reserved = 0 }, true)
end

function M.cancel()
    M.state, M.receiver, M.pending, M.loader = "idle", nil, nil, nil
    say(nil)
end

local function finish(session)
    local data, err = M.receiver:result()
    M.receiver = nil
    if data == nil then
        M.state = "failed"
        say("join.transfer_failed", { error = tostring(err) })
        session:logt("join.log_failed", { text = M.message })
        return
    end
    local parts, derr = serial.decode(data)
    if parts == nil then
        M.state = "failed"
        say("join.unreadable", { error = tostring(derr) })
        session:logt("join.log_failed", { text = M.message })
        return
    end
    M.pending = parts
    M.state = "ready"
    say("join.received")
    session:logt("join.log_received", { kb = #data // 1024 })
end

function M.on_begin(session, msg)
    if M.state ~= "requested" and M.state ~= "receiving" then
        return -- nicht angefragt
    end
    if msg.size == 0 then
        if msg.info == M.HOST_NOT_READY then
            M.state = "waiting_host"
            say("join.wait_host_save")
            M.request_at = nil -- update_auto setzt die naechste Anfrage
            return
        end
        M.state = "failed"
        say((msg.info == "" or msg.info == M.HOST_NO_SAVE) and "join.host_no_save" or msg.info)
        return
    end
    M.receiver = transfer.receiver(msg)
    M.state = "receiving"
    say("join.receiving_from", { info = msg.info })
    if M.receiver:complete() then
        finish(session)
    end
end

function M.on_chunk(session, msg)
    if M.state ~= "receiving" or M.receiver == nil then
        return
    end
    if M.receiver:add(msg) and M.receiver:complete() then
        finish(session)
    end
end

function M.progress()
    if M.receiver ~= nil then
        return M.receiver:progress()
    end
    return M.state == "ready" and 1 or 0
end

-- --- Eigene Figur, eigenes Inventar (Freund) ----------------------------------
--
-- Bestaetigt am 5. November 2026 im Spiel: Die Figur steht im Spielstand in
-- MainFlowManager.GameHeaderSaveData.SurvivorTypeValue (0 Leon, 1 Claire).
-- Wird sie vor dem Einspielen umgeschrieben, laedt der Freund als Claire in
-- Leons Welt (Szenario bleibt das des Hosts). Das Inventar steht je Figur in
-- InventoryManager.SaveData.DataLists (_SurvivorType, _Stocks mit 20
-- Plaetzen, _CurrentSlotSize), die Itemkiste in ItemLockerManager
-- (SaveData._Items, 400 Plaetze, eine Kiste fuer alle). Das Kostuem
-- (CostumeManager) bleibt das des Freundes.
-- Regeln (User): andere Hauptfigur als der Host, Startausstattung nach
-- items_net.join_inventory, eigene Kiste leer. Speichert der Host
-- (HOST_SAVED), sichert der Freund Inventar und Kiste lokal und bekommt sie
-- beim naechsten Beitreten in dasselbe Host-Spiel zurueck (z. B. nach Game Over).

M.COPY_FILE = "re2r_coop_inventory.json" -- unter reframework/data
M.COPY_MAX = 8                           -- so viele Host-Spiele merken
M.joined = nil                           -- { key =, character = } nach dem Einspielen

M.CHARACTER_NAMES = { [0] = "Leon", [1] = "Claire" }

local EMPTY = { item = 0, weapon = -1, bullet = 0, count = 1, parts = 0 }

-- Knoten nach id (fuer Verweise { ref = id }) ueber alle Teile.
local function index_nodes(parts)
    local idx, seen = {}, {}
    local function walk(n)
        if type(n) ~= "table" or seen[n] then
            return
        end
        seen[n] = true
        if n.id ~= nil and n.ref == nil then
            idx[n.id] = n
        end
        for _, v in pairs(n) do
            walk(v)
        end
    end
    walk(parts)
    return idx
end

local function deref(idx, n)
    if type(n) == "table" and n.ref ~= nil then
        return idx[n.ref]
    end
    return n
end

-- Eintraege einer Liste/eines Arrays als Lua-Liste 1..n (Luecken = nil).
local function entries(idx, node)
    node = deref(idx, node)
    local items = node and (node.l or node.a)
    local out = {}
    if items == nil then
        return out, 0
    end
    local n = node.n or #items
    for i = 1, n do
        out[i] = deref(idx, items[i])
    end
    return out, n
end

local function find_part(parts, needle)
    for _, p in ipairs(parts) do
        if type(p.t) == "string" and p.t:find(needle, 1, true) then
            return p
        end
    end
    return nil
end

local function read_prim(idx, node)
    local f = (deref(idx, node) or {}).f or {}
    return { item = f.ItemId or 0, weapon = f.WeaponId or -1, bullet = f.BulletId or 0, count = f.Count or 1, parts = f.WeaponParts or 0 }
end

local function write_prim(idx, node, it)
    local n = deref(idx, node)
    if n == nil or n.f == nil then
        return false
    end
    n.f.ItemId, n.f.WeaponId, n.f.BulletId = it.item or 0, it.weapon or -1, it.bullet or 0
    n.f.Count, n.f.WeaponParts = it.count or 1, it.parts or 0
    return true
end

local function is_empty(it)
    return (it.item or 0) == 0 and (it.weapon or -1) == -1
end

-- Figur im Header eines Stands (nil, wenn kein Header dabei ist).
function M.host_character(parts)
    local h = find_part(parts, "GameHeaderSaveData")
    return h and h.f and h.f.SurvivorTypeValue
end

-- Schluessel des Host-Spiels (Spielbeginn laut Header), nil ohne Header.
function M.game_key(parts)
    local h = find_part(parts, "GameHeaderSaveData")
    local f = h and h.f
    if f == nil or f.GameStartTicks == nil then
        return nil
    end
    return string.format("%s_%s", tostring(f.GameStartTicks), tostring(f.FirstSaveTicks))
end

-- Inventar-Eintrag (inventory.Data) einer Figur, nil wenn es keinen gibt.
local function inventory_entry(idx, parts, survivor)
    local inv = find_part(parts, "InventoryManager.SaveData")
    if inv == nil or inv.f == nil then
        return nil
    end
    local list = entries(idx, inv.f.DataLists)
    for _, data in pairs(list) do
        if data.f ~= nil and data.f._SurvivorType == survivor then
            return data, list
        end
    end
    return nil, list
end

-- Belegte Inventarplaetze einer Figur: Liste von Items mit slot (0..),
-- dazu die Platzzahl (_CurrentSlotSize).
function M.read_inventory(parts, survivor)
    local idx = index_nodes(parts)
    local data = inventory_entry(idx, parts, survivor)
    if data == nil then
        return {}, nil
    end
    local items = {}
    for i, stock in pairs((entries(idx, data.f._Stocks))) do
        local it = stock.f and read_prim(idx, stock.f.DefaultItem)
        if it ~= nil and not is_empty(it) then
            it.slot = stock.f.Index or (i - 1)
            items[#items + 1] = it
        end
    end
    table.sort(items, function(a, b) return a.slot < b.slot end)
    return items, data.f._CurrentSlotSize
end

-- Belegte Plaetze der Itemkiste (mit slot 0..399).
function M.read_box(parts)
    local idx = index_nodes(parts)
    local box = find_part(parts, "ItemLockerManager")
    local sd = box and box.f and deref(idx, box.f.SaveData)
    local out = {}
    if sd == nil or sd.f == nil then
        return out
    end
    local list, n = entries(idx, sd.f._Items)
    for i = 1, n do
        local e = list[i]
        local it = read_prim(idx, e and e.f and e.f.DefaultItem)
        if e ~= nil and not is_empty(it) then
            it.slot = i - 1
            out[#out + 1] = it
        end
    end
    return out
end

-- Items auf Plaetze verteilen: mit slot an diese Stelle, sonst der Reihe nach.
local function place(items, count)
    local by_slot, next_free = {}, 0
    for _, it in ipairs(items or {}) do
        if it.slot ~= nil and it.slot >= 0 and it.slot < count and by_slot[it.slot] == nil then
            by_slot[it.slot] = it
        end
    end
    for _, it in ipairs(items or {}) do
        if not (it.slot ~= nil and by_slot[it.slot] == it) then
            while next_free < count and by_slot[next_free] ~= nil do
                next_free = next_free + 1
            end
            if next_free < count then
                by_slot[next_free] = it
            end
        end
    end
    return by_slot
end

local function clear_slot(idx, node)
    local n = deref(idx, node)
    if n == nil or n.f == nil then
        return
    end
    write_prim(idx, n.f.AdditionalItem, EMPTY)
    local ex = deref(idx, n.f.ExData)
    if ex ~= nil and ex.f ~= nil then
        ex.f.ExItemID, ex.f.ExUintData, ex.f.InitialCount = 0, 0, 0
        ex.f.IsInitialSet, ex.f.RogueWeaponLevel = false, 0
    end
    if n.f.IsWeaponEquip ~= nil then
        n.f.IsWeaponEquip = false
    end
end

-- Schreibt den Stand des Hosts fuer den Freund um (in place):
-- opts.character = eigene Figur, opts.items = Inventar, opts.box = Kiste.
-- Gibt { character, items, box } zurueck (Zahlen der geschriebenen Items).
function M.adapt_parts(parts, opts)
    local idx = index_nodes(parts)
    local me, host = opts.character, M.host_character(parts)
    local info = { character = me, items = 0, box = 0 }

    local header = find_part(parts, "GameHeaderSaveData")
    if header ~= nil and header.f ~= nil then
        header.f.SurvivorTypeValue = me
    end
    -- PlayerType: live 0 bei Leon, 1000 bei Claire (das Spiel setzt ihn
    -- selbst aus der Figur, bestaetigt am 5. November 2026)
    local pm = find_part(parts, "PlayerManager.GameSaveData")
    if pm ~= nil and pm.f ~= nil and pm.f.PlayerType ~= nil then
        pm.f.PlayerType = me * 1000
    end

    -- Inventar: eigener Eintrag, sonst der unbenutzte (-1), sonst der des Hosts
    local data, list = inventory_entry(idx, parts, me)
    if data == nil then
        data = inventory_entry(idx, parts, -1) or inventory_entry(idx, parts, host)
    end
    if data == nil then
        for _, d in pairs(list or {}) do
            data = data or (d.f ~= nil and d or nil)
        end
    end
    if data ~= nil then
        local hd = host ~= me and inventory_entry(idx, parts, host)
        data.f._SurvivorType = me
        if hd and hd ~= data and hd.f._CurrentSlotSize ~= nil then
            data.f._CurrentSlotSize = hd.f._CurrentSlotSize
        end
        local stocks, n = entries(idx, data.f._Stocks)
        local size = math.min(n, data.f._CurrentSlotSize or n)
        local slots = place(opts.items, size)
        local first_weapon
        for i = 1, n do
            local stock = stocks[i]
            if stock ~= nil and stock.f ~= nil then
                local slot = stock.f.Index or (i - 1)
                local it = slots[slot] or EMPTY
                write_prim(idx, stock.f.DefaultItem, it)
                clear_slot(idx, stock)
                if slots[slot] ~= nil then
                    info.items = info.items + 1
                    if first_weapon == nil and (it.weapon or -1) ~= -1 then
                        first_weapon = { slot = slot, weapon = it.weapon }
                    end
                end
            end
        end
        -- Ausgeruestete Waffe, Kurzwahl und Nebenwaffe zurueck auf die neuen Plaetze
        local main = deref(idx, data.f._MainData)
        if main ~= nil and main.f ~= nil then
            main.f._Index = first_weapon and first_weapon.slot or -1
            main.f._LastWeaponType = first_weapon and first_weapon.weapon or -1
        end
        for _, key in ipairs({ "_SubShortcutDataList", "_ShortcutDataList" }) do
            for i, sc in pairs((entries(idx, data.f[key]))) do
                if sc.f ~= nil then
                    local use = key == "_ShortcutDataList" and i == 1 and first_weapon
                    sc.f._Index = use and first_weapon.slot or -1
                    sc.f._LastWeaponType = use and first_weapon.weapon or -1
                end
            end
        end
        local sub = deref(idx, data.f._SubData)
        if sub ~= nil and sub.f ~= nil then
            sub.f._LastWeaponType = -1
            local st = deref(idx, sub.f._Stock)
            if st ~= nil and st.f ~= nil then
                write_prim(idx, st.f.DefaultItem, EMPTY)
                clear_slot(idx, st)
            end
        end
    end

    -- Itemkiste: leer bzw. die gesicherte Kopie
    local box = find_part(parts, "ItemLockerManager")
    local sd = box and box.f and deref(idx, box.f.SaveData)
    if sd ~= nil and sd.f ~= nil then
        local items, n = entries(idx, sd.f._Items)
        local slots = place(opts.box, n)
        for i = 1, n do
            local e = items[i]
            if e ~= nil and e.f ~= nil then
                write_prim(idx, e.f.DefaultItem, slots[i - 1] or EMPTY)
                clear_slot(idx, e)
                if slots[i - 1] ~= nil then
                    info.box = info.box + 1
                end
            end
        end
    end

    -- Kostuem: das eigene behalten (Teil fehlt -> bleibt beim Einspielen stehen)
    for i = #parts, 1, -1 do
        if type(parts[i].t) == "string" and parts[i].t:find("CostumeManager", 1, true) then
            table.remove(parts, i)
        end
    end
    return info
end

-- Gesicherte Kopien (Datei unter reframework/data). Austauschbar fuer Tests.
M.store = {
    load = function()
        if json == nil then
            return nil
        end
        local ok, t = pcall(json.load_file, M.COPY_FILE)
        return ok and t or nil
    end,
    save = function(t)
        if json ~= nil then
            pcall(json.dump_file, M.COPY_FILE, t)
        end
    end,
}

function M.load_copy(key)
    local all = M.store.load()
    local c = type(all) == "table" and type(all.games) == "table" and all.games[key] or nil
    return type(c) == "table" and c or nil
end

function M.save_copy(key, copy)
    local all = M.store.load()
    if type(all) ~= "table" or type(all.games) ~= "table" then
        all = { games = {} }
    end
    copy.saved = os.time()
    all.games[key] = copy
    -- nur die neuesten COPY_MAX Host-Spiele behalten
    local keys = {}
    for k, c in pairs(all.games) do
        keys[#keys + 1] = { k = k, t = type(c) == "table" and c.saved or 0 }
    end
    table.sort(keys, function(a, b) return a.t > b.t end)
    for i = M.COPY_MAX + 1, #keys do
        all.games[keys[i].k] = nil
    end
    M.store.save(all)
end

-- Vor dem Einspielen: Figur und Inventar fuer den Freund setzen. Ohne Header
-- (z. B. Tests) bleibt der Stand unveraendert, Rueckgabe nil.
function M.prepare_partner(parts)
    local host = M.host_character(parts)
    if host == nil then
        return nil
    end
    local items_net = require("re2r_coop.items_net")
    local me = items_net.partner_character(host)
    local key = M.game_key(parts)
    local copy = key and M.load_copy(key)
    local items, box, source
    -- leere Listen kommen aus der JSON-Datei als nil zurueck
    if copy ~= nil and copy.character == me then
        items, box, source = copy.items or {}, copy.box or {}, "copy"
    else
        local host_items, size = M.read_inventory(parts, host)
        items, box, source = items_net.join_inventory(host_items, me, size), {}, "start"
    end
    local info = M.adapt_parts(parts, { character = me, items = items, box = box })
    info.source, info.key = source, key
    M.joined = { key = key, character = me }
    return info
end

-- Austauschbar fuer Tests: eigenes Inventar und eigene Kiste live einsammeln.
M.capture_own = function()
    local parts = {}
    for _, name in ipairs({ "gamemastering.InventoryManager", "gamemastering.ItemLockerManager" }) do
        local m = sdk.get_managed_singleton(game.ns(name))
        local data = m and m:call("saveGameSaveData")
        if data ~= nil then
            parts[#parts + 1] = savestate.snapshot(data)
        end
    end
    return parts
end

-- HOST_SAVED beim Freund: Inventar und Kiste fuer dieses Host-Spiel sichern.
function M.on_host_saved(session)
    if M.joined == nil or M.joined.key == nil or M.state ~= "applied" then
        return false
    end
    local main = M.main_state()
    if main ~= nil and main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE then
        return false
    end
    local ok, own = pcall(M.capture_own)
    if not ok or own == nil then
        return false
    end
    local items = M.read_inventory(own, M.joined.character)
    local box = M.read_box(own)
    M.save_copy(M.joined.key, { character = M.joined.character, items = items, box = box })
    if session ~= nil then
        session:logt("join.log_inventory_saved", { items = #items, box = #box })
    end
    return true
end

-- Host: Speichern im Spiel (Schreibmaschine, Auto-Speichern) melden.
M.host_saved = false
function M.send_host_saved(session)
    if M.host_saved and session ~= nil and session.is_host then
        session:send("HOST_SAVED", { slot = -1, session_id = 0 }, true)
    end
    M.host_saved = false
end

-- Wird vom Lade-Hook mit der frisch eingelesenen GameSaveDataList aufgerufen.
function M.on_load(list)
    local parts = M.pending
    if parts == nil then
        return
    end
    M.pending = nil
    local ok_p, kit = pcall(M.prepare_partner, parts)
    local ok, ctx = pcall(M.apply, list, parts)
    if not ok then
        M.state = "failed"
        say("join.apply_failed", { error = tostring(ctx) })
        return
    end
    M.result = ctx
    M.state = "applied"
    local s = ctx.stats
    if not ok_p then
        ctx.errors = ctx.errors or {}
        ctx.errors[#ctx.errors + 1] = "Figur/Inventar: " .. tostring(kit)
    elseif kit ~= nil then
        ctx.kit = kit
        say(kit.source == "copy" and "join.applied_copy" or "join.applied_start", {
            character = M.CHARACTER_NAMES[kit.character] or tostring(kit.character), items = kit.items, failed = s.failed,
        })
        return
    end
    say("join.applied", { parts = s.parts, vars = s.vars, failed = s.failed })
end

-- Pre-Hook auf SaveDataManager.loadGameSaveData (nur im Spiel).
function M.install_hook()
    if M.hooked or sdk == nil or sdk.hook == nil then
        return false
    end
    local td = sdk.find_type_definition(game.ns("gamemastering.SaveDataManager"))
    local method = td and td:get_method("loadGameSaveData")
    if method == nil then
        return false
    end
    sdk.hook(method, function(args)
        if M.pending == nil then
            return
        end
        local ok, err = pcall(function()
            local self = sdk.to_managed_object(args[2])
            local list = self:get_field("GameSaveDataValue"):get_field("GameSaveDataList")
            M.on_load(list)
        end)
        if not ok then
            M.pending = nil
            M.state = "failed"
            say("join.load_hook", { error = tostring(err) })
        end
    end, function(retval)
        return retval
    end)
    -- Host speichert (Schreibmaschine bzw. automatisch). UNBESTAETIGT, ob
    -- beide Methoden bei jedem Speichern laufen.
    for _, name in ipairs({ "requestSaveGameData", "requestSaveGameDataAuto" }) do
        local m = td:get_method(name)
        if m ~= nil then
            sdk.hook(m, function()
                M.host_saved = true
                M.host_saved_count = (M.host_saved_count or 0) + 1
            end, function(retval)
                return retval
            end)
        end
    end
    M.hooked = true
    return true
end

-- --- Automatisch laden (Freund) ----------------------------------------------
--
-- Bestaetigt am 3. November 2026: Aus dem laufenden Spiel direkt
-- goLoadGameData aufzurufen haengt (der Hauptablauf steht noch auf IN_GAME).
-- Funktioniert: goResetGameToStoryContinue (zurueck zum Titel, MainState 3),
-- dann requestLoadGameData(Modus, Platz), warten bis die Datei gelesen ist
-- (saveLoadStep wieder 1), dann MainFlowManager.goLoadGameData -> nach ca.
-- 2,4 s IN_GAME (6). Steuerung danach normal.
--
-- Bestaetigt am 4. November 2026: Aus dem Titelmenue (MainState 3) geht
-- dasselbe ohne Zuruecksetzen, auch aus dem Hauptmenue (GUI_MenuMain). Das
-- Spiel laedt, aber die gerade offenen Menues (GUI_MenuMain, GUI_TitleMenu,
-- GUI_GeneralGuide ...) bleiben ueber dem Spiel stehen. Das war beim ersten
-- echten Test "haengt im Titelmenue". Das Spiel selbst blendet seine Menues
-- ueber Behavior.enableObject(false) aus (DrawSelf und UpdateSelf aus), das
-- machen wir nach dem Laden mit allen Titel-Menues auch.
-- TitleFlow.StateValue = TITLE_SAVEDATA_LOAD_END (27) zu setzen bewirkt
-- dagegen nichts.

M.MAIN_TITLE = 3
M.MAIN_IN_GAME = 6
M.MAIN_PAUSE = 9
M.LOAD_TIMEOUT = 60

-- Menues des Titelbildschirms, die nach dem Laden weg muessen.
M.TITLE_GUIS = {
    GUI_TitleMenu = true, GUI_MenuMain = true, GUI_MenuStory = true, GUI_Load = true,
    GUI_MenuScenario = true, GUI_TitleFirst = true, GUI_TitleL = true, GUI_TitleR = true,
    GUI_GeneralGuide = true, GUI_SelectDifficulty = true, GUI_Costume = true,
}

M.auto = false       -- setzt das Hauptskript aus der Konfiguration
M.loader = nil       -- laufender automatischer Ladevorgang

local function managers()
    local mfm = sdk.get_managed_singleton(game.ns("gamemastering.MainFlowManager"))
    local sdm = sdk.get_managed_singleton(game.ns("gamemastering.SaveDataManager"))
    return mfm, sdm
end

local function main_state(mfm)
    return mfm:get_field("_CurrentMainState")
end

-- Hauptzustand des Spiels (3 = Titel, 6 = im Spiel, 9 = Pause) oder nil.
function M.main_state()
    if sdk == nil or sdk.get_managed_singleton == nil then
        return nil
    end
    local mfm = managers()
    return mfm and main_state(mfm) or nil
end

-- Blendet alle noch sichtbaren Titel-Menues aus. Gibt die Namen zurueck.
function M.hide_title_menus()
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local guis = scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
    local hidden = {}
    for _, c in ipairs(guis and guis:get_elements() or {}) do
        local go = c:call("get_GameObject")
        local name = go:call("get_Name")
        if M.TITLE_GUIS[name] and go:call("get_DrawSelf") then
            local done = false
            for _, comp in ipairs(go:call("get_Components"):get_elements()) do
                local tn = comp:get_type_definition():get_full_name()
                if tn:find("Behavior$") then
                    done = pcall(comp.call, comp, "enableObject(System.Boolean)", false)
                    break
                end
            end
            if not done or go:call("get_DrawSelf") then
                go:call("set_DrawSelf", false)
                go:call("set_UpdateSelf", false)
            end
            hidden[#hidden + 1] = name
        end
    end
    return hidden
end

-- Neuester belegter Speicherplatz (SaveDataManager.getSaveFileDetailList,
-- bestaetigt am 4. November 2026: get_Slot = Platz fuer requestLoadGameData,
-- leere Plaetze sind nil) oder nil.
function M.newest_slot(sdm, mode)
    local list = sdm:call("getSaveFileDetailList", mode)
    if list == nil then
        return nil
    end
    local best, best_time
    for i = 0, list:call("get_Count") - 1 do
        local d = list:call("get_Item", i)
        if d ~= nil and not d:call("get_EmptyData") then
            local t = d:call("get_LastUpdateTimeStamp")
            if best_time == nil or (t ~= nil and t > best_time) then
                best, best_time = d:call("get_Slot"), t
            end
        end
    end
    return best
end

-- Startet das automatische Laden (Stand muss bereitliegen). Geht im Spiel,
-- in der Pause und im Titelbildschirm (auch in dessen Untermenues).
function M.start_auto_load(now)
    local mfm, sdm = managers()
    if mfm == nil or sdm == nil then
        M.state = "failed"
        say("join.game_not_ready")
        return false
    end
    local main = main_state(mfm)
    if main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE and main ~= M.MAIN_TITLE then
        say("join.wait_game")
        return false
    end
    local ok, mode = pcall(sdm.call, sdm, "getSaveModeFromCurrentScenarioType")
    mode = ok and mode or 1
    local index = sdm:get_field("<LoadGameDataIndex>k__BackingField")
    if index == nil or index < 0 then
        local ok_slot, slot = pcall(M.newest_slot, sdm, mode)
        index = ok_slot and slot or nil
    end
    if index == nil or index < 0 then
        say("join.no_own_save")
        return false
    end
    local phase = main == M.MAIN_TITLE and "title" or "reset"
    M.loader = { phase = phase, since = now, start = now, index = index, mode = mode }
    say("join.loading")
    return true
end

local function step_loader(now)
    local L = M.loader
    local mfm, sdm = managers()
    local main = main_state(mfm)
    if now - L.start > M.LOAD_TIMEOUT then
        M.loader = nil
        M.state = "failed"
        say("join.load_timeout", { state = tostring(main) })
        return
    end
    if L.phase == "reset" then
        if main == M.MAIN_TITLE then
            L.phase, L.since = "title", now
        elseif not L.reset_called then
            L.reset_called = true
            mfm:call("goResetGameToStoryContinue")
        end
    elseif L.phase == "title" then
        -- Titel kurz zur Ruhe kommen lassen (nach dem Zuruecksetzen)
        if now - L.since >= (L.reset_called and 1.0 or 0.1) then
            sdm:call("requestLoadGameData", L.mode, L.index)
            L.phase, L.since, L.saw_read = "read", now, false
        end
    elseif L.phase == "read" then
        local step = sdm:call("get_saveLoadStep")
        if step ~= 1 then
            L.saw_read = true
        end
        -- Ist im Titel "Spiel laden" offen, laedt das Spiel nach
        -- requestLoadGameData selbst weiter (TitleFlow FINALIZE, MainState 4,
        -- bestaetigt am 4. November 2026). Dann kein zweites goLoadGameData.
        if main ~= M.MAIN_TITLE and main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE then
            L.phase, L.since = "loading", now
        elseif now - L.since >= 0.3 and ((L.saw_read and step == 1) or now - L.since > 3.0) then
            mfm:call("goLoadGameData")
            L.phase, L.since = "loading", now
        end
    elseif L.phase == "loading" then
        if main == M.MAIN_IN_GAME and game.get_local_state() ~= nil then
            pcall(M.hide_title_menus)
            M.loader = nil
        end
    end
end

-- Jeden Frame (Freund): automatisch anfordern war schon, hier laden.
function M.update_auto(now)
    -- Host war noch nicht im Spiel: regelmaessig neu anfragen.
    if M.state == "waiting_host" and M.session ~= nil then
        M.request_at = M.request_at or (now + M.RETRY_INTERVAL)
        if now >= M.request_at then
            M.request_at = nil
            local session = M.session
            M.request(session)
            say("join.wait_host_save")
        end
        return
    end
    if M.loader ~= nil then
        local ok, err = pcall(step_loader, now)
        if not ok then
            M.loader = nil
            M.state = "failed"
            say("join.auto_load_failed", { error = tostring(err) })
        end
        return
    end
    -- Startet, sobald das Spiel bereit ist (sonst alle 2 s neu pruefen).
    if M.auto and M.state == "ready" and M.pending ~= nil and now >= (M.auto_retry_at or 0) then
        if not M.start_auto_load(now) then
            M.auto_retry_at = now + 2.0
        end
    end
end

return M
