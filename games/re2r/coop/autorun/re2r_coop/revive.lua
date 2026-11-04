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

---------------------------------------------------------------------------
-- Controller: verbindet den Automaten mit Netzwerk und Spiel (Adapter)
---------------------------------------------------------------------------
--
-- Controller.new{ role = "host"|"client", send = function(name, data, reliable),
--                 adapter = <re2r_coop.game_adapter>, cfg = { ... wie DEFAULTS },
--                 on_game_over = function(reason, slot) }   -- z. B. erneuter Join
-- c:install()                 Tod-Hook anmelden (einmal)
-- c:peer_joined() / c:peer_left(now)
-- c:update(now, ctx)          ctx = { partner_distance = Meter oder nil }
-- c:handle(msg, now)          empfangene Nachricht
-- c:reset()                   nach dem Laden des Speicherpunkts

local Controller = {}
Controller.__index = Controller
revive.Controller = Controller

revive.EVENT_CODE = { DOWNED = 1, REVIVE_BEGIN = 2, REVIVE_CANCEL = 3, REVIVED = 4, SOLO = 5 }
revive.EVENT_NAME = {}
for k, v in pairs(revive.EVENT_CODE) do revive.EVENT_NAME[v] = k end
revive.WHO_CODE = { host = 0, client = 1, auto = 2 }
revive.WHO_NAME = { [0] = "host", [1] = "client", [2] = "auto" }
revive.REASON_CODE = { both_down = 1, bleedout = 2 }
revive.REASON_NAME = { [1] = "both_down", [2] = "bleedout" }

function Controller.new(opts)
    local self = setmetatable({}, Controller)
    self.role = assert(opts.role, "role fehlt")
    self.other = self.role == "host" and "client" or "host"
    self.send = assert(opts.send, "send fehlt")
    self.adapter = opts.adapter or require("re2r_coop.game_adapter")
    self.on_game_over = opts.on_game_over
    self.cfg = {}
    for k, v in pairs(revive.DEFAULTS) do
        self.cfg[k] = (opts.cfg and opts.cfg[k] ~= nil) and opts.cfg[k] or v
    end
    self.machine = self.role == "host" and revive.new(self.cfg) or nil
    if self.machine then
        self.machine:add_player("host")
    end
    self.state = { host = "alive", client = "alive" }
    self.peer = false
    self.helping = false      -- eigener Spieler hebt gerade auf
    self.cutscene = false
    self.game_over = false
    self.now = 0
    return self
end

function Controller:install()
    self.adapter.hook_player_death(function()
        return self:_on_local_death()
    end)
end

function Controller:peer_joined()
    self.peer = true
    if self.machine then
        self.machine:add_player("client")
    end
end

function Controller:peer_left(now)
    self.peer = false
    self.helping = false
    if self.machine then
        self:_dispatch(self.machine:remove_player("client"), now, false)
    elseif self.state.client ~= "alive" and not self.game_over then
        -- Niemand kann helfen: normales Game Over im eigenen Spiel
        self:_apply_game_over("bleedout", -1)
    end
    self.state[self.other] = "alive"
end

-- Hook: eigener Spieler wuerde sterben. true = Tod verhindern.
function Controller:_on_local_death()
    if not self.peer or self.game_over then
        return false -- allein: normales Spiel
    end
    if self.state[self.role] ~= "alive" then
        return true
    end
    if self.machine then
        self:_dispatch(self.machine:down("host", self.now), self.now, true)
    else
        self.state.client = "down"
        self.adapter.set_downed(true)
        self.send("PLAYER_DOWN", { reserved = 0 }, true)
    end
    return true
end

-- Ereignis lokal umsetzen (beide Rollen).
function Controller:_apply(name, who, by)
    local a = self.adapter
    local me = who == self.role
    if name == "DOWNED" then
        self.state[who] = "down"
        if me then a.set_downed(true) else a.set_partner_downed(true) end
    elseif name == "REVIVE_BEGIN" then
        self.state[who] = "reviving"
    elseif name == "REVIVE_CANCEL" then
        self.state[who] = "down"
        if by == self.role then self.helping = false end
    elseif name == "REVIVED" then
        self.state[who] = "alive"
        if by == self.role then self.helping = false end
        if me then
            a.set_downed(false)
            a.set_player_hp(self.cfg.revive_hp)
        else
            a.set_partner_downed(false)
        end
    end
end

function Controller:_apply_game_over(reason, slot)
    if self.game_over then
        return slot
    end
    self.game_over = true
    if self.role == "host" then
        local s = self.adapter.trigger_game_over()
        slot = type(s) == "number" and s or -1
    else
        self.adapter.trigger_game_over()
    end
    if self.on_game_over then
        self.on_game_over(reason, slot)
    end
    return slot
end

-- Host: Ereignisse des Automaten umsetzen und verschicken.
function Controller:_dispatch(events, now, send)
    for _, ev in ipairs(events) do
        if ev.type == "GAME_OVER" then
            local slot = self:_apply_game_over(ev.reason, -1)
            if send ~= false and self.peer then
                self.send("GAME_OVER", { reason = revive.REASON_CODE[ev.reason] or 0, slot = slot }, true)
            end
        else
            self:_apply(ev.type, ev.pid, ev.by)
            if send ~= false and self.peer and ev.type ~= "SOLO" then
                local left = 0
                if ev.deadline then left = ev.deadline - now end
                if ev.done_at then left = ev.done_at - now end
                self.send("REVIVE_EVENT", { event = revive.EVENT_CODE[ev.type], who = revive.WHO_CODE[ev.pid] or 0,
                    by = revive.WHO_CODE[ev.by] or 0, time_left = math.max(left, 0) }, true)
            end
        end
    end
end

function Controller:update(now, ctx)
    self.now = now
    if not self.peer or self.game_over then
        return
    end
    local a = self.adapter
    local dist = ctx and ctx.partner_distance
    local held = a.revive_button_held() == true
    local other_down = self.state[self.other] == "down" or self.state[self.other] == "reviving"
    local in_range = dist ~= nil and dist <= self.cfg.revive_range

    if self.machine then
        local cut = a.in_cutscene() == true
        if cut ~= self.cutscene then
            self.cutscene = cut
            self:_dispatch(self.machine:cutscene(cut, now), now)
        end
        if not self.helping and held and in_range and self.state.client == "down" and self.state.host == "alive" then
            self.helping = true
            self:_dispatch(self.machine:begin("client", "host", now, dist), now)
            if self.state.client ~= "reviving" then self.helping = false end
        elseif self.helping and (not held or not in_range) then
            self.helping = false
            self:_dispatch(self.machine:cancel("client", now), now)
        end
        self:_dispatch(self.machine:update(now), now)
    else
        if not self.helping and held and in_range and self.state.host == "down" and self.state.client == "alive" then
            self.helping = true
            self.send("REVIVE_REQUEST", { action = 1, distance = dist }, true)
        elseif self.helping and (not held or not in_range or not other_down) then
            self.helping = false
            if other_down then
                self.send("REVIVE_REQUEST", { action = 0, distance = dist or 0 }, true)
            end
        end
    end
end

function Controller:handle(msg, now)
    local t = msg.type
    if self.machine then
        if t == "PLAYER_DOWN" then
            self:_dispatch(self.machine:down("client", now), now)
        elseif t == "REVIVE_REQUEST" then
            if msg.action == 1 then
                self:_dispatch(self.machine:begin("host", "client", now, msg.distance), now)
            else
                self:_dispatch(self.machine:cancel("host", now), now)
            end
        end
    else
        if t == "REVIVE_EVENT" then
            local name = revive.EVENT_NAME[msg.event]
            if name ~= nil and name ~= "SOLO" then
                self:_apply(name, revive.WHO_NAME[msg.who], revive.WHO_NAME[msg.by])
            end
        elseif t == "GAME_OVER" then
            self:_apply_game_over(revive.REASON_NAME[msg.reason] or "both_down", msg.slot)
        end
    end
end

function Controller:reset()
    if self.machine then
        self.machine:reset()
    end
    self.state = { host = "alive", client = "alive" }
    self.helping = false
    self.cutscene = false
    self.game_over = false
end

-- Bits fuer PLAYER_STATE.flags (erst mit protocol.VERSION 4 aktiv).
revive.FLAG_DOWN, revive.FLAG_REVIVING, revive.FLAG_DANGER = 1, 2, 4

function Controller:flags()
    local s = self.state[self.role]
    if s == "down" then return revive.FLAG_DOWN end
    if s == "reviving" then return revive.FLAG_DOWN | revive.FLAG_REVIVING end
    return 0
end

return revive
