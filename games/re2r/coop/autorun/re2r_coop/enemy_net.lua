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

---------------------------------------------------------------------------
-- Rueckgabe einer geliehenen Zone (ENEMY_HANDOVER.data)
---------------------------------------------------------------------------

M.HANDOVER_RECORD = "<s1ffffB" -- key, x, y, z, hp, dead

function M.pack_handover(list)
    local parts = { string.pack("<I2", math.min(#list, 65535)) }
    for i = 1, math.min(#list, 65535) do
        local e = list[i]
        parts[#parts + 1] = string.pack(M.HANDOVER_RECORD, (e.key or ""):sub(1, 255),
            e.x or 0, e.y or 0, e.z or 0, e.hp or 0, e.dead and 1 or 0)
    end
    return table.concat(parts)
end

function M.unpack_handover(data)
    local ok, result = pcall(function()
        local n, pos = string.unpack("<I2", data)
        local list = {}
        for i = 1, n do
            local key, x, y, z, hp, dead
            key, x, y, z, hp, dead, pos = string.unpack(M.HANDOVER_RECORD, data, pos)
            list[i] = { key = key, x = x, y = y, z = z, hp = hp, dead = dead == 1 }
        end
        return list
    end)
    if not ok then
        return nil, tostring(result)
    end
    return result
end

---------------------------------------------------------------------------
-- Zuordnung: Gegner aus ENEMY_SPAWN zu einem Gegner im eigenen Spiel
---------------------------------------------------------------------------

M.MATCH_DISTANCE = 2.0

-- spawn = { key, kind, x, y, z }, candidates = Liste von enemy (Adapter),
-- taken[ref] = true fuer schon zugeordnete. Gibt den passenden enemy oder nil.
-- Erst ueber die stabile Kennung (E1), sonst naechster derselben Art bis 2 m.
function M.match_enemy(spawn, candidates, taken)
    taken = taken or {}
    if spawn.key ~= nil and spawn.key ~= "" then
        for _, c in ipairs(candidates) do
            if c.key == spawn.key and not taken[c.ref] then
                return c
            end
        end
    end
    local best, best_d = nil, M.MATCH_DISTANCE
    for _, c in ipairs(candidates) do
        if not taken[c.ref] and c.kind == spawn.kind and (c.key == nil or c.key == "" or spawn.key == "") then
            local dx, dy, dz = (c.x or 0) - spawn.x, (c.y or 0) - spawn.y, (c.z or 0) - spawn.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d <= best_d then
                best, best_d = c, d
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Sync: Gegner-Abgleich fuer eine Seite (Host oder Mitspieler)
---------------------------------------------------------------------------
--
-- Sync.new{ role = "host"|"client", send = function(name, data, reliable),
--           adapter = <re2r_coop.game_adapter> }
-- sync:install()            Hooks beim Adapter anmelden (einmal)
-- sync:update(now, ctx)     regelmaessig, ctx siehe unten
-- sync:handle(msg, now)     empfangene Nachricht (protocol.decode)
--
-- ctx = { host_zones = {Map.ID, ...}  -- beim Host: geladene Zonen (E10), beim
--                                     -- Mitspieler: Zone des Hosts aus PLAYER_STATE
--         client_zone = Map.ID,
--         host_pos = {x,y,z}, client_pos = {x,y,z},
--         host_down = bool, client_down = bool }

local Sync = {}
Sync.__index = Sync
M.Sync = Sync

Sync.STATE_INTERVAL = 0.1      -- 10x pro Sekunde
Sync.RETRY_MATCH = 1.0         -- Sekunden zwischen Zuordnungsversuchen
Sync.HOST_CLAIM_TIMEOUT = 1.0  -- Host sendet fuer die Zone: sie gehoert ihm
Sync.MAX_HIT_DAMAGE = 5000     -- Plausibilitaet fuer ENEMY_HIT
Sync.MAX_HITS_PER_SECOND = 20
Sync.MAX_HIT_RANGE = 60        -- Meter zwischen Partner-Figur und Gegner
Sync.EID_BASE = { host = 1, client = 32768 }
Sync.EID_LIMIT = { host = 32767, client = 65535 }

local function adapter_list(v)
    if type(v) == "table" then
        return v
    end
    return {}
end

local function dist(a, b)
    if a == nil or b == nil then
        return nil
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Sync.new(opts)
    local self = setmetatable({}, Sync)
    self.role = assert(opts.role, "role fehlt")
    self.send = assert(opts.send, "send fehlt")
    self.adapter = opts.adapter or require("re2r_coop.game_adapter")
    self.next_eid = Sync.EID_BASE[self.role]
    -- eigene (simulierte) Gegner: eid -> { ref, key, kind, zone, hp, dead, killer }
    self.own = {}
    self.own_by_ref = {}
    -- Puppen fuer Gegner der Gegenseite: eid -> { ref|nil, spawn, zone, next_try }
    self.puppets = {}
    self.puppet_by_ref = {}
    self.dead_refs = {}    -- im eigenen Spiel per ENEMY_DEAD getoetet: nie wieder uebernehmen
    self.host_claims = {}  -- zone -> Zeit der letzten Host-Nachricht (nur Mitspieler)
    self.owned_zones = {}  -- zone -> true
    self.last_state = -math.huge
    self.seq = 0
    self.hit_seq = 0
    self.hits = { second = -1, count = 0 }
    self.chaser = Chaser.new()
    self.chaser_ref = nil
    self.chaser_target = nil
    self.stats = { hits_sent = 0, hits_applied = 0, hits_rejected = 0, blocked = 0, unmatched = 0 }
    return self
end

local function who_code(who)
    return who == "host" and M.TARGET_HOST or (who == "client" and M.TARGET_CLIENT or M.TARGET_NONE)
end

-- Hooks anmelden (einmal pro Skriptstart).
function Sync:install()
    local a = self.adapter
    a.hook_enemy_damage(function(ref, damage, part, weapon, flags, source)
        return self:_on_enemy_damage(ref, damage, part, weapon, flags, source)
    end)
    a.hook_player_damage(function(victim, damage, enemy_ref, kind, dir)
        return self:_on_player_damage(victim, damage, enemy_ref, kind, dir)
    end)
    a.hook_noise(function(who)
        self.chaser:noise(who, self.now or 0)
    end)
end

-- Welche Zonen simuliert diese Seite gerade?
function Sync:_compute_owned(ctx, now)
    local owned = {}
    if self.role == "host" then
        for _, z in ipairs(ctx.host_zones or {}) do
            owned[z] = true
        end
    else
        local z = ctx.client_zone
        local claimed = self.host_claims[z] ~= nil and now - self.host_claims[z] < Sync.HOST_CLAIM_TIMEOUT
        if not claimed and M.zone_owner(z, ctx.host_zones, z) == M.OWNER_CLIENT then
            owned[z] = true
        end
    end
    return owned
end

function Sync:_new_eid()
    local eid = self.next_eid
    self.next_eid = eid + 1
    if self.next_eid > Sync.EID_LIMIT[self.role] then
        self.next_eid = Sync.EID_BASE[self.role]
    end
    return eid
end

function Sync:_spawn_msg(eid, o, e)
    return { eid = eid, kind = o.kind or "", key = o.key or "", zone = o.zone or 65535,
        x = e.x, y = e.y, z = e.z, yaw = e.yaw, hp = e.hp, hp_max = e.hp_max, flags = 0 }
end

-- Diese Seite simuliert die Zone nicht mehr. Mitspieler: Rueckgabe an den
-- Host (ENEMY_HANDOVER). Host: Puppen beim Mitspieler freigeben
-- (ENEMY_DESPAWN Grund 1), damit sein Spiel sie uebernehmen kann.
function Sync:_release_zone(zone)
    local list = {}
    for eid, o in pairs(self.own) do
        if o.zone == zone then
            local e = self.adapter.read_enemy(o.ref) or {}
            list[#list + 1] = { key = o.key, x = e.x, y = e.y, z = e.z, hp = o.hp, dead = o.dead }
            if self.role == "host" and not o.dead then
                self.send("ENEMY_DESPAWN", { eid = eid, reason = 1 }, true)
            end
            self.own[eid] = nil
            self.own_by_ref[o.ref] = nil
        end
    end
    if self.role == "client" then
        self.send("ENEMY_HANDOVER", { zone = zone, data = M.pack_handover(list) }, true)
    end
end

-- Zone wird uebernommen: Puppen darin werden wieder echte Gegner.
function Sync:_adopt_zone(zone)
    for eid, p in pairs(self.puppets) do
        if p.zone == zone then
            if p.ref ~= nil then
                self.adapter.freeze_ai(p.ref, false)
                self.puppet_by_ref[p.ref] = nil
            end
            self.puppets[eid] = nil
        end
    end
end

function Sync:update(now, ctx)
    self.now = now
    local a = self.adapter
    local owned = self:_compute_owned(ctx, now)
    for z in pairs(self.owned_zones) do
        if not owned[z] then
            self:_release_zone(z)
        end
    end
    for z in pairs(owned) do
        if not self.owned_zones[z] then
            self:_adopt_zone(z)
        end
    end
    self.owned_zones = owned

    local send_state = now - self.last_state >= Sync.STATE_INTERVAL
    if send_state then
        self.last_state = now
    end

    for zone in pairs(owned) do
        local seen, records = {}, {}
        for _, e in ipairs(adapter_list(a.get_enemies(zone))) do
          if not self.dead_refs[e.ref] then
            local eid = self.own_by_ref[e.ref]
            local o = eid and self.own[eid]
            if o == nil then
                eid = self:_new_eid()
                o = { ref = e.ref, key = e.key, kind = e.kind, zone = zone, hp = e.hp, dead = false, killer = 2 }
                self.own[eid], self.own_by_ref[e.ref] = o, eid
                self.send("ENEMY_SPAWN", self:_spawn_msg(eid, o, e), true)
            end
            seen[eid] = true
            if not o.dead then
                if e.hp ~= nil and e.hp ~= o.hp then
                    o.hp = e.hp
                    self.send("ENEMY_HP", { eid = eid, hp = e.hp, flags = 0 }, true)
                end
                if e.hp ~= nil and e.hp <= 0 then
                    o.dead = true
                    self.send("ENEMY_DEAD", { eid = eid, key = o.key or "", zone = zone, killer = o.killer }, true)
                else
                    local target = 0
                    if e.ref == self.chaser_ref then
                        target = who_code(self.chaser_target)
                    end
                    records[#records + 1] = { eid = eid, x = e.x, y = e.y, z = e.z, yaw = e.yaw, mode = e.mode,
                        target = target, bank = e.bank, motion = e.motion, frame = e.frame }
                end
            end
          end
        end
        for eid, o in pairs(self.own) do
            if o.zone == zone and not seen[eid] then
                if not o.dead then
                    self.send("ENEMY_DESPAWN", { eid = eid, reason = 0 }, true)
                end
                self.own[eid] = nil
                self.own_by_ref[o.ref] = nil
            end
        end
        if send_state then
            self.seq = (self.seq + 1) % 4294967296
            self.send("ENEMY_STATE", { seq = self.seq, zone = zone, data = M.pack_states(records) }, false)
        end
    end

    -- Puppen ohne Zuordnung erneut versuchen (Zone evtl. erst jetzt geladen)
    for _, p in pairs(self.puppets) do
        if p.ref == nil and now >= p.next_try then
            self:_try_match(p, now)
        end
    end

    if self.role == "host" then
        self:_update_chaser(now, ctx)
    end
end

-- Mr. X (nur Host): Ziel waehlen und an die KI geben.
function Sync:_update_chaser(now, ctx)
    local a = self.adapter
    local ref = a.find_chaser()
    self.chaser_ref = ref
    if ref == nil then
        self.chaser_target = nil
        return
    end
    local e = a.read_enemy(ref)
    if e == nil then
        return
    end
    local client_reachable = false
    for _, z in ipairs(ctx.host_zones or {}) do
        if z == ctx.client_zone then
            client_reachable = true
        end
    end
    local d = {
        host = (not ctx.host_down) and dist(e, ctx.host_pos) or nil,
        client = (client_reachable and not ctx.client_down) and dist(e, ctx.client_pos) or nil,
    }
    local target = self.chaser:update(d, now)
    if target ~= self.chaser_target then
        self.chaser_target = target
        if target ~= nil then
            a.set_chase_target(ref, target)
        end
    end
end

function Sync:_try_match(p, now)
    local cands = adapter_list(self.adapter.get_enemies(p.zone))
    local taken = {}
    for ref in pairs(self.puppet_by_ref) do taken[ref] = true end
    for ref in pairs(self.own_by_ref) do taken[ref] = true end
    for ref in pairs(self.dead_refs) do taken[ref] = true end
    local c = M.match_enemy(p.spawn, cands, taken)
    if c == nil then
        p.next_try = now + Sync.RETRY_MATCH
        self.stats.unmatched = self.stats.unmatched + 1
        return false
    end
    p.ref = c.ref
    self.puppet_by_ref[c.ref] = p.eid
    self.adapter.freeze_ai(c.ref, true)
    if p.spawn.hp ~= nil then
        self.adapter.set_enemy_hp(c.ref, p.spawn.hp)
    end
    return true
end

function Sync:_drop_puppet(eid)
    local p = self.puppets[eid]
    if p ~= nil then
        if p.ref ~= nil then
            self.puppet_by_ref[p.ref] = nil
        end
        self.puppets[eid] = nil
    end
    return p
end

-- Hook: Treffer an einem Gegner im eigenen Spiel. true = Abzug verhindern.
function Sync:_on_enemy_damage(ref, damage, part, weapon, flags, source)
    local peid = self.puppet_by_ref[ref]
    if peid ~= nil then
        -- Puppe: nur der Besitzer zieht ab
        if source == "local" then
            self.hit_seq = (self.hit_seq + 1) % 4294967296
            self.stats.hits_sent = self.stats.hits_sent + 1
            self.send("ENEMY_HIT", { hit_seq = self.hit_seq, eid = peid, damage = damage, part = part or 0,
                weapon = weapon or 0, flags = flags or 0 }, true)
        end
        self.stats.blocked = self.stats.blocked + 1
        return true
    end
    -- Eigener Gegner: Schuesse der Partner-Figur zaehlen nicht (Grundsatz 3),
    -- dafuer kommt ENEMY_HIT von der Gegenseite
    if source == "partner" then
        self.stats.blocked = self.stats.blocked + 1
        return true
    end
    local eid = self.own_by_ref[ref]
    if eid ~= nil and source == "local" then
        self.own[eid].killer = self.role == "host" and 0 or 1
    end
    return false
end

-- Hook: Gegner trifft eine Spielfigur. true = Abzug verhindern.
function Sync:_on_player_damage(victim, damage, enemy_ref, kind, dir)
    if victim ~= "partner" then
        return false
    end
    if self.role == "host" then
        self.send("PLAYER_HIT", { eid = self.own_by_ref[enemy_ref] or 0, damage = damage,
            kind = kind or 0, dir = dir or 0 }, true)
    end
    -- Die Lebenspunkte gehoeren dem anderen Spieler, hier nie abziehen
    return true
end

function Sync:_accept_hit(msg, o, now)
    if o == nil or o.dead or o.ref == nil then
        return false
    end
    if type(msg.damage) ~= "number" or msg.damage <= 0 or msg.damage > Sync.MAX_HIT_DAMAGE then
        return false
    end
    local second = math.floor(now)
    if self.hits.second ~= second then
        self.hits.second, self.hits.count = second, 0
    end
    self.hits.count = self.hits.count + 1
    if self.hits.count > Sync.MAX_HITS_PER_SECOND then
        return false
    end
    if self.client_pos ~= nil then
        local e = self.adapter.read_enemy(o.ref)
        local d = e and dist(e, self.client_pos)
        if d ~= nil and d > Sync.MAX_HIT_RANGE then
            return false
        end
    end
    return true
end

function Sync:handle(msg, now, ctx)
    local t = msg.type
    local a = self.adapter
    if ctx ~= nil then
        self.client_pos = ctx.client_pos
    end
    if t == "ENEMY_SPAWN" then
        if self.owned_zones[msg.zone] then
            return -- eigene Zone, Gegenseite ist (noch) nicht aktuell
        end
        self:_drop_puppet(msg.eid)
        local p = { eid = msg.eid, zone = msg.zone, next_try = now,
            spawn = { key = msg.key, kind = msg.kind, x = msg.x, y = msg.y, z = msg.z, hp = msg.hp } }
        self.puppets[msg.eid] = p
        self:_try_match(p, now)
    elseif t == "ENEMY_STATE" then
        if self.role == "client" then
            self.host_claims[msg.zone] = now
        end
        local list = M.unpack_states(msg.data)
        for _, r in ipairs(list or {}) do
            local p = self.puppets[r.eid]
            if p ~= nil and p.ref ~= nil then
                a.set_enemy_pose(p.ref, r)
            end
        end
    elseif t == "ENEMY_HP" then
        local p = self.puppets[msg.eid]
        if p ~= nil then
            p.spawn.hp = msg.hp
            if p.ref ~= nil then
                a.set_enemy_hp(p.ref, msg.hp)
            end
        end
    elseif t == "ENEMY_DEAD" then
        local p = self:_drop_puppet(msg.eid)
        if p ~= nil and p.ref ~= nil then
            self.dead_refs[p.ref] = true
            a.kill_enemy(p.ref)
        end
        if self.role == "host" and msg.key ~= "" then
            -- Tod aus einer geliehenen Zone in die Host-Welt eintragen
            a.mark_enemy_dead(msg.key, msg.zone)
        end
    elseif t == "ENEMY_DESPAWN" then
        local p = self:_drop_puppet(msg.eid)
        if p ~= nil and p.ref ~= nil and msg.reason == 1 then
            -- Besitzwechsel: das eigene Spiel steuert den Gegner wieder.
            -- Grund 0 (beim Besitzer verschwunden): Puppe bleibt eingefroren.
            a.freeze_ai(p.ref, false)
        end
    elseif t == "ENEMY_HIT" then
        if self.role ~= "host" then
            return
        end
        local o = self.own[msg.eid]
        if self:_accept_hit(msg, o, now) then
            o.killer = 1
            a.apply_damage(o.ref, msg.damage, msg.part, msg.weapon, msg.flags)
            self.stats.hits_applied = self.stats.hits_applied + 1
        else
            self.stats.hits_rejected = self.stats.hits_rejected + 1
        end
    elseif t == "PLAYER_HIT" then
        if self.role == "client" then
            a.apply_player_damage(msg.damage, msg.kind, msg.dir)
        end
    elseif t == "ENEMY_HANDOVER" then
        if self.role ~= "host" then
            return
        end
        local list = M.unpack_handover(msg.data) or {}
        local by_key = {}
        for _, e in ipairs(adapter_list(a.get_enemies(msg.zone))) do
            if e.key ~= nil and e.key ~= "" then
                by_key[e.key] = e
            end
        end
        for _, r in ipairs(list) do
            if r.key ~= "" then
                if r.dead then
                    a.mark_enemy_dead(r.key, msg.zone)
                elseif by_key[r.key] ~= nil and r.hp < (by_key[r.key].hp or math.huge) then
                    -- nur senken: ein Gegner wird durch die Rueckgabe nie geheilt
                    a.set_enemy_hp(by_key[r.key].ref, r.hp)
                end
            end
        end
    end
end

return M
