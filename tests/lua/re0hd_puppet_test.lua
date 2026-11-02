-- Testet die Puppen-Steuerung (re0hd_coop/puppet.lua) in einem Mini-Spiel:
-- Der Partner laeuft in die Richtung der gedrueckten Partner-Tasten
-- (relativ zur Kamera), so wie in RE0 beobachtet.
local RE0 = assert(os.getenv("REMULTIPLAYER_RE0HD_LUA"), "Umgebungsvariable REMULTIPLAYER_RE0HD_LUA fehlt")
package.path = RE0 .. "/autorun/?.lua;" .. package.path
local Puppet = require("re0hd_coop.puppet")

local function run(camera_deg)
    local cam = math.rad(camera_deg)
    local keys = { up = false, down = false, left = false, right = false }
    local partner = { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1 }
    local teleports = 0
    local game = {
        camera_heading = function() return cam end,
        set_partner_key = function(name, v) keys[name] = v end,
        partner_object = function() return 1 end,
        read_state = function() return { x = partner.x, y = partner.y, z = partner.z, qy = partner.qy, qw = partner.qw } end,
        place_partner = function(s)
            if math.abs(s.x - partner.x) > 300 or math.abs(s.z - partner.z) > 300 then teleports = teleports + 1 end
            partner.x, partner.y, partner.z = s.x, s.y or partner.y, s.z
            if s.qw then partner.qy, partner.qw = s.qy, s.qw end
        end,
    }
    local p = Puppet.new(game, { delay = 0.2 })
    local SPEED, DT = 250, 1 / 60
    local function step_partner()
        local ux = (keys.up and 1 or 0) - (keys.down and 1 or 0)
        local lx = (keys.left and 1 or 0) - (keys.right and 1 or 0)
        if ux ~= 0 or lx ~= 0 then
            local world = cam + math.atan(lx, ux) -- +90 Grad = links
            partner.x = partner.x + math.sin(world) * SPEED * DT
            partner.z = partner.z + math.cos(world) * SPEED * DT
        end
    end

    -- Ziel: 3 s geradeaus (200/s, schraeg), dann 1 s um die Ecke, dann stehen
    local target = { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1 }
    local t, max_dist, modes = 0, 0, {}
    for frame = 1, 60 * 8 do
        t = frame * DT
        if t < 3 then
            target.x = target.x + 200 * DT * 0.6; target.z = target.z + 200 * DT * 0.8
        elseif t < 4 then
            target.x = target.x - 200 * DT
        end
        p:push({ x = target.x, y = 0, z = target.z, qx = 0, qy = 0.5, qz = 0, qw = 0.866 }, t)
        local mode = p:update(t)
        modes[mode] = (modes[mode] or 0) + 1
        step_partner()
        if t > 0.5 and t < 4 then
            local d = math.sqrt((target.x - partner.x) ^ 2 + (target.z - partner.z) ^ 2)
            max_dist = math.max(max_dist, d)
        end
    end
    local final = math.sqrt((target.x - partner.x) ^ 2 + (target.z - partner.z) ^ 2)
    return { max_dist = max_dist, final = final, modes = modes, teleports = teleports, partner = partner, keys = keys }
end

for _, cam in ipairs({ 0, 108, -158, 45 }) do
    local r = run(cam)
    assert(r.teleports == 0, "Kamera " .. cam .. ": unnoetiger Teleport")
    assert(r.max_dist < 150, string.format("Kamera %d: Partner zu weit weg (%.0f)", cam, r.max_dist))
    assert(r.final < 1, string.format("Kamera %d: steht nicht am Ziel (%.1f)", cam, r.final))
    assert((r.modes.laufen or 0) > 60, "Kamera " .. cam .. ": kaum gelaufen")
    assert((r.modes.stehen or 0) > 30, "Kamera " .. cam .. ": steht am Ende nicht")
    assert(not (r.keys.up or r.keys.down or r.keys.left or r.keys.right), "Tasten am Ende nicht losgelassen")
    assert(math.abs(r.partner.qy - 0.5) < 1e-6, "Drehung im Stand nicht uebernommen")
end

-- Zu weit weg: Teleport
do
    local partner = { x = 0, y = 0, z = 0 }
    local game = {
        camera_heading = function() return 0 end,
        set_partner_key = function() end,
        partner_object = function() return 1 end,
        read_state = function() return { x = partner.x, y = 0, z = partner.z } end,
        place_partner = function(s) partner.x, partner.z = s.x, s.z end,
    }
    local p = Puppet.new(game, { delay = 0 })
    p:push({ x = 5000, y = 0, z = 0, qw = 1 }, 1)
    assert(p:update(1) == "teleport" and partner.x == 5000, "kein Teleport bei grossem Abstand")
    -- Ohne Daten: warten, Tasten los
    local q = Puppet.new(game)
    assert(q:update(1) == "warten")
end

print("re0hd_puppet_test: alles ok")
