-- Laedt das RE2-Koop-Skript in einer nachgebauten REFramework-Umgebung und
-- spielt eine Verbindung mit einem zweiten (reinen Lua-)Spieler durch.
-- Erwartet: Umgebungsvariable REMODS_RE2R_AUTORUN = Pfad zu games/re2r/coop/autorun
local AUTORUN = assert(os.getenv("REMODS_RE2R_AUTORUN"), "Umgebungsvariable REMODS_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

-- ---- Mock: REFramework-API ---------------------------------------------
local callbacks = { frame = {}, ui = {}, reset = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
    on_script_reset = function(fn) table.insert(callbacks.reset, fn) end,
}
log = { info = function() end }
local files = { ["re2r_coop_config.json"] = { devconsole = true } } -- gespeicherter Haken
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
Quaternion = { new = function(w, x, y, z) return { w = w, x = x, y = y, z = z } end }
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
local function component(name)
    return { get_type_definition = function() return { get_full_name = function() return name end } end }
end
local condition = obj({
    get_SurvivorType = function() return 1 end,
    get_StaySceneAreaID = function() return 7 end,
    get_StaySpaceAreaID = function() return 8 end,
    get_StaySceneMapArea = function() return 2 end,
})
local player = obj({
    ["getComponent(System.Type)"] = function(t)
        if t == "TYPE:app.ropeway.survivor.player.PlayerCondition" then return condition end
    end,
    get_Transform = function() return transform end,
    get_Name = function() return "pl1000" end,
    get_Components = function()
        return { get_elements = function() return { component("via.Transform"), component("via.motion.Motion") } end }
    end,
})
local player_manager = obj({ get_CurrentPlayer = function() return player end })

-- Puppe: Prefab, erzeugte GameObjects, SurvivorManager
local spawned, prefabs = {}, {}
local function fake_go()
    local go
    local transform_obj = obj({
        set_Position = function(p) go.pos = p end,
        set_Rotation = function(q) go.rot = q end,
    })
    local changer = obj({
        ["change(app.ropeway.SurvivorDefine.SurvivorType, app.ropeway.SurvivorDefine.Costume)"] =
            function(t, c) go.costume = { t, c } end,
    })
    go = obj({
        get_Valid = function() return not go.destroyed end,
        get_Transform = function() return transform_obj end,
        ["getComponent(System.Type)"] = function(t)
            if t == "TYPE:app.ropeway.survivor.SurvivorCostumeChanger" then return changer end
        end,
        set_DrawSelf = function(v) go.draw = v end,
        destroy = function(g) g.destroyed = true end,
    })
    return go
end
local function fake_prefab()
    local p
    local checks = 0
    p = obj({
        set_Path = function(path) p.path = path end,
        set_Standby = function(v) p.standby = v end,
        get_Ready = function() checks = checks + 1; return p.standby and checks > 1 end, -- erst beim 2. Mal fertig
        ["instantiate(via.vec3, via.Quaternion, via.Folder)"] = function(pos, rot, folder)
            local go = fake_go()
            go.pos, go.rot, go.folder = pos, rot, folder
            spawned[#spawned + 1] = go
            return go
        end,
    })
    p.add_ref = function(self) return self end
    prefabs[#prefabs + 1] = p
    return p
end
local survivor_manager = obj({ get_ActorFolder = function() return "ACTOR_FOLDER" end })

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
-- Enums wie in REFramework: statische Felder mit Wert, dazu das Instanzfeld value__
local function fake_enum(values)
    local fields = { { is_static = function() return false end, get_name = function() return "value__" end,
        get_data = function() error("kein statisches Feld") end } }
    for name, value in pairs(values) do
        fields[#fields + 1] = { is_static = function() return true end, get_name = function() return name end,
            get_data = function() return value end }
    end
    return { get_fields = function() return fields end }
end
local enums = {
    ["app.ropeway.SurvivorDefine.SurvivorType"] = fake_enum({ PL0000 = 0, PL1000 = 1, PL2000 = 2, Invalid = -1 }),
    ["app.ropeway.gamemastering.Map.ID"] = fake_enum({ Invalid = -1, St1_101_0 = 7, St1_102_0 = 8 }),
    ["app.ropeway.gamemastering.Map.Area"] = fake_enum({ RPD = 2 }),
}
sdk = {
    game_namespace = function(n) return "app.ropeway." .. n end,
    get_managed_singleton = function(n)
        if n == "app.ropeway.PlayerManager" then return player_manager end
        if n == "app.ropeway.SurvivorManager" then return survivor_manager end
    end,
    create_instance = function(n) if n == "via.Prefab" then return fake_prefab() end end,
    find_type_definition = function(n)
        if n == "app.ropeway.PlayerManager" then return fake_type(n) end
        return enums[n]
    end,
    typeof = function(n) return "TYPE:" .. n end,
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
assert(b_states[1].character == 1, "Figur falsch: " .. tostring(b_states[1].character))
assert(b_states[1].area == "St1_101_0", "Bereich falsch: " .. tostring(b_states[1].area))

-- B sendet seine Position -> A zeichnet Markierung "Claire"
for i = 1, 5 do
    b:send("PLAYER_STATE", { seq = i, x = 4, y = 0, z = 6, qw = 1, area = "St1_102_0", character = 0 }, false)
    b:update()
    sleep_ms(20)
    drawn = {}
    run_frame()
end
local label
for _, t in ipairs(drawn) do if t:find("Claire") then label = t end end
assert(label, "Markierung fuer Claire wurde nicht gezeichnet")
assert(label:find("5.0m"), "Entfernung falsch: " .. label) -- (1,0,2) -> (4,0,6) = 5m
assert(label:find("[Leon]", 1, true), "Figur fehlt: " .. label)
assert(label:find("anderer Bereich: St1_102_0", 1, true), "Bereichshinweis fehlt: " .. label)
assert(#prefabs == 0, "Puppe trotz anderem Bereich erzeugt")

-- Gleicher Bereich -> Puppe (Leon-Actor) wird geladen, erzeugt und mitbewegt
for i = 6, 12 do
    b:send("PLAYER_STATE", { seq = i, x = 4, y = 0, z = 6, qx = 0, qy = 1, qz = 0, qw = 0, area = "St1_101_0", character = 0 }, false)
    b:update()
    sleep_ms(20)
    run_frame()
end
assert(#prefabs == 1, "Prefab nicht angelegt")
assert(prefabs[1].path == "ObjectRoot/Prefab/Character/Survivor/Actor/pl0000.pfb", tostring(prefabs[1].path))
assert(#spawned == 1, "Puppe nicht (oder mehrfach) erzeugt: " .. #spawned)
local pup = spawned[1]
assert(pup.folder == "ACTOR_FOLDER")
assert(pup.costume and pup.costume[1] == 0 and pup.costume[2] == 0, "Kostuem nicht angefordert")
assert(pup.draw == true, "Puppe nicht sichtbar")
assert(math.abs(pup.pos.x - 4) < 0.01 and math.abs(pup.pos.z - 6) < 0.01, "Puppe an falscher Position")
assert(pup.rot.y == 1 and pup.rot.w == 0, "Drehung nicht uebernommen")

-- Anderer Bereich -> ausblenden, nicht loeschen
b:send("PLAYER_STATE", { seq = 13, x = 4, y = 0, z = 6, qw = 1, area = "St1_102_0", character = 0 }, false)
b:update()
sleep_ms(20)
run_frame()
assert(pup.draw == false and not pup.destroyed, "Puppe nicht ausgeblendet")

-- Vom Spiel geloescht (z. B. Szenenwechsel) -> neu erzeugen
b:send("PLAYER_STATE", { seq = 14, x = 4, y = 0, z = 6, qw = 1, area = "St1_101_0", character = 0 }, false)
b:update()
sleep_ms(20)
pup.destroyed = true
for _ = 1, 4 do run_frame() end
assert(#spawned == 2 and spawned[2].draw == true, "Puppe nicht neu erzeugt")

-- Reset Scripts -> Puppe weg
assert(#callbacks.reset == 1, "on_script_reset nicht registriert")
callbacks.reset[1]()
assert(spawned[2].destroyed, "Puppe nach Reset nicht geloescht")

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
assert(d.player.components[2] == "via.motion.Motion", "Komponenten fehlen")
assert(d.player.condition.survivor_name == "PL1000", "Figur fehlt in Diagnose")
local game_mod = require("re2r_coop.game")
assert(game_mod.get_area({ scene_area_name = "Invalid" }) == "", "Invalid muss als unbekannt gelten")
assert(game_mod.get_area({ scene_area_name = "st4_101_0" }) == "st4_101_0")
assert(game_mod.character_name(1) == "Claire" and game_mod.character_name(2) == "PL2000" and game_mod.character_name(255) == "?")
assert(d.player.condition.space_area_name == "St1_102_0")
assert(d.player.condition.map_area_name == "RPD")
local st = d.enums["app.ropeway.SurvivorDefine.SurvivorType"]
assert(st[1] == "-1 = Invalid" and st[3] == "1 = PL1000", "Enum-Liste falsch: " .. table.concat(st, ", "))
assert(#d.enums["app.ropeway.PlayerDefine.PlayerType"] == 0, "unbekanntes Enum sollte leer sein")
assert(d.research_available == false and d.type_search == nil)

-- Mit Plugin-Forschungsfunktionen + Situationsname
coopnet.find_types = function(word)
    if word == "Map" then return { "app.ropeway.gamemastering.MapManager", "via.Map", "app.ropeway.MapAreaDefineTable" } end
    return {}
end
coopnet.list_singletons = function()
    return { "app.ropeway.PlayerManager", "app.ropeway.gamemastering.LocationThing", "app.ropeway.SoundManager", "via.SceneManager" }
end
local diag = require("re2r_coop.diag")
local ok, path = diag.write(nil, "RPD Halle 1F!")
assert(ok, path)
assert(path == "reframework/data/re2r_coop_diag_RPD_Halle_1F.json", path)
d = files["re2r_coop_diag_RPD_Halle_1F.json"]
assert(d.research_available and d.label == "RPD Halle 1F!")
assert(#d.singletons == 4)
assert(#d.type_search.Map == 2, "Namespace-Filter falsch") -- via.Map faellt raus
assert(d.types["app.ropeway.gamemastering.LocationThing"], "interessanter Manager nicht beschrieben")
assert(d.types["app.ropeway.SoundManager"] == nil, "uninteressanter Manager beschrieben")
coopnet.find_types, coopnet.list_singletons = nil, nil

assert(find_text("Mitspieler: Claire"), "Mitspieler nicht in der UI")

-- Entwickler-Konsole: gespeicherter Haken muss nach dem Laden gelten
local devconsole = require("re2r_coop.devconsole")
assert(devconsole.enabled == true, "gespeicherter Konsolen-Haken nicht uebernommen")
devconsole.enabled = false
run_ui()
-- aus -> Befehl wird ignoriert
assert(find_text("%(aus%)"), "Konsolen-Status fehlt")
files["claude_cmd.json"] = { id = 5, code = "out(game.ID, 1 + 1); return { a = 1 }" }
run_frame()
assert(files["claude_out.json"] == nil, "Konsole lief, obwohl aus")
devconsole.enabled = true
run_frame()
local res = files["claude_out.json"]
assert(res and res.ok and res.id == 5, "Befehl nicht ausgefuehrt")
assert(res.output[1] == "re2r" and res.output[2] == 2 and res.returned.a == 1)
-- gleiche id -> nicht noch einmal
files["claude_out.json"] = nil
sleep_ms(600); run_frame()
assert(files["claude_out.json"] == nil, "Befehl doppelt ausgefuehrt")
-- Fehler, Store, Task und gemischte Schluessel
files["claude_cmd.json"] = { id = 6, code = "console.store.n = 0; task(function() console.store.n = console.store.n + 1; return console.store.n < 3 end); out({ [1] = 'x', [5] = 'y' }); error('absicht')" }
sleep_ms(600); run_frame()
res = files["claude_out.json"]
assert(res.id == 6 and res.ok == false and res.error:find("absicht"), "Fehler nicht gemeldet")
assert(res.output[1]["5"] == "y", "gemischte Schluessel nicht umgewandelt")
run_frame(); run_frame(); run_frame()
assert(devconsole.store.n == 3, "Task lief nicht bis zum Ende: " .. tostring(devconsole.store.n))
devconsole.enabled = false

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
