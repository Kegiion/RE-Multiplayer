-- re2r_coop/enemy_net.lua
--
-- Reine Hilfslogik fuer den Gegner-Abgleich (Konzept:
-- docs/re2r-konzept-gegner-tod-items.md, Teil 1). Ohne Spielbezug:
--   * pack_states/unpack_states: viele Gegner in einem Datenfeld (fuer das
--     vorgeschlagene ENEMY_STATE mit einem s2-Feld "data")
--   * zone_owner: wer simuliert die Gegner einer Zone
--   * Chaser: Zielwahl fuer Verfolger (Mr. X) mit Hysterese
--
-- UNBESTAETIGT: Woher Position, Zustand und Animation eines Gegners im
-- Spiel kommen, steht im Konzept unter "Im Spiel zu erforschen".

local M = {}

-- Ein Datensatz je Gegner (26 Bytes):
--   eid I2, x/y/z f, yaw i2 (Radiant * 10000), mode B, target B,
--   bank I2, motion I4, frame I2 (Bild * 10)
M.RECORD = "<I2fffi2BBI2I4I2"
M.RECORD_SIZE = string.packsize(M.RECORD)
M.MAX_RECORDS = 255

M.TARGET_NONE, M.TARGET_HOST, M.TARGET_CLIENT = 0, 1, 2
M.OWNER_HOST, M.OWNER_CLIENT, M.OWNER_NONE = "host", "client", "none"

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- list = { { eid, x, y, z, yaw, mode, target, bank, motion, frame }, ... }
function M.pack_states(list)
    local parts = {}
    local n = math.min(#list, M.MAX_RECORDS)
    for i = 1, n do
        local e = list[i]
        parts[i] = string.pack(M.RECORD,
            e.eid & 0xFFFF,
            e.x or 0, e.y or 0, e.z or 0,
            clamp(math.floor((e.yaw or 0) * 10000 + 0.5), -32768, 32767),
            (e.mode or 0) & 0xFF, (e.target or 0) & 0xFF,
            (e.bank or 0) & 0xFFFF, (e.motion or 0) & 0xFFFFFFFF,
            clamp(math.floor((e.frame or 0) * 10 + 0.5), 0, 65535))
    end
    return string.pack("<B", n) .. table.concat(parts)
end

function M.unpack_states(data)
    if type(data) ~= "string" or #data < 1 then
        return nil, "leer"
    end
    local n = string.byte(data, 1)
    if #data ~= 1 + n * M.RECORD_SIZE then
        return nil, "falsche Laenge"
    end
    local list, pos = {}, 2
    for i = 1, n do
        local eid, x, y, z, yaw, mode, target, bank, motion, frame
        eid, x, y, z, yaw, mode, target, bank, motion, frame, pos = string.unpack(M.RECORD, data, pos)
        list[i] = { eid = eid, x = x, y = y, z = z, yaw = yaw / 10000, mode = mode, target = target,
            bank = bank, motion = motion, frame = frame / 10 }
    end
    return list
end

-- Wer simuliert die Gegner der Zone `zone`?
-- host_zones = Zonen, die im Spiel des Hosts gerade geladen sind
-- (mindestens seine eigene), client_zone = Zone des Mitspielers.
-- Der Host hat Vorrang. Eine Zone, in der nur der Mitspieler ist, wird
-- dem Mitspieler geliehen (er meldet Tode an den Host).
function M.zone_owner(zone, host_zones, client_zone)
    if zone == nil then
        return M.OWNER_NONE
    end
    for _, z in ipairs(host_zones or {}) do
        if z == zone then
            return M.OWNER_HOST
        end
    end
    if zone == client_zone then
        return M.OWNER_CLIENT
    end
    return M.OWNER_NONE
end

-- Zielwahl fuer einen Verfolger (Mr. X) mit Hysterese, damit er nicht
-- zwischen zwei gleich weit entfernten Spielern hin und her springt.
local Chaser = {}
Chaser.__index = Chaser
M.Chaser = Chaser

Chaser.DEFAULTS = {
    margin = 3.0,   -- Meter: der andere muss so viel naeher sein
    hold = 2.0,     -- Sekunden: so lange muss er naeher bleiben
    noise_hold = 8.0, -- Sekunden: nach einem Geraeusch (Schuss) bleibt das Ziel
}

function Chaser.new(opts)
    local self = setmetatable({}, Chaser)
    for k, v in pairs(Chaser.DEFAULTS) do
        self[k] = (opts and opts[k] ~= nil) and opts[k] or v
    end
    self.target = nil
    self.better_since = nil
    self.noise_until = -math.huge
    return self
end

-- Ein Spieler hat Laerm gemacht (Schuss), den der Verfolger hoert.
function Chaser:noise(pid, now)
    self.target = pid
    self.better_since = nil
    self.noise_until = now + self.noise_hold
end

-- dist[pid] = Abstand in Metern, nil = nicht erreichbar (andere Zone,
-- am Boden). Gibt das aktuelle Ziel zurueck (oder nil).
function Chaser:update(dist, now)
    local best, best_d = nil, math.huge
    for pid, d in pairs(dist) do
        if d ~= nil and (d < best_d or (d == best_d and tostring(pid) < tostring(best))) then
            best, best_d = pid, d
        end
    end
    local cur_d = self.target ~= nil and dist[self.target] or nil
    if cur_d == nil then
        -- Ziel weg: sofort das naechste nehmen
        self.target, self.better_since = best, nil
        return self.target
    end
    if best == self.target or now < self.noise_until then
        self.better_since = nil
        return self.target
    end
    if best_d + self.margin <= cur_d then
        self.better_since = self.better_since or now
        if now - self.better_since >= self.hold then
            self.target, self.better_since = best, nil
        end
    else
        self.better_since = nil
    end
    return self.target
end

return M
