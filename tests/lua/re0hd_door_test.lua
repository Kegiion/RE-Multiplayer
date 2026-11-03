-- Testet das Tuer-Verhalten des RE0-Koops mit dem echten Hauptskript:
-- Verlaesst der Mitspieler den Raum, laeuft der Partner zur Tuer und wird
-- ausgeblendet. Kommt er zurueck, taucht der Partner bei ihm auf. Bricht die
-- Verbindung ab, steht der Partner wieder neben der eigenen Figur.
local RE0 = assert(os.getenv("REMULTIPLAYER_RE0HD_LUA"), "Umgebungsvariable REMULTIPLAYER_RE0HD_LUA fehlt")
package.path = RE0 .. "/lib/?.lua;" .. RE0 .. "/autorun/?.lua;" .. package.path

remultiplayer = { version = "0.4.0", game = "re0hd", data_dir = "", exe_timestamp = 0, exe_base = 0, exe_size = 0 }
log = { info = function() end, warn = function() end, error = function() end }
json = require("json")
mem = setmetatable({}, { __index = function() return function() return nil end end }) -- Speicher-Werkzeug im Menue
os.remove("re0hd_coop_config.json")

local callbacks = { frame = {}, ui = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
}
local pending_clicks = {}
imgui = {
    tree_node = function() return true end, tree_pop = function() end,
    text = function() end, text_colored = function() end, separator = function() end, same_line = function() end,
    button = function(label)
        if pending_clicks[label] then pending_clicks[label] = nil; return true end
        return false
    end,
    input_text = function(_, v) return false, v end,
    checkbox = function(_, v) return false, v end,
}

-- ---- Nachgebautes Spiel ------------------------------------------------------
local me = { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, character = 1, area = "Tr02" }
local partner = { x = 100, y = 0, z = 0 }
local keys = { up = false, down = false, left = false, right = false }
local game = {
    ID = "re0hd", supported = true, SAVE_SLOTS = 20, SAVE_SLOT_SIZE = 100,
    get_local_state = function()
        local s = {}
        for k, v in pairs(me) do s[k] = v end
        return s
    end,
    partner_object = function() return 1 end,
    read_state = function() return { x = partner.x, y = partner.y, z = partner.z, qy = 0, qw = 1 } end,
    place_partner = function(s)
        partner.x, partner.z = s.x, s.z
        if s.y then partner.y = s.y end
        return true
    end,
    camera_heading = function() return 0 end,
    set_partner_key = function(name, v) keys[name] = v end,
    set_change_key = function() end,
    same_room = function(a, b)
        if a == nil or b == nil or a == "" or b == "" then return nil end
        return a == b
    end,
    current_save_slot = function() return nil end,
    read_save_slot = function() return nil end,
    save_slot_matches = function() return true end,
    write_save_slot = function() end,
    describe_save = function() return "" end,
}
function game.hide_partner(x, y, z) return game.place_partner({ x = x, y = y - 3000, z = z }) end
package.loaded["re0hd_coop.game"] = game

coopnet = net_a
dofile(RE0 .. "/autorun/re0hd_coop.lua")

local function frame(dt)
    for _, fn in ipairs(callbacks.frame) do fn() end
    for _, fn in ipairs(callbacks.ui) do fn() end
    -- Partner laeuft wie im Spiel in Richtung der Tasten (Kamera 0: hoch = +z, links = -x... siehe puppet.lua)
    local ux = (keys.up and 1 or 0) - (keys.down and 1 or 0)
    local lx = (keys.left and 1 or 0) - (keys.right and 1 or 0)
    if (ux ~= 0 or lx ~= 0) and partner.y > -100 then
        local world = math.atan(lx, ux)
        partner.x = partner.x + math.sin(world) * 250 * dt
        partner.z = partner.z + math.cos(world) * 250 * dt
    end
end

-- ---- Mitspieler B -------------------------------------------------------------
pending_clicks["Hosten"] = true
frame(0)
assert(net_a.status().mode == "hosting", "Host nicht gestartet")

local Session = require("remultiplayer_coop.session")
local b = Session.new({ net = net_b, game = "re0hd", mod_version = "0.8.0", name = "Billy" })
assert(b:join("127.0.0.1", 27350))
local bs = { x = 500, y = 0, z = 0, area = "Tr02" }
local seq = 0
local function run(seconds, step)
    local t_end = net_a.time() + seconds
    while net_a.time() < t_end do
        if step then step() end
        if #b:ready_peers() > 0 then
            seq = seq + 1
            b:send("PLAYER_STATE", { seq = seq, area = bs.area, x = bs.x, y = bs.y, z = bs.z,
                qx = 0, qy = 0, qz = 0, qw = 1, character = 2, flags = 0 }, false)
        end
        b:update()
        sleep_ms(16)
        frame(0.016)
    end
end
local function dist(x, z) return math.sqrt((partner.x - x) ^ 2 + (partner.z - z) ^ 2) end

-- 1. Gleicher Raum: Partner geht zu B
run(3)
assert(partner.y == 0 and dist(500, 0) < 40, string.format("Partner nicht bei B (%.0f, %.0f)", partner.x, partner.z))

-- 2. B geht zur Tuer (800, 0) und dann in Raum Tr03
run(2, function() bs.x = math.min(800, bs.x + 4) end)
bs.area, bs.x, bs.z = "Tr03", -2000, 400
run(4)
assert(partner.y == -3000, "Partner nicht ausgeblendet (y = " .. partner.y .. ")")
assert(dist(800, 0) < 80, string.format("Partner nicht an der Tuer verschwunden (%.0f, %.0f)", partner.x, partner.z))
assert(not (keys.up or keys.down or keys.left or keys.right), "Tasten beim Verstecken nicht losgelassen")

-- 3. B kommt zurueck in meinen Raum
bs.area, bs.x, bs.z = "Tr02", 750, 120
run(1.5)
assert(partner.y == 0, "Partner taucht nicht wieder auf (y = " .. partner.y .. ")")
assert(dist(750, 120) < 60, string.format("Partner nicht bei B aufgetaucht (%.0f, %.0f)", partner.x, partner.z))

-- 4. B geht wieder raus, dann bricht die Verbindung ab: Partner zurueck neben mich
bs.area = "Tr03"
run(1.0)
assert(partner.y == -3000, "Partner beim zweiten Mal nicht ausgeblendet")
b:leave()
run(1.5)
assert(partner.y == 0, "Partner bleibt nach Verbindungsabbruch im Boden")
assert(dist(me.x + 60, me.z) < 1, "Partner nicht neben der eigenen Figur")

os.remove("re0hd_coop_config.json")
print("re0hd_door_test: alles ok")
