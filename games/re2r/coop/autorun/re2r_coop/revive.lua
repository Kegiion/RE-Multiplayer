-- re2r_coop/revive.lua
--
-- Zustandsautomat fuer Tod und Wiederbeleben (Konzept:
-- docs/re2r-konzept-gegner-tod-items.md, Teil 2). Reine Logik ohne
-- Spielbezug: Der Host fuehrt eine Instanz und entscheidet allein. Der
-- Mitspieler meldet nur (am Boden, Aufheben beginnen/abbrechen) und spielt
-- die Ergebnisse ab.
--
-- Spieler-IDs sind frei waehlbar (z. B. "host", "client"). Zeit in Sekunden
-- (coopnet.time()). Jede Funktion gibt eine Liste von Ereignissen zurueck,
-- die das Spielskript umsetzt bzw. verschickt:
--   { type = "DOWNED",   pid, deadline }      Spieler liegt am Boden
--   { type = "REVIVE_BEGIN",  pid, by, done_at } Aufheben laeuft
--   { type = "REVIVE_CANCEL", pid, by }        Aufheben abgebrochen
--   { type = "REVIVED",  pid, by }             Spieler steht wieder (by = "auto" bei Zwischensequenz)
--   { type = "GAME_OVER", reason }             "both_down" | "bleedout"
--   { type = "SOLO",     pid }                 Mitspieler weg, pid spielt allein weiter
--
-- UNBESTAETIGT: Alles, was das Spiel betrifft (Liegen, Lebenspunkte setzen,
-- Game Over ausloesen), steht im Konzept unter "Im Spiel zu erforschen".

local revive = {}
revive.__index = revive

revive.DEFAULTS = {
    bleedout = 30.0,     -- Sekunden am Boden bis zum Game Over
    revive_time = 3.0,   -- Sekunden Knopf halten zum Aufheben
    revive_range = 1.5,  -- Meter: hoechster Abstand beim Aufheben
    revive_hp = 0.3,     -- Anteil der Lebenspunkte nach dem Aufheben
}

function revive.new(opts)
    local self = setmetatable({}, revive)
    self.cfg = {}
    for k, v in pairs(revive.DEFAULTS) do
        self.cfg[k] = (opts and opts[k] ~= nil) and opts[k] or v
    end
    self.players = {}  -- pid -> { state = "alive"|"down"|"reviving", deadline, by, done_at }
    self.paused_at = nil
    self.over = false
    return self
end

function revive:add_player(pid)
    self.players[pid] = self.players[pid] or { state = "alive" }
end

function revive:state(pid)
    local p = self.players[pid]
    return p and p.state or nil
end

function revive:is_over()
    return self.over
end

local function count(self)
    local total, standing = 0, 0
    for _, p in pairs(self.players) do
        total = total + 1
        if p.state == "alive" then
            standing = standing + 1
        end
    end
    return total, standing
end

local function game_over(self, events, reason)
    if not self.over then
        self.over = true
        events[#events + 1] = { type = "GAME_OVER", reason = reason }
    end
    return events
end

-- Lebenspunkte von pid sind auf 0 gefallen.
function revive:down(pid, now)
    local events = {}
    local p = self.players[pid]
    if self.over or p == nil or p.state ~= "alive" then
        return events
    end
    -- Wer gerade jemanden aufhebt und selbst faellt, bricht ab.
    for other_id, other in pairs(self.players) do
        if other.state == "reviving" and other.by == pid then
            other.state, other.by, other.done_at = "down", nil, nil
            events[#events + 1] = { type = "REVIVE_CANCEL", pid = other_id, by = pid }
        end
    end
    p.state = "down"
    -- In einer Zwischensequenz zaehlt die Frist erst ab deren Ende
    p.deadline = (self.paused_at or now) + self.cfg.bleedout
    events[#events + 1] = { type = "DOWNED", pid = pid, deadline = p.deadline }
    local total, standing = count(self)
    if total > 1 and standing == 0 then
        return game_over(self, events, "both_down")
    end
    if total == 1 then
        -- Allein: kein Wiederbeleben moeglich, normales Game Over des Spiels
        return game_over(self, events, "both_down")
    end
    return events
end

-- `by` beginnt, `pid` aufzuheben. distance = Abstand in Metern.
function revive:begin(pid, by, now, distance)
    local events = {}
    local p, r = self.players[pid], self.players[by]
    if self.over or self.paused_at or p == nil or r == nil or pid == by then
        return events
    end
    if p.state ~= "down" or r.state ~= "alive" then
        return events
    end
    if distance == nil or distance > self.cfg.revive_range then
        return events
    end
    p.state, p.by = "reviving", by
    p.done_at = now + self.cfg.revive_time
    events[#events + 1] = { type = "REVIVE_BEGIN", pid = pid, by = by, done_at = p.done_at }
    return events
end

-- Knopf losgelassen oder zu weit weg.
function revive:cancel(pid, now)
    local events = {}
    local p = self.players[pid]
    if p == nil or p.state ~= "reviving" then
        return events
    end
    local by = p.by
    p.state, p.by, p.done_at = "down", nil, nil
    -- Kurze Gnadenfrist, falls die Frist waehrend des Aufhebens ablief
    p.deadline = math.max(p.deadline, now + 2.0)
    events[#events + 1] = { type = "REVIVE_CANCEL", pid = pid, by = by }
    return events
end

-- Zwischensequenz beginnt (paused = true) oder endet. Waehrend der
-- Sequenz laeuft keine Frist. Zu Beginn werden Liegende automatisch
-- aufgehoben, damit keine Figur liegend in die Sequenz geht
-- (vom User am 4. November 2026 so entschieden, mit revive_hp).
function revive:cutscene(active, now)
    local events = {}
    if self.over then
        return events
    end
    if active and self.paused_at == nil then
        self.paused_at = now
        for pid, p in pairs(self.players) do
            if p.state ~= "alive" then
                p.state, p.by, p.done_at, p.deadline = "alive", nil, nil, nil
                events[#events + 1] = { type = "REVIVED", pid = pid, by = "auto" }
            end
        end
    elseif not active and self.paused_at ~= nil then
        local pause = now - self.paused_at
        self.paused_at = nil
        for _, p in pairs(self.players) do
            if p.deadline then p.deadline = p.deadline + pause end
            if p.done_at then p.done_at = p.done_at + pause end
        end
    end
    return events
end

-- Verbindung zu pid ist weg.
function revive:remove_player(pid)
    local events = {}
    if self.players[pid] == nil then
        return events
    end
    self.players[pid] = nil
    for other_id, other in pairs(self.players) do
        if other.state == "reviving" and other.by == pid then
            other.state, other.by, other.done_at = "down", nil, nil
            events[#events + 1] = { type = "REVIVE_CANCEL", pid = other_id, by = pid }
        end
        events[#events + 1] = { type = "SOLO", pid = other_id }
        if not self.over and other.state ~= "alive" then
            -- Der Verbliebene liegt am Boden und niemand kann helfen
            game_over(self, events, "bleedout")
        end
    end
    return events
end

-- Jeden Frame (oder mehrmals pro Sekunde) aufrufen.
function revive:update(now)
    local events = {}
    if self.over or self.paused_at then
        return events
    end
    for pid, p in pairs(self.players) do
        if p.state == "reviving" and now >= p.done_at then
            local by = p.by
            p.state, p.by, p.done_at, p.deadline = "alive", nil, nil, nil
            events[#events + 1] = { type = "REVIVED", pid = pid, by = by }
        end
    end
    for _, p in pairs(self.players) do
        -- Waehrend des Aufhebens laeuft die Frist nicht ab
        if p.state == "down" and now >= p.deadline then
            return game_over(self, events, "bleedout")
        end
    end
    return events
end

-- Nach dem Laden des Speicherpunkts: alle wieder stehend.
function revive:reset()
    self.over = false
    self.paused_at = nil
    for _, p in pairs(self.players) do
        p.state, p.by, p.done_at, p.deadline = "alive", nil, nil, nil
    end
end

return revive
