-- re0hd_coop/puppet.lua - Partner als Puppe eines anderen Spielers.
--
-- Der Partner laeuft den empfangenen Positionen hinterher, und zwar ueber die
-- Partner-Tasten des Spiels (passend zur Kamera). So spielt das Spiel die
-- Laufanimationen selbst ab. Im Spiel erprobt am 2. November 2026 (Spur-Test).
--
--   local p = Puppet.new(game, { delay = 0.2, adaptive = true })
--   p:push(zustand, zeit)   -- empfangener Zustand { x, y, z, qy, qw, ... }
--   p:update(zeit)          -- jeden Frame
--   p:release()             -- Tasten loslassen (z. B. wenn die Verbindung weg ist)
--
-- Zustaende (p.mode):
--   "laufen"     Ziel bewegt sich: Tasten Richtung Ziel (+ Vorhalt), bei Abweichung sanft nachziehen
--   "hinlaufen"  Ziel steht, Partner ist noch weg: hinlaufen
--   "stehen"     Ziel steht, Partner ist da: Position und Drehung festhalten (sonst laeuft die KI los)
--   "teleport"   zu weit weg: direkt hinsetzen
--   "warten"     noch keine Daten

local Puppet = {}
Puppet.__index = Puppet

local DEFAULTS = {
    delay = 0.2,          -- s Puffer gegen Netzwerk-Schwankungen (fest, wenn adaptive = false)
    adaptive = false,     -- Puffer an gemessene Paketabstaende anpassen (fuer das Netzwerk)
    delay_min = 0.12,     -- s Grenzen fuer den anpassbaren Puffer
    delay_max = 0.6,
    extrapolate = 0.25,   -- s: so lange laeuft das Ziel bei fehlenden Daten in seiner Richtung weiter
    stop_speed = 20,      -- Einheiten/s: darunter gilt ein laufendes Ziel wieder als stehend (Hysterese)
    near = 30,            -- Einheiten: so nah gilt der Partner als "da"
    far = 350,            -- Einheiten: weiter weg wird teleportiert
    moving_speed = 40,    -- Einheiten/s: ab hier laeuft das Ziel
    lookahead = 0.25,     -- s Vorhalt beim Laufen
    pull = 0.08,          -- Anteil der Abweichung, der pro Frame nachgezogen wird
    pull_from = 60,       -- Einheiten: ab dieser Abweichung wird nachgezogen
    keep = 3.0,           -- s Verlauf, der aufbewahrt wird
}

function Puppet.new(game, opts)
    local self = setmetatable({}, Puppet)
    self.game = game
    self.cfg = {}
    for k, v in pairs(DEFAULTS) do
        self.cfg[k] = (opts and opts[k] ~= nil) and opts[k] or v
    end
    self.trail = {}
    self.mode = "warten"
    self.dist = nil
    self.keys = { up = false, down = false, left = false, right = false }
    self.stats = { laufen = 0, hinlaufen = 0, stehen = 0, teleport = 0, warten = 0 }
    self.moving = false
    -- Netzwerk-Statistik (nur mit adaptive): mittlerer Paketabstand, Schwankung, aktueller Puffer
    self.net = { interval = nil, jitter = 0, delay = self.cfg.delay, last_push = nil }
    return self
end

local function wrap(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

function Puppet:_set_keys(up, down, left, right)
    local want = { up = up, down = down, left = left, right = right }
    for name, v in pairs(want) do
        if self.keys[name] ~= v then
            self.keys[name] = v
            self.game.set_partner_key(name, v)
        end
    end
end

function Puppet:release()
    self:_set_keys(false, false, false, false)
end

-- Richtung r relativ zur Kamera (0 = hoch, +90 Grad = links, -90 Grad = rechts) auf 8 Richtungen
function Puppet:_steer(world_angle)
    local cam = self.game.camera_heading()
    if not cam then
        self:release()
        return
    end
    local r = wrap(world_angle - cam)
    local s = math.floor((r + math.pi / 8) / (math.pi / 4)) % 8
    self:_set_keys(s == 0 or s == 1 or s == 7, s == 3 or s == 4 or s == 5, s == 1 or s == 2 or s == 3,
        s == 5 or s == 6 or s == 7)
end

function Puppet:push(state, t)
    if not state or not state.x then
        return
    end
    local trail = self.trail
    if #trail > 0 and t <= trail[#trail].t then
        t = trail[#trail].t + 1e-3 -- Zeit muss steigen
    end
    local net = self.net
    if net.last_push then
        local dt = t - net.last_push
        if dt < 1.0 then -- Pausen (z. B. Ladebildschirm) nicht mitzaehlen
            net.interval = net.interval and (net.interval * 0.9 + dt * 0.1) or dt
            net.jitter = net.jitter * 0.9 + math.abs(dt - net.interval) * 0.1
        end
    end
    net.last_push = t
    if self.cfg.adaptive and net.interval then
        -- Puffer: ein Paketabstand plus dreimal die Schwankung, dazu etwas Reserve
        local want = net.interval + 3 * net.jitter + 0.05
        net.delay = math.max(self.cfg.delay_min, math.min(self.cfg.delay_max, want))
    end
    trail[#trail + 1] = { t = t, s = state }
    while #trail > 3 and trail[2].t < t - self.cfg.keep do
        table.remove(trail, 1)
    end
end

function Puppet:reset()
    self.trail = {}
    self.mode = "warten"
    self.moving = false
    self.net.last_push = nil
    self:release()
end

-- Aktueller Puffer in Sekunden
function Puppet:delay()
    return self.cfg.adaptive and self.net.delay or self.cfg.delay
end

-- Geschwindigkeit am Ende der Spur (ueber etwa 0,1 s)
function Puppet:_end_velocity()
    local trail = self.trail
    local n = #trail
    if n < 2 then
        return 0, 0
    end
    local j = n - 1
    while j > 1 and trail[n].t - trail[j].t < 0.1 do j = j - 1 end
    local dt = trail[n].t - trail[j].t
    if dt <= 0 then
        return 0, 0
    end
    return (trail[n].s.x - trail[j].s.x) / dt, (trail[n].s.z - trail[j].s.z) / dt
end

-- Zustand zur Zeit tt (linear interpoliert) mit Geschwindigkeit vx/vz
function Puppet:_sample(tt)
    local trail = self.trail
    if #trail == 0 or trail[1].t > tt then
        return nil
    end
    if tt >= trail[#trail].t then
        -- Keine neueren Daten (Paket verspaetet): kurz in der letzten Richtung
        -- weiterlaufen, damit die Puppe nicht bei jeder Luecke anhaelt
        local last = trail[#trail].s
        local late = tt - trail[#trail].t
        local vx, vz = 0, 0
        if late < self.cfg.extrapolate then
            vx, vz = self:_end_velocity()
        else
            late = 0
        end
        return { x = last.x + vx * late, y = last.y, z = last.z + vz * late, qx = last.qx, qy = last.qy,
            qz = last.qz, qw = last.qw, vx = vx, vz = vz }
    end
    for i = #trail - 1, 1, -1 do
        local a, b = trail[i], trail[i + 1]
        if a.t <= tt then
            local k = (b.t > a.t) and math.min(1, (tt - a.t) / (b.t - a.t)) or 0
            local s = {
                x = a.s.x + (b.s.x - a.s.x) * k, y = a.s.y, z = a.s.z + (b.s.z - a.s.z) * k,
                qx = b.s.qx, qy = b.s.qy, qz = b.s.qz, qw = b.s.qw,
            }
            -- Geschwindigkeit ueber etwa 0,1 s
            local j = i
            while j > 1 and b.t - trail[j].t < 0.1 do j = j - 1 end
            local dt = b.t - trail[j].t
            s.vx = dt > 0 and (b.s.x - trail[j].s.x) / dt or 0
            s.vz = dt > 0 and (b.s.z - trail[j].s.z) / dt or 0
            return s
        end
    end
    local last = trail[#trail].s
    return { x = last.x, y = last.y, z = last.z, qx = last.qx, qy = last.qy, qz = last.qz, qw = last.qw, vx = 0, vz = 0 }
end

function Puppet:update(t)
    local cfg = self.cfg
    local target = self:_sample(t - self:delay())
    local partner = self.game.read_state(self.game.partner_object())
    if not target or not partner then
        self.mode = "warten"
        self.stats.warten = self.stats.warten + 1
        self:release()
        return self.mode
    end

    local dx, dz = target.x - partner.x, target.z - partner.z
    local dist = math.sqrt(dx * dx + dz * dz)
    local speed = math.sqrt(target.vx * target.vx + target.vz * target.vz)
    self.dist = dist

    if dist > cfg.far then
        self.mode = "teleport"
        self:release()
        self.game.place_partner({ x = target.x, y = target.y, z = target.z, qx = target.qx, qy = target.qy,
            qz = target.qz, qw = target.qw })
    end
    -- Hysterese: Anlaufen erst ab moving_speed, Anhalten erst unter stop_speed
    if speed > cfg.moving_speed then
        self.moving = true
    elseif speed < cfg.stop_speed then
        self.moving = false
    end

    if dist > cfg.far then
        -- (oben schon behandelt)
    elseif self.moving then
        self.mode = "laufen"
        local ax = target.x + target.vx * cfg.lookahead - partner.x
        local az = target.z + target.vz * cfg.lookahead - partner.z
        self:_steer(math.atan(ax, az))
        if dist > cfg.pull_from then
            self.game.place_partner({ x = partner.x + dx * cfg.pull, y = partner.y, z = partner.z + dz * cfg.pull })
        end
    elseif dist > cfg.near then
        self.mode = "hinlaufen"
        self:_steer(math.atan(dx, dz))
    else
        self.mode = "stehen"
        self:release()
        self.game.place_partner({ x = target.x, y = partner.y, z = target.z, qx = target.qx, qy = target.qy,
            qz = target.qz, qw = target.qw })
    end
    self.stats[self.mode] = self.stats[self.mode] + 1
    return self.mode
end

return Puppet
