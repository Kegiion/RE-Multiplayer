-- Laedt das RE2-Koop-Skript in einer nachgebauten REFramework-Umgebung und
-- spielt eine Verbindung mit einem zweiten (reinen Lua-)Spieler durch.
-- Erwartet: Umgebungsvariable REMODS_RE2R_AUTORUN = Pfad zu games/re2r/coop/autorun
local AUTORUN = assert(os.getenv("REMODS_RE2R_AUTORUN"), "Umgebungsvariable REMODS_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

-- ---- Mock: REFramework-API ---------------------------------------------
local callbacks = { frame = {}, ui = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
}
log = { info = function() end }
local files = {}
json = {
    load_file = function(p) return files[p] end,
    dump_file = function(p, t) files[p] = t; return true end,
}

local pending_clicks = {}
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
    input_text = function(_, v) return false, v end,
    checkbox = function(_, v) return false, v end,
}

local drawn = {}
Vector3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
draw = {
    world_to_screen = function(v) return { x = v.x * 10, y = v.y * 10 } end,
    text = function(t) table.insert(drawn, t) end,
    line = function() end,
    outline_circle = function() end,
}

-- Fake-Spieler
local player_pos = { x = 1, y = 0, z = 2 }
local function obj(methods)
    return { call = function(self, name, ...)
        local m = methods[name]
        if not m then error("Methode fehlt: " .. name) end
        return m(...)
    end }
end
local transform = obj({
    get_Position = function() return player_pos end,
    get_Rotation = function() return { x = 0, y = 0, z = 0, w = 1 } end,
})
local player = obj({ get_Transform = function() return transform end, get_Name = function() return "pl1000" end })
local player_manager = obj({ get_CurrentPlayer = function() return player end })

local function fake_type(name)
    local method = { get_name = function() return "get_CurrentPlayer" end, get_num_params = function() return 0 end,
        is_static = function() return false end, get_return_type = function() return { get_full_name = function() return "via.GameObject" end } end }
    return {
        get_full_name = function() return name end,
        get_parent_type = function() return nil end,
        get_methods = function() return { method } end,
        get_fields = function() return {} end,
    }
end
sdk = {
    game_namespace = function(n) return "app.ropeway." .. n end,
    get_managed_singleton = function(n) if n == "app.ropeway.PlayerManager" then return player_manager end end,
    find_type_definition = function(n) if n == "app.ropeway.PlayerManager" then return fake_type(n) end end,
}
reframework = { get_game_name = function() return "re2" end, get_commit_count = function() return 1 end }

-- ---- Skript laden (Spieler A = Host, nutzt net_a als coopnet) ----------
coopnet = net_a
dofile(AUTORUN .. "/re2r_coop.lua")
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

-- UI ohne Verbindung
run_ui()
assert(find_text("Nicht verbunden"), "Status fehlt")
assert(not find_text("UI%-Fehler"), find_text("UI%-Fehler"))

-- "Hosten" klicken
pending_clicks["Hosten"] = true
run_ui()
assert(net_a.status().mode == "hosting", "Host nicht gestartet")

-- Spieler B (reine Lua-Session) tritt bei
local Session = require("remods_coop.session")
local b = Session.new({ net = net_b, game = "re2r", mod_version = "0.1.0", name = "Claire" })
local b_states = {}
b:on("PLAYER_STATE", function(_, _, msg) table.insert(b_states, msg) end)
assert(b:join("127.0.0.1", 27350))

local deadline = net_a.time() + 3
while net_a.time() < deadline and #b_states < 3 do
    run_frame()
    b:update()
    sleep_ms(20)
end
assert(#b_states >= 3, "B hat keine Positionsdaten bekommen")
assert(b_states[1].x == 1 and b_states[1].z == 2, "falsche Position")
assert(b_states[2].seq > b_states[1].seq)

-- B sendet seine Position -> A zeichnet Markierung "Claire"
for i = 1, 5 do
    b:send("PLAYER_STATE", { seq = i, x = 4, y = 0, z = 6, qw = 1 }, false)
    b:update()
    sleep_ms(20)
    drawn = {}
    run_frame()
end
local label
for _, t in ipairs(drawn) do if t:find("Claire") then label = t end end
assert(label, "Markierung fuer Claire wurde nicht gezeichnet")
assert(label:find("5.0m"), "Entfernung falsch: " .. label) -- (1,0,2) -> (4,0,6) = 5m

-- Chat
b:send("CHAT", { text = "hallo leon" }, true)
deadline = net_a.time() + 2
repeat run_frame(); sleep_ms(10); run_ui() until find_text("Claire: hallo leon") or net_a.time() > deadline
assert(find_text("Claire: hallo leon"), "Chat nicht im Log")
pending_clicks["Diagnose speichern"] = true
run_ui()
assert(files["re2r_coop_diag.json"], "Diagnose nicht geschrieben")
local d = files["re2r_coop_diag.json"]
assert(d.player.found and d.player.object_name == "pl1000")
assert(d.types["app.ropeway.PlayerManager"].found)
assert(d.types["app.ropeway.EnemyManager"].found == false)

assert(find_text("Mitspieler: Claire"), "Mitspieler nicht in der UI")

-- Fehler im Spielzugriff duerfen das Skript nicht abschiessen
sdk.get_managed_singleton = function() error("kaputt") end
run_frame()
run_ui()
assert(not find_text("UI%-Fehler"))

-- Trennen
pending_clicks["Trennen"] = true
run_ui()
assert(net_a.status().mode == "idle")
b:leave()
print("re2r_mock_test: alles ok")
