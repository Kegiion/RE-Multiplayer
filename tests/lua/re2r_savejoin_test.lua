-- RE2: Join auf den Spielstand des Hosts (re2r_coop/savejoin.lua) ueber zwei
-- echte Sessions, ohne Spiel (Einsammeln und Einspielen sind ersetzt).
local AUTORUN = assert(os.getenv("REMULTIPLAYER_RE2R_AUTORUN"), "Umgebungsvariable REMULTIPLAYER_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

sdk = {} -- game.lua fragt sdk.game_namespace ab; Spielzugriffe sind hier ersetzt
local Session = require("remultiplayer_coop.session")
local transfer = require("remultiplayer_coop.transfer")
local savejoin = require("re2r_coop.savejoin")
local i18n = require("remultiplayer_coop.i18n")
assert(i18n.set_setting("de")) -- Meldungen unten auf Deutsch geprueft
local PORT = 47941

-- Ein Spielstand, gross genug fuer mehrere Stuecke
local parts = {}
for i = 1, 32 do
    local items = {}
    for k = 1, 400 do
        items[k] = { t = "app.ropeway.gamemastering.InventoryManager.ItemData", id = i * 1000 + k, f = { Count = k, Pos = { v3 = { k * 0.5, 0, -k } } } }
    end
    parts[i] = { t = "app.ropeway.Part" .. i, id = i, f = { Hash = 1000 + i, Items = { t = "System.Collections.Generic.List`1<x>", id = 99000 + i, l = items, n = #items } } }
end
local captures = 0
savejoin.capture = function()
    captures = captures + 1
    return parts
end
local applied_list, applied_parts
savejoin.apply = function(list, p)
    applied_list, applied_parts = list, p
    return { stats = { parts = #p, vars = 3490, failed = 2 }, errors = {} }
end

local a = Session.new({ net = net_a, game = "re2r", name = "Leon" })
local b = Session.new({ net = net_b, game = "re2r", name = "Claire" })
a:on("SAVE_REQUEST", function(s, peer) savejoin.on_request(s, peer) end)
b:on("SAVE_BEGIN", function(s, _, msg) savejoin.on_begin(s, msg) end)
b:on("SAVE_CHUNK", function(s, _, msg) savejoin.on_chunk(s, msg) end)
assert(a:host(PORT))
assert(b:join("127.0.0.1", PORT))

local function pump(cond, seconds)
    local deadline = net_a.time() + seconds
    while net_a.time() < deadline and not cond() do
        a:update()
        b:update()
        savejoin.update(a)
        sleep_ms(5)
    end
end

pump(function() return #a:ready_peers() > 0 and #b:ready_peers() > 0 end, 3)
assert(#b:ready_peers() > 0, "keine Verbindung")

-- Freund fordert an -> Host schickt in Stuecken -> Freund hat den Stand bereit
savejoin.request(b)
assert(savejoin.state == "requested")
pump(function() return savejoin.state == "ready" or savejoin.state == "failed" end, 10)
assert(savejoin.state == "ready", "Stand nicht empfangen: " .. savejoin.state .. " " .. savejoin.message)
assert(captures == 1)
assert(#savejoin.outgoing == 0, "Host sendet noch")
assert(savejoin.progress() == 1)
local got = savejoin.pending
assert(#got == 32 and got[32].f.Hash == 1032, "Teile falsch")
assert(got[5].f.Items.n == 400 and got[5].f.Items.l[400].f.Pos.v3[3] == -400, "Inhalt falsch")
assert(#b.log_lines > 0)

-- mehrere Stuecke? (sonst testet das nichts)
local serial = require("remultiplayer_coop.serial")
assert(#serial.encode(parts) > 3 * transfer.CHUNK_SIZE, "Testdaten zu klein")

-- Laden: wird eingespielt, danach nichts mehr ausstehend
local fake_list = {}
savejoin.on_load(fake_list)
assert(applied_list == fake_list and applied_parts == got)
assert(savejoin.state == "applied" and savejoin.pending == nil)
assert(savejoin.message:find("3490 Variablen") and savejoin.message:find("2 nicht"), savejoin.message)
-- Anzeige folgt einem Sprachwechsel, ohne neu einzuspielen
i18n.set_setting("en")
assert(savejoin.text() == "Host's save applied (32 parts, 3490 variables, 2 not taken over).", savejoin.text())
i18n.set_setting("de")
assert(savejoin.text() == savejoin.message)
applied_list = nil
savejoin.on_load(fake_list)
assert(applied_list == nil, "zweites Laden hat erneut eingespielt")

-- Host kann nicht einsammeln -> Freund bekommt eine Meldung
savejoin.capture = function() error("kein Spieler") end
savejoin.request(b)
pump(function() return savejoin.state == "failed" end, 5)
assert(savejoin.state == "failed" and savejoin.message:find("keinen Spielstand"), savejoin.message)

-- Host noch im Titel -> Freund wartet und fragt spaeter von selbst neu an
savejoin.capture = function() return parts end
local host_main = 3
local real_main_state = savejoin.main_state
savejoin.main_state = function() return host_main end
savejoin.request(b)
pump(function() return savejoin.state == "waiting_host" end, 5)
assert(savejoin.state == "waiting_host", savejoin.state .. " " .. savejoin.message)
local t0 = net_a.time()
savejoin.update_auto(t0)
assert(savejoin.state == "waiting_host", "zu frueh neu angefragt")
host_main = 6 -- Host hat geladen
savejoin.update_auto(t0 + savejoin.RETRY_INTERVAL + 0.1)
assert(savejoin.state == "requested", "nicht neu angefragt: " .. savejoin.state)
pump(function() return savejoin.state == "ready" end, 10)
assert(savejoin.state == "ready", "nach dem Warten nicht empfangen: " .. savejoin.state)
savejoin.main_state = real_main_state

-- nicht angeforderte Uebertragung wird ignoriert
savejoin.cancel()
savejoin.on_begin(b, { transfer = 1, size = 10, chunks = 1, checksum = 0, info = "" })
assert(savejoin.state == "idle" and savejoin.receiver == nil)

-- --- Eigene Figur und Inventar (Aufbau wie im Spiel, 5. November 2026) ------
local items_net = require("re2r_coop.items_net")
local next_id = 500000
local function obj(t, f)
    next_id = next_id + 1
    return { t = t, id = next_id, f = f }
end
local function list(t, items)
    next_id = next_id + 1
    return { t = t, id = next_id, l = items, n = #items }
end
local function prim(item, weapon, bullet, count)
    return obj("app.ropeway.gamemastering.InventoryManager.PrimitiveItem",
        { ItemId = item, WeaponId = weapon, BulletId = bullet, Count = count, WeaponParts = 0 })
end
local function exdata()
    return obj("app.ropeway.gamemastering.InventoryManager.ItemExData",
        { ExItemID = 7, ExUintData = 0, InitialCount = 0, IsInitialSet = true, RogueWeaponLevel = 0 })
end
local function inv_data(survivor, filled)
    local stocks = {}
    for i = 0, 19 do
        local d = filled[i] or { 0, -1, 0, 1 }
        stocks[i + 1] = obj("app.ropeway.gamemastering.InventoryManager.StockItem", {
            Index = i, IsWeaponEquip = filled[i] ~= nil and d[2] ~= -1,
            DefaultItem = prim(d[1], d[2], d[3], d[4]), AdditionalItem = prim(0, -1, 0, 1), ExData = exdata(),
        })
    end
    local shortcuts = {}
    for i = 1, 4 do
        shortcuts[i] = obj("app.ropeway.inventory.ShortcutSlotData", { _Index = i == 1 and 0 or -1, _LastWeaponType = i == 1 and 1 or -1, _ShortcutKind = 0 })
    end
    local sub_stock = obj("app.ropeway.gamemastering.InventoryManager.StockItem", {
        Index = 0, DefaultItem = prim(0, -1, 0, 1), AdditionalItem = prim(0, -1, 0, 1), ExData = exdata(),
    })
    return obj("app.ropeway.inventory.Data", {
        _SurvivorType = survivor, _CurrentSlotSize = survivor == -1 and 8 or 10,
        _Stocks = list("System.Collections.Generic.List`1<StockItem>", stocks),
        _MainData = obj("app.ropeway.inventory.MainSlotData", { _Index = 0, _LastWeaponType = 1 }),
        _ShortcutDataList = list("System.Collections.Generic.List`1<ShortcutSlotData>", shortcuts),
        _SubShortcutDataList = list("System.Collections.Generic.List`1<ShortcutSlotData>", {}),
        _SubData = obj("app.ropeway.inventory.SubSlotData", { _LastWeaponType = -1, _Stock = sub_stock }),
    })
end
local function host_parts(survivor)
    local box_items = {}
    for i = 1, 400 do
        local d = i == 1 and { 0, 85, 15, 0 } or (i == 3 and { 2, -1, 0, 1 } or { 0, -1, 0, 1 })
        box_items[i] = obj("app.ropeway.gamemastering.InventoryManager.ItemData", {
            DefaultItem = prim(d[1], d[2], d[3], d[4]), AdditionalItem = prim(0, -1, 0, 1), ExData = exdata(),
        })
    end
    -- Leon: Matilda, Item 77, Pistolenmunition 15, Schrotpatronen 16, Waffe W-870 (11), Kraut 2
    local leon = inv_data(survivor, { [0] = { 0, 1, 15, 11 }, [1] = { 77, -1, 0, 1 }, [2] = { 15, -1, 0, 24 },
        [3] = { 16, -1, 0, 7 }, [4] = { 0, 11, 16, 5 }, [6] = { 2, -1, 0, 1 } })
    local p = {
        obj("app.ropeway.gamemastering.MainFlowManager.GameHeaderSaveData", {
            SurvivorTypeValue = survivor, ScenarioTypeValue = 0, GameStartTicks = 639292452450000000, FirstSaveTicks = 639292452660000000 }),
        obj("app.ropeway.CostumeManager.GameSaveData", { Hash = 1 }),
        obj("app.ropeway.gamemastering.InventoryManager.SaveData", {
            DataLists = list("System.Collections.Generic.List`1<app.ropeway.inventory.Data>", { inv_data(-1, {}), leon }) }),
        obj("app.ropeway.gamemastering.ItemLockerManager.GameSaveData", {
            SaveData = obj("app.ropeway.gimmick.action.GimmickItemLockerControl.ItemLockerSaveData", {
                _Items = list("System.Collections.Generic.List`1<ItemData>", box_items) }) }),
        obj("app.ropeway.PlayerManager.GameSaveData", { PlayerType = survivor * 1000 }),
    }
    -- Verweis wie im Spiel: Kurzwahl-Liste des Nebenplatzes zeigt auf dieselbe Liste
    leon.f._SubShortcutDataList = { ref = leon.f._ShortcutDataList.id }
    return p
end
local function inv_of(p, survivor)
    local items = savejoin.read_inventory(p, survivor)
    local s = {}
    for _, it in ipairs(items) do
        s[#s + 1] = string.format("%d:%d/%d/%d/%d", it.slot, it.item, it.weapon, it.bullet, it.count)
    end
    return table.concat(s, " ")
end

-- Startausstattung: Claire bekommt JMB Hp3, keine Leon-Waffen, nur passende Munition
local kit = items_net.join_inventory(savejoin.read_inventory(host_parts(0), 0), items_net.CLAIRE, 10)
assert(#kit == 4 and kit[1].weapon == 3 and kit[1].bullet == 15, "Startwaffe falsch")
assert(kit[2].item == 77 and kit[3].item == 15 and kit[3].count == 24 and kit[4].item == 2, "Host-Items falsch")
assert(#items_net.join_inventory(kit, items_net.CLAIRE, 2) == 2, "Platzgrenze")
-- Story-Items stehen vor den anderen, die Platzgrenze schneidet sie nicht ab
local k2 = items_net.join_inventory({ { item = 2 }, { item = 15, count = 5 }, { item = 120 } }, items_net.CLAIRE, 2)
assert(#k2 == 2 and k2[2].item == 120, "Story-Item abgeschnitten")
assert(items_net.is_story_item(77) and not items_net.is_story_item(15))
assert(items_net.partner_character(0) == 1 and items_net.partner_character(1) == 0)

-- Join Leon -> Claire: Header, PlayerType, Inventar, Kiste, Kostuem
local memory = {}
savejoin.store = { load = function() return memory.data end, save = function(t) memory.data = t end }
local p = host_parts(0)
local info = savejoin.prepare_partner(p)
assert(info.character == 1 and info.source == "start" and info.items == 4 and info.box == 0, "prepare_partner")
assert(savejoin.host_character(p) == 1, "Header nicht Claire")
local pm
for _, x in ipairs(p) do
    assert(not x.t:find("CostumeManager"), "Kostuem des Hosts nicht entfernt")
    if x.t:find("PlayerManager") then pm = x end
end
assert(pm.f.PlayerType == 1000)
assert(inv_of(p, 1) == "0:0/3/15/13 1:77/-1/0/1 2:15/-1/0/24 3:2/-1/0/1", inv_of(p, 1))
assert(#savejoin.read_box(p) == 0, "Kiste nicht leer")
assert(savejoin.joined.character == 1 and savejoin.joined.key == "639292452450000000_639292452660000000")
local claire = p[2].f.DataLists.l[1]
assert(claire.f._SurvivorType == 1 and claire.f._CurrentSlotSize == 10, "Platzzahl nicht vom Host")
assert(claire.f._MainData.f._Index == 0 and claire.f._MainData.f._LastWeaponType == 3)
assert(claire.f._Stocks.l[1].f.ExData.f.ExItemID == 0 and claire.f._Stocks.l[1].f.IsWeaponEquip == false)
assert(claire.f._ShortcutDataList.l[1].f._LastWeaponType == 3, "Kurzwahl")
-- Host spielt Claire -> Freund wird Leon mit Matilda
local p2 = host_parts(1)
assert(savejoin.prepare_partner(p2).character == 0 and inv_of(p2, 0):find("^0:0/1/15/12"), inv_of(p2, 0))

-- Lade-Hook mit Header: Meldung nennt die Figur
savejoin.apply = function(_, pp) return { stats = { parts = #pp, vars = 1, failed = 0 }, errors = {} } end
savejoin.pending = host_parts(0)
savejoin.on_load({})
assert(savejoin.state == "applied" and savejoin.result.kit.character == 1)
assert(savejoin.message:find("Claire") and savejoin.message:find("Startausstattung"), savejoin.message)

-- HOST_SAVED: Freund sichert sein Inventar (hat inzwischen Schrotflinte, Kiste belegt)
local own = host_parts(1) -- Inventar-Eintrag 1 = Claires
savejoin.capture_own = function() return own end
savejoin.main_state = function() return savejoin.MAIN_IN_GAME end
assert(savejoin.on_host_saved(nil), "nicht gesichert")
local copy = savejoin.load_copy(savejoin.joined.key)
assert(copy.character == 1 and #copy.items == 6 and #copy.box == 2 and copy.box[2].slot == 2, "Kopie falsch")
-- Game Over -> erneutes Beitreten: gesichertes Inventar statt Startausstattung
savejoin.pending = host_parts(0)
savejoin.on_load({})
assert(savejoin.result.kit.source == "copy" and savejoin.message:find("gesichert"), savejoin.message)
local p3 = host_parts(0)
savejoin.prepare_partner(p3)
assert(inv_of(p3, 1) == "0:0/1/15/11 1:77/-1/0/1 2:15/-1/0/24 3:16/-1/0/7 4:0/11/16/5 6:2/-1/0/1", inv_of(p3, 1))
assert(#savejoin.read_box(p3) == 2)
-- anderes Host-Spiel: keine Kopie
local p4 = host_parts(0)
p4[1].f.GameStartTicks = 1
assert(savejoin.prepare_partner(p4).source == "start")
-- ohne Einspielen wird nichts gesichert
savejoin.state = "idle"
assert(not savejoin.on_host_saved(nil))
savejoin.main_state = real_main_state

-- Host meldet Speichern an alle
local got_saved = false
b:on("HOST_SAVED", function() got_saved = true end)
a.is_host = true
savejoin.host_saved = true
savejoin.update(a)
pump(function() return got_saved end, 3)
assert(got_saved and savejoin.host_saved == false, "HOST_SAVED nicht angekommen")

b:leave()
a:leave()
print("re2r_savejoin_test: alles ok")
