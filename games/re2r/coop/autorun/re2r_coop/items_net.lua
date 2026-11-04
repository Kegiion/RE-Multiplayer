-- re2r_coop/items_net.lua
--
-- Item-Abgleich (Konzept: docs/re2r-konzept-gegner-tod-items.md, Teil 3).
-- Spielzugriffe nur ueber re2r_coop/game_adapter.lua (alle unbestaetigt).
--
-- Regeln (User, 4. November 2026):
--   * Verbrauchsitems: wer zuerst kommt, das Weltitem verschwindet bei beiden.
--   * Schluessel-/Story-Items: einer hebt auf, beide bekommen es (ITEM_GRANT).
--   * Jeder hat sein eigenes Inventar und seine eigene Itemkiste.
--   * Erstes Beitreten: Waffen passend zur eigenen Figur, Munition, Heilung
--     und Schluessel vom Host, eigene Kiste leer (starting_kit).
--   * Bei HOST_SAVED sichert der Mitspieler sein Inventar, beim erneuten
--     Beitreten (Game Over, Abbruch) bekommt er es zurueck.

local M = {}

-- Handkorrekturen: item_id -> "key" | "consumable" | "weapon" | "other".
-- Vorrang vor der Kategorie aus dem Spiel (I2). Noch leer, weil keine
-- Item-IDs bestaetigt sind.
M.OVERRIDES = {}

-- Kategorie eines Items. "unknown", solange I2 nicht erforscht ist.
function M.classify(item_id, adapter)
    local o = M.OVERRIDES[item_id]
    if o ~= nil then
        return o
    end
    local cat = adapter.item_category(item_id)
    if type(cat) == "string" then
        return cat
    end
    return "unknown"
end

function M.is_key(item_id, adapter)
    return M.classify(item_id, adapter) == "key"
end

-- Startausstattung beim ersten Beitreten.
-- host_inventory = Liste von item (I1) des Hosts, character = SurvivorType
-- des Mitspielers. Waffen des Hosts fallen weg, dafuer kommen die
-- Startwaffen der eigenen Figur (I6). Unbekannte Kategorien werden
-- uebernommen (lieber zu viel als ein fehlender Schluessel).
function M.starting_kit(host_inventory, character, adapter)
    local inventory = {}
    local weapons = adapter.default_weapons(character)
    for _, w in ipairs(type(weapons) == "table" and weapons or {}) do
        inventory[#inventory + 1] = { item_id = w.item_id, count = w.count or 1, extra = w.extra or 0 }
    end
    for _, item in ipairs(host_inventory or {}) do
        if M.classify(item.item_id, adapter) ~= "weapon" then
            inventory[#inventory + 1] = { item_id = item.item_id, count = item.count or 1, extra = item.extra or 0 }
        end
    end
    return { inventory = inventory, box = {} }
end

-- Speicher fuer Inventar-Kopien (Standard: nur im Speicher; im Spiel z. B.
-- json/serial-Datei unter reframework/data).
function M.memory_storage()
    local t = {}
    return {
        save = function(key, data) t[key] = data; return true end,
        load = function(key) return t[key] end,
    }
end

local function copy_key(session_id, slot)
    return string.format("%08x_%d", session_id or 0, slot or -1)
end
M.copy_key = copy_key

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
--
-- Sync.new{ role = "host"|"client", send = function(name, data, reliable),
--           adapter = ..., storage = M.memory_storage(), session_id = Zahl (Host) }
-- sync:install()          Hooks anmelden (einmal)
-- sync:handle(msg, now)
-- sync:restore(session_id, slot)   Mitspieler: eigenes Inventar zurueck
-- sync:reset()            nach Game Over/Neuladen (Welt ist wieder alt)

local Sync = {}
Sync.__index = Sync
M.Sync = Sync

function Sync.new(opts)
    local self = setmetatable({}, Sync)
    self.role = assert(opts.role, "role fehlt")
    self.send = assert(opts.send, "send fehlt")
    self.adapter = opts.adapter or require("re2r_coop.game_adapter")
    self.storage = opts.storage or M.memory_storage()
    self.session_id = opts.session_id or 0
    self.taken = {}       -- Host: item_key -> 0 (Host) | 1 (Mitspieler)
    self.notices = {}     -- Hinweise fuer die Anzeige
    self.last_saved = nil -- Mitspieler: { session_id, slot }
    self.stats = { pickups = 0, conflicts = 0, granted = 0, boxed = 0, failed = 0 }
    return self
end

function Sync:install()
    local a = self.adapter
    a.hook_item_pickup(function(world_key, item_id, count, zone)
        self:on_pickup(world_key, item_id, count, zone)
    end)
    a.hook_item_discard(function(item_id)
        if M.is_key(item_id, a) then
            self.send("ITEM_DISCARD", { item_id = item_id }, true)
        end
    end)
    if self.role == "host" then
        a.hook_host_saved(function(slot)
            self.send("HOST_SAVED", { slot = slot or -1, session_id = self.session_id }, true)
        end)
    end
end

-- Eigener Spieler hat ein Weltitem aufgehoben (I3). Das Item ist schon im
-- eigenen Inventar.
function Sync:on_pickup(world_key, item_id, count, zone)
    self.stats.pickups = self.stats.pickups + 1
    world_key = tostring(world_key or "")
    if self.role == "host" then
        if self.taken[world_key] ~= nil then
            self.stats.conflicts = self.stats.conflicts + 1
        else
            self.taken[world_key] = 0
            self.send("ITEM_TAKEN", { item_key = world_key, by = 0, zone = zone or 65535 }, true)
        end
    else
        self.send("ITEM_PICKUP", { item_key = world_key, item_id = item_id, count = count or 1, zone = zone or 65535 }, true)
    end
    if M.is_key(item_id, self.adapter) then
        self.send("ITEM_GRANT", { item_id = item_id, count = count or 1, extra = 0 }, true)
    end
end

function Sync:_grant(item_id, count, extra)
    local a = self.adapter
    local ok, err = a.give_item(item_id, count, extra)
    if ok then
        self.stats.granted = self.stats.granted + 1
        return true
    end
    if err == "full" then
        local okb = a.put_in_box(item_id, count, extra)
        if okb then
            self.stats.boxed = self.stats.boxed + 1
            self.notices[#self.notices + 1] = "Schluessel-Item liegt in der Itemkiste (Inventar voll)"
            return true
        end
    end
    self.stats.failed = self.stats.failed + 1
    self.notices[#self.notices + 1] = "Schluessel-Item konnte nicht uebernommen werden: " .. tostring(err)
    return false
end

function Sync:handle(msg, now)
    local t = msg.type
    local a = self.adapter
    if t == "ITEM_PICKUP" and self.role == "host" then
        if self.taken[msg.item_key] ~= nil then
            -- Gleichzeitig aufgehoben: beide behalten ihr Exemplar (Grundsatz 4)
            self.stats.conflicts = self.stats.conflicts + 1
        else
            self.taken[msg.item_key] = 1
            a.remove_world_item(msg.item_key, msg.zone)
        end
        self.send("ITEM_TAKEN", { item_key = msg.item_key, by = 1, zone = msg.zone }, true)
    elseif t == "ITEM_TAKEN" and self.role == "client" then
        if msg.by == 0 then
            a.remove_world_item(msg.item_key, msg.zone)
        end
    elseif t == "ITEM_GRANT" then
        self:_grant(msg.item_id, msg.count, msg.extra)
    elseif t == "ITEM_DISCARD" then
        a.remove_item(msg.item_id)
    elseif t == "HOST_SAVED" and self.role == "client" then
        local data = a.capture_inventory()
        if data ~= nil then
            self.storage.save(copy_key(msg.session_id, msg.slot), data)
            self.last_saved = { session_id = msg.session_id, slot = msg.slot }
        end
    end
end

-- Mitspieler, erneutes Beitreten: eigenes Inventar vom letzten Speichern
-- des Hosts zurueck. Gibt false zurueck, wenn es keine Kopie gibt (dann
-- gilt die Startausstattung).
function Sync:restore(session_id, slot)
    local data = self.storage.load(copy_key(session_id, slot))
    if data == nil then
        return false
    end
    local ok = self.adapter.restore_inventory(data)
    return ok == true
end

function Sync:reset()
    self.taken = {}
end

return M
