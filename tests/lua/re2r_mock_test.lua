-- Laedt das RE2-Koop-Skript in einer nachgebauten REFramework-Umgebung und
-- spielt eine Verbindung mit einem zweiten (reinen Lua-)Spieler durch.
-- Erwartet: Umgebungsvariable REMULTIPLAYER_RE2R_AUTORUN = Pfad zu games/re2r/coop/autorun
local AUTORUN = assert(os.getenv("REMULTIPLAYER_RE2R_AUTORUN"), "Umgebungsvariable REMULTIPLAYER_RE2R_AUTORUN fehlt")
package.path = AUTORUN .. "/?.lua;" .. package.path

-- ---- Mock: REFramework-API ---------------------------------------------
local callbacks = { frame = {}, ui = {}, reset = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
    on_script_reset = function(fn) table.insert(callbacks.reset, fn) end,
}
log = { info = function() end }
-- Gespeicherte Konfiguration: Konsolen-Haken an, eigener Port, damit der Test
-- auch laeuft, waehrend das echte Spiel auf 27350 hostet.
local TEST_PORT = 27351
local files = { ["re2r_coop_config.json"] = { devconsole = true, port = TEST_PORT } }
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
local next_address = 0x1000
local function obj(methods)
    next_address = next_address + 8
    local address = next_address
    return { call = function(self, name, ...)
        local m = methods[name]
        if not m then error("Methode fehlt: " .. name) end
        return m(...)
    end, get_address = function() return address end }
end
-- Motion-Komponente (via.motion.Motion) mit Ebenen und Baenken
local NO_MOTION = 4294967295
local function holder(path)
    return obj({ get_ResourcePath = function() return path end })
end
local function fake_dyn_bank()
    local b
    b = obj({
        get_MotionBank = function() return b.bank end,
        set_MotionBank = function(h) b.bank = h end,
    })
    return b
end
local function fake_var(value)
    local v
    v = obj({
        get_CastF32 = function() return type(v.value) == "boolean" and (v.value and 1 or 0) or v.value end,
        get_Bool = function() return v.value == true end,
        set_F32 = function(x) v.value = x end,
        set_Bool = function(x) v.value = x end,
    })
    v.value = value
    return v
end
local function fake_motion()
    local m = { layers = {}, dyn = {}, vars = {
        MoveDir = fake_var(0.5), WatchDir = fake_var(0.5), Pitch = fake_var(0), Jog = fake_var(false), HoldUp = fake_var(false),
    } }
    local hub = obj({ ["findVariable(System.String)"] = function(name) return m.vars[name] end })
    for i = 0, 5 do
        local L = { bank = 0, id = NO_MOTION, frame = 0, changes = 0 }
        L.obj = obj({
            get_MotionBankID = function() return L.bank end,
            get_MotionID = function() return L.id end,
            get_Frame = function() return L.frame end,
            get_InterpolationFrame = function() return L.interp or 0 end,
            get_InterpolationMode = function() return L.imode or 0 end,
            get_InterpolationCurve = function() return L.icurve or 0 end,
            ["changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, "
                .. "via.motion.InterpolationMode, via.motion.InterpolationCurve)"] = function(b, id, f, ifr, mode, curve)
                L.bank, L.id, L.frame, L.changes = b, id, f, L.changes + 1
                L.interp, L.imode, L.icurve = ifr, mode, curve
            end,
        })
        m.layers[i] = L
    end
    m.obj = obj({
        getLayer = function(i) return m.layers[i].obj end,
        get_MotionBankAsset = function() return m.asset end,
        set_MotionBankAsset = function(h) m.asset = h end,
        getDynamicMotionBankCount = function() return #m.dyn end,
        getDynamicMotionBank = function(i) return m.dyn[i + 1] end,
        setDynamicMotionBankCount = function(n) m.dyn_count = n end,
        setDynamicMotionBank = function(i, b) m.dyn[i + 1] = b end,
        set_TargetBankType = function(t) m.target_bank_type = t end,
        setupMotionBank = function() m.setups = (m.setups or 0) + 1 end,
        set_RootMotion = function(v) m.root_motion = v end,
        get_VariablesHub = function() return hub end,
    })
    return m
end
local player_motion = fake_motion()
player_motion.asset = holder("main.motbank")
player_motion.dyn[1] = fake_dyn_bank()
player_motion.dyn[1].bank = holder("BareHand.motbank")
player_motion.layers[0].bank, player_motion.layers[0].id, player_motion.layers[0].frame = 1, 190, 5
player_motion.layers[0].interp, player_motion.layers[0].imode, player_motion.layers[0].icurve = 36, 3, 1
player_motion.vars.MoveDir.value, player_motion.vars.Pitch.value, player_motion.vars.Jog.value = 0.25, -30, true

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
        if t == "TYPE:via.motion.Motion" then return player_motion.obj end
    end,
    get_Transform = function() return transform end,
    get_Name = function() return "pl1000" end,
    get_Folder = function() return "PLAYER_FOLDER" end,
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
    local motion = fake_motion()
    go = obj({
        get_Valid = function() return not go.destroyed end,
        get_Transform = function() return transform_obj end,
        ["getComponent(System.Type)"] = function(t)
            if t == "TYPE:app.ropeway.survivor.SurvivorCostumeChanger" then return changer end
            if t == "TYPE:via.motion.Motion" then return motion.obj end
        end,
        set_DrawSelf = function(v) go.draw = v end,
        set_FolderSelf = function(f) go.folder = f end,
        destroy = function(g) g.destroyed = true end,
    })
    go.motion = motion
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
    create_instance = function(n)
        if n == "via.Prefab" then return fake_prefab() end
        if n == "via.motion.DynamicMotionBank" then return fake_dyn_bank() end
    end,
    create_resource = function(t, path)
        assert(t == "via.motion.MotionBankResource", t)
        return { create_holder = function(_, ht) assert(ht == "via.motion.MotionBankResourceHolder"); return holder(path) end }
    end,
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
local Session = require("remultiplayer_coop.session")
local b = Session.new({ net = net_b, game = "re2r", mod_version = "0.1.0", name = "Claire" })
local b_states = {}
b:on("PLAYER_STATE", function(_, _, msg) table.insert(b_states, msg) end)
local b_anim, b_banks = {}, {}
b:on("ANIM_STATE", function(_, _, msg) table.insert(b_anim, msg) end)
b:on("ANIM_BANKS", function(_, _, msg) table.insert(b_banks, msg) end)
assert(b:join("127.0.0.1", TEST_PORT))

local deadline = net_a.time() + 3
while net_a.time() < deadline and (#b_states < 3 or #b_anim < 3 or #b_banks == 0) do
    run_frame()
    b:update()
    sleep_ms(20)
end
assert(#b_states >= 3, "B hat keine Positionsdaten bekommen")
assert(b_states[1].x == 1 and b_states[1].z == 2, "falsche Position")
assert(b_states[2].seq > b_states[1].seq)
assert(b_states[1].character == 1, "Figur falsch: " .. tostring(b_states[1].character))
assert(b_states[1].area == "St1_101_0", "Bereich falsch: " .. tostring(b_states[1].area))
-- Animationen des Spielers gehen mit
assert(#b_banks == 1, "ANIM_BANKS fehlt oder doppelt: " .. #b_banks)
assert(b_banks[1].main == "main.motbank" and b_banks[1].dyn1 == "BareHand.motbank" and b_banks[1].dyn2 == "")
local a1 = b_anim[#b_anim]
assert(a1.banks_id == b_banks[1].banks_id, "ANIM_STATE verweist auf falschen Bank-Satz")
assert(a1.bank0 == 1 and a1.motion0 == 190 and a1.frame0 == 5 and a1.motion3 == NO_MOTION, "falsche Animation gesendet")
assert(a1.interp0 == 36 and a1.imode0 == 3 and a1.icurve0 == 1, "Ueberblendung nicht gesendet")
-- Steuer-Variablen: MoveDir = var2, Pitch = var9, Jog = Bit 1 (siehe anim.lua)
assert(a1.var2 == 0.25 and a1.var9 == -30 and a1.var1 == 0, "Variablen nicht gesendet")
assert(a1.bits == 2, "Schalter nicht gesendet: " .. tostring(a1.bits))

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
b:send("ANIM_BANKS", { banks_id = 42, main = "pl_common.motbank", dyn1 = "BareHand.motbank", dyn2 = "wp0000.motbank" }, true)
for i = 6, 12 do
    b:send("PLAYER_STATE", { seq = i, x = 4, y = 0, z = 6, qx = 0, qy = 1, qz = 0, qw = 0, area = "St1_101_0", character = 0 }, false)
    b:send("ANIM_STATE", { seq = i, banks_id = 42, bank0 = 1, motion0 = 230, frame0 = 7, interp0 = 20, imode0 = 3, icurve0 = 1,
        var4 = 0.75, bits = 8, motion1 = NO_MOTION, bank2 = 10000, motion2 = 2, frame2 = 1,
        bank3 = 0, motion3 = NO_MOTION }, false)
    b:update()
    sleep_ms(20)
    run_frame()
end
assert(#prefabs == 1, "Prefab nicht angelegt")
assert(prefabs[1].path == "ObjectRoot/Prefab/Character/Survivor/Actor/pl0000.pfb", tostring(prefabs[1].path))
assert(#spawned == 1, "Puppe nicht (oder mehrfach) erzeugt: " .. #spawned)
local pup = spawned[1]
assert(pup.folder == "PLAYER_FOLDER", "Puppe nicht im Spieler-Ordner: " .. tostring(pup.folder))
assert(pup.costume and pup.costume[1] == 0 and pup.costume[2] == 0, "Kostuem nicht angefordert")
assert(pup.draw == true, "Puppe nicht sichtbar")
assert(math.abs(pup.pos.x - 4) < 0.01 and math.abs(pup.pos.z - 6) < 0.01, "Puppe an falscher Position")
-- Drehung wird geglaettet: nach einigen Frames nahe am Ziel (0,1,0,0), Laenge 1
assert(pup.rot.y > 0.9 and math.abs(pup.rot.w) < 0.45, string.format("Drehung nicht uebernommen: %.3f %.3f", pup.rot.y, pup.rot.w))
assert(math.abs(pup.rot.x ^ 2 + pup.rot.y ^ 2 + pup.rot.z ^ 2 + pup.rot.w ^ 2 - 1) < 1e-6, "Drehung nicht normalisiert")
local ghost_mod = require("re2r_coop.ghost")
local q = { x = 0, y = 0, z = 0, w = 1 }
ghost_mod.nlerp(q, { qx = 0, qy = 0, qz = 0, qw = -1 }, 0.5) -- gleiche Drehung, anderes Vorzeichen
assert(q.w == 1, "nlerp nimmt nicht den kuerzeren Weg")
-- Animationsdateien und Ebenen uebernommen
local pm = pup.motion
assert(pm.asset and pm.asset:call("get_ResourcePath") == "pl_common.motbank", "Haupt-Bank fehlt")
assert(pm.dyn_count == 2 and pm.dyn[2]:call("get_MotionBank"):call("get_ResourcePath") == "wp0000.motbank", "dynamische Baenke fehlen")
assert(pm.setups == 1 and pm.root_motion == 0 and pm.target_bank_type == 1, "Baenke nicht eingerichtet")
local L0 = pm.layers[0]
assert(L0.bank == 1 and L0.id == 230 and L0.frame == 7, "Ebene 0 nicht uebernommen")
assert(L0.interp == 20 and L0.imode == 3 and L0.icurve == 1, "Ueberblendung nicht uebernommen")
assert(pm.vars.WatchDir.value == 0.75 and pm.vars.MoveDir.value == 0, "Variablen nicht uebernommen")
assert(pm.vars.HoldUp.value == true and pm.vars.Jog.value == false, "Schalter nicht uebernommen")
assert(L0.changes == 1, "changeMotion mehrfach fuer dieselbe Animation: " .. L0.changes)
assert(pm.layers[2].id == 2 and pm.layers[3].changes == 0, "Ebenen 2/3 falsch")
-- Wechsel auf Idle und Ebene 3 belegen -> genau ein changeMotion je Ebene
b:send("ANIM_STATE", { seq = 13, banks_id = 42, bank0 = 1, motion0 = 160, frame0 = 0, motion1 = NO_MOTION, bank2 = 10000, motion2 = 2, frame2 = 1,
    bank3 = 2, motion3 = 140, frame3 = 3 }, false)
b:update()
sleep_ms(20)
run_frame()
assert(L0.id == 160 and L0.changes == 2 and pm.layers[3].id == 140 and pm.layers[2].changes == 1, "Animationswechsel nicht uebernommen")
assert(pm.setups == 1, "Baenke ohne Aenderung neu geladen")
local st_text = require("re2r_coop.puppet").status_text(next(require("re2r_coop.puppet").instances))
assert(st_text:find("animiert %(4 Wechsel, 0 x neu erzeugt%)"), "Animationsstatus falsch: " .. st_text)

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
assert(#spawned == 1, "Puppe ohne Wartezeit neu erzeugt")
sleep_ms(1100) -- puppet.RESPAWN_DELAY
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
sleep_ms(600) -- Abfrage-Intervall der Konsole (0,5 s) abwarten
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
