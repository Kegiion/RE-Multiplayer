-- Laedt das RE0-Koop-Skript in einer nachgebauten REMods-Runtime-Umgebung:
-- json.lua (echt), Speicher-Werkzeug mit Fake-Speicher, Verbindung mit einem
-- zweiten (reinen Lua-)Spieler.
-- Erwartet: REMODS_RE0HD_LUA = Pfad zu games/re0hd/lua
local RE0 = assert(os.getenv("REMODS_RE0HD_LUA"), "Umgebungsvariable REMODS_RE0HD_LUA fehlt")
package.path = RE0 .. "/lib/?.lua;" .. RE0 .. "/autorun/?.lua;" .. package.path

-- ---- json.lua -------------------------------------------------------------
remods = {
    version = "0.1.0", game = "re0hd", data_dir = "",
    exe_base = 0x400000, exe_size = 0x100000, exe_timestamp = 0x5A0B1C2D,
}
log = { info = function() end, warn = function() end, error = function() end }
json = require("json")

local sample = {
    name = "Rebecca \"R\" Chambers\n", list = { 1, 2.5, -3, true, false }, empty = {},
    nested = { a = { b = { c = "ü" } } }, [5] = "fuenf",
}
local back = json.decode(json.encode(sample, true))
assert(back.name == sample.name, "String falsch")
assert(back.list[2] == 2.5 and back.list[3] == -3 and back.list[4] == true and back.list[5] == false)
assert(math.type(back.list[1]) == "integer", "Ganzzahl wurde zu Gleitkomma")
assert(back.nested.a.b.c == "ü", "UTF-8 falsch")
assert(back["5"] == "fuenf", "Zahlen-Schluessel falsch")
assert(json.decode('{"x": [1, {"y": null}], "u": "\\u00e4\\ud83d\\ude00"}').u == "ä😀", "Unicode-Escape falsch")
assert(json.decode('[1, null, 3]')[2] == json.null)
assert(not pcall(json.decode, '{"a": 1,}'), "kaputtes JSON akzeptiert")
assert(not pcall(json.dump_file, "../boese.json", {}), "'..' im Pfad erlaubt")

local TEST_FILE = "re0hd_json_test.json"
assert(json.dump_file(TEST_FILE, { a = 1 }))
assert(json.load_file(TEST_FILE).a == 1)
os.remove(TEST_FILE)
assert(json.load_file("gibt_es_nicht.json") == nil)

-- ---- Mock: Runtime-API ------------------------------------------------------
os.remove("re0hd_coop_config.json") -- Reste frueherer Laeufe

local callbacks = { frame = {}, ui = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
}

local pending_clicks = {}
local pending_inputs = {}
local ui_texts = {}
imgui = {
    tree_node = function() return true end,
    tree_pop = function() end,
    text = function(t) table.insert(ui_texts, t) end,
    text_colored = function(t) table.insert(ui_texts, t) end,
    separator = function() end,
    same_line = function() end,
    button = function(label)
        if pending_clicks[label] then pending_clicks[label] = nil; return true end
        return false
    end,
    input_text = function(label, v)
        if pending_inputs[label] then
            local nv = pending_inputs[label]; pending_inputs[label] = nil; return true, nv
        end
        return false, v
    end,
    checkbox = function(_, v) return false, v end,
}

-- Fake-Speicher: re0hd.exe+100 zeigt auf 0x2000, dort +10 -> 0x3000, bei 0x3004 liegt 1234
local memory = { [0x400100] = 0x2000, [0x2010] = 0x3000, [0x3004] = 1234 }
mem = {
    module = function(name) if name == "re0hd.exe" then return 0x400000 end end,
    read_ptr = function(a) return memory[a] end,
    read_u32 = function(a) return memory[a] end,
    read_i32 = function(a) return memory[a] end,
    read_u16 = function(a) return memory[a] end,
    read_u8 = function(a) return memory[a] end,
    read_f32 = function(a) return memory[a] end,
    read_string = function() return nil end,
}

local memtool = require("re0hd_coop.memtool")
assert(memtool.resolve("re0hd.exe+100") == 0x400100)
assert(memtool.resolve("0x3004") == 0x3004)
assert(memtool.resolve("re0hd.exe+100, 10, 4") == 0x3004, "Zeiger-Kette falsch")
assert(memtool.read("re0hd.exe + 100 , 10 , 4", "u32") == 1234)
local _, err = memtool.resolve("re0hd.exe+200, 4")
assert(err and err:find("Stufe 1"), "Fehler bei kaputtem Zeiger fehlt")
assert(select(2, memtool.resolve("foo.dll+1")):find("nicht geladen"))
assert(select(2, memtool.resolve("xyz")):find("ungueltig"))
assert(memtool.format(-1, "i32") == "-1 (0xFFFFFFFF)")

-- ---- Skript laden (Spieler A = Host, nutzt net_a als coopnet) --------------
coopnet = net_a
dofile(RE0 .. "/autorun/re0hd_coop.lua")
assert(#callbacks.frame == 1 and #callbacks.ui == 1, "Callbacks nicht registriert")

local function run_frame()
    for _, fn in ipairs(callbacks.frame) do fn() end
end
local function run_ui()
    ui_texts = {}
    for _, fn in ipairs(callbacks.ui) do fn() end
end
local function find_text(pattern)
    for _, t in ipairs(ui_texts) do if t:find(pattern) then return t end end
end

run_ui()
assert(find_text("Nicht verbunden"), "Status fehlt")
assert(not find_text("UI%-Fehler"), find_text("UI%-Fehler"))

-- Speicher-Werkzeug: Adresse eingeben und merken
pending_inputs["Adresse"] = "re0hd.exe+100, 10, 4"
run_ui()
assert(find_text("0x00003004 = 1234"), "Wert nicht angezeigt")
pending_inputs["Name"] = "Test-HP"
run_ui()
pending_clicks["Merken"] = true
run_ui()
run_ui()
assert(find_text("Test%-HP %[u32%]: 0x00003004 = 1234"), "Merkliste fehlt")
assert(json.load_file("re0hd_coop_config.json").watches[1].name == "Test-HP", "Merkliste nicht gespeichert")

pending_inputs["Situation (z. B. rebecca_zug)"] = "Zug Wagen 1!"
run_ui()
pending_clicks["Diagnose speichern"] = true
run_ui()
assert(find_text("Gespeichert: remods/data/re0hd_diag_Zug_Wagen_1_.json"), "Diagnose nicht gespeichert")
local d = json.load_file("re0hd_diag_Zug_Wagen_1_.json")
assert(d.exe.timestamp == "0x5A0B1C2D" and d.watches[1].value == 1234 and d.watches[1].address == "0x00003004")
os.remove("re0hd_diag_Zug_Wagen_1_.json")

-- "Hosten" klicken, Spieler B tritt bei und chattet
pending_clicks["Hosten"] = true
run_ui()
assert(net_a.status().mode == "hosting", "Host nicht gestartet")

local Session = require("remods_coop.session")
local b = Session.new({ net = net_b, game = "re0hd", mod_version = "0.1.0", name = "Billy" })
assert(b:join("127.0.0.1", 27350))

local deadline = net_a.time() + 3
repeat
    run_frame(); b:update(); sleep_ms(20); run_ui()
until find_text("Mitspieler: Billy") or net_a.time() > deadline
assert(find_text("Mitspieler: Billy"), "Mitspieler nicht in der UI")

b:send("CHAT", { text = "hallo rebecca" }, true)
deadline = net_a.time() + 2
repeat run_frame(); sleep_ms(10); run_ui() until find_text("Billy: hallo rebecca") or net_a.time() > deadline
assert(find_text("Billy: hallo rebecca"), "Chat nicht im Log")

pending_clicks["Trennen"] = true
run_ui()
assert(net_a.status().mode == "idle")
b:leave()
os.remove("re0hd_coop_config.json")

-- ---- MT-Explorer mit Fake-mt ------------------------------------------------
imgui.begin_child = function() return true end
imgui.end_child = function() end
imgui.set_clipboard = function() end
memory[0x5000] = 0x00C00000          -- vtable von uPlayerRebecca
memory[0x5004] = 0x16000              -- Zeiger auf ein anderes MT-Objekt
memory[0x5008] = 0x3F800000          -- 1.0 als float
mem.read_f32 = function(a) return memory[a] == 0x3F800000 and 1.0 or 0.0 end
memory[0x16000] = 0x00C00010
mt = {
    scan = function() return { active = true, progress = 0, dti = 2, instances = 0, classes_with_instances = 0, ms = 0, scanned_mb = 0, skipped_mb = 0 } end,
    scan_step = function() return { active = false, finished = true, progress = 1, dti = 2, instances = 2, classes_with_instances = 2, ms = 1, scanned_mb = 1, skipped_mb = 0 } end,
    classes = function(filter)
        local all = { { name = "uPlayerRebecca", dti = 0x100, count = 1, size = 0x400 }, { name = "uCoord", dti = 0x200, count = 1, size = 0x40 } }
        local out = {}
        for _, c in ipairs(all) do if c.name:find(filter, 1, true) then out[#out + 1] = c end end
        return out
    end,
    instances = function(name) return name == "uPlayerRebecca" and { 0x5000 } or {} end,
    class_of = function(a)
        if a == 0x5000 then return "uPlayerRebecca" elseif a == 0x16000 then return "uCoord" end
    end,
    dti_raw = function() return { addr = 0x100, words = {}, parent = "uPlayerBase" } end,
    info = function() return { dti_count = 2 } end,
}
local frames_before = #callbacks.frame
local explorer = require("re0hd_coop.explorer")
assert(#callbacks.frame == frames_before + 1, "Explorer hat keinen on_frame-Callback")
local function run_explorer()
    ui_texts = {}
    explorer.draw()
end
pending_clicks["Speicher durchsuchen"] = true
run_explorer()
run_explorer()
assert(find_text("Suche laeuft: 0 %%"), "Fortschritt fehlt")
callbacks.frame[#callbacks.frame]() -- ein Frame: Suche wird fertig
run_explorer()
assert(find_text("2 Klassen %(DTI%)"), "Scan-Ergebnis fehlt")
pending_clicks["uPlayerRebecca  (1)##cls"] = true
run_explorer()
assert(find_text("Objekte von uPlayerRebecca: 1"))
pending_clicks["0x00005000##inst1"] = true
run_explorer()
run_explorer()
assert(find_text("Objekt 0x00005000  %(uPlayerRebecca%)"), "Objekt-Ansicht fehlt")
assert(find_text("%+004  0x00016000.*%-> uCoord"), "Zeiger-Klasse fehlt")
assert(find_text("%+008  0x3F800000  f=1%.0000"), "float fehlt")
pending_clicks[">##follow4"] = true
run_explorer()
run_explorer()
assert(find_text("Objekt 0x00016000  %(uCoord%)"), "Zeiger folgen geht nicht")
pending_clicks["< Zurueck"] = true
run_explorer()
run_explorer()
assert(find_text("Objekt 0x00005000"))
pending_inputs["Was passiert gerade?"] = "rebecca steht"
run_explorer()
pending_clicks["Schnappschuss speichern"] = true
run_explorer()
local snap = json.load_file("re0hd_snap_rebecca_steht.json")
assert(snap and snap.class == "uPlayerRebecca" and snap.words[2] == "0x00016000" and snap.floats[3] == 1.0, "Schnappschuss falsch")
os.remove("re0hd_snap_rebecca_steht.json")

-- Alle Objekte einer Klasse auf einmal
pending_inputs["Was passiert gerade?##all"] = "alle"
run_explorer()
pending_clicks["Alle 1 Objekte speichern"] = true
run_explorer()
local all = json.load_file("re0hd_snap_alle.json")
assert(all and all.class == "uPlayerRebecca" and #all.objects == 1 and all.objects[1].addr == "0x00005000", "Sammel-Schnappschuss falsch")
os.remove("re0hd_snap_alle.json")
-- ---- Entwickler-Konsole -------------------------------------------------------
local devconsole = require("re0hd_coop.devconsole")
devconsole.enabled = true
local f = assert(io.open("claude_cmd.lua", "wb"))
f:write("out(1 + 1, 'hallo'); console.store.x = 5; local n = 0; task(function() n = n + 1; console.store.n = n; return n < 3 end); return {a = 1}")
f:close()
devconsole.update(100)
local res = json.load_file("claude_out.json")
assert(res and res.ok and res.output[1] == 2 and res.output[2] == "hallo" and res.returned.a == 1, "Konsole falsch")
assert(io.open("claude_cmd.lua", "rb") == nil, "Befehlsdatei nicht geloescht")
for i = 1, 5 do devconsole.update(100 + i * 0.01) end
assert(devconsole.store.n == 3, "Aufgabe lief nicht bis zum Ende: " .. tostring(devconsole.store.n))
f = assert(io.open("claude_cmd.lua", "wb")); f:write("error('kaputt')"); f:close()
devconsole.update(200)
res = json.load_file("claude_out.json")
assert(res and res.ok == false and res.error:find("kaputt"), "Fehler nicht gemeldet")
os.remove("claude_out.json")
print("re0hd_mock_test: alles ok")
