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

b:leave()
a:leave()
print("re2r_savejoin_test: alles ok")
