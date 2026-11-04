-- remultiplayer_coop/protocol.lua
--
-- Netzwerk-Protokoll aller RE:Multiplayer-Koop-Mods. Jede Nachricht beginnt mit einem
-- Byte fuer den Typ, danach folgen die Felder als kompakte Binaerdaten
-- (string.pack, little-endian).
--
-- Neue Nachricht hinzufuegen:
--   1. Eintrag in `messages` mit eindeutiger ID ergaenzen.
--   2. Falls sich bestehende Nachrichten aendern: VERSION erhoehen.
--
-- Formatzeichen (siehe Lua-Handbuch, string.pack):
--   B = uint8, I2 = uint16, I4 = uint32, f = float32, s1 = String bis 255 Bytes,
--   s2 = String bis 65535 Bytes

local protocol = {}

-- Muss bei beiden Spielern gleich sein, sonst wird die Verbindung abgelehnt.
protocol.VERSION = 3 -- 2: ANIM_BANKS und ANIM_STATE, 3: 6 Ebenen, Neustarts, Waffenmodell

local messages = {
    -- Wird direkt nach dem Verbinden von beiden Seiten geschickt.
    HELLO = {
        id = 1,
        fields = {
            { "protocol", "I2" },
            { "game", "s1" },       -- z. B. "re2r"
            { "mod_version", "s1" },
            { "name", "s1" },       -- Anzeigename des Spielers
            { "want_reply", "B" },  -- 1 = Gegenseite soll mit HELLO antworten
        },
    },
    -- Position/Blickrichtung des Spielers, ca. 20x pro Sekunde (unreliable).
    PLAYER_STATE = {
        id = 2,
        fields = {
            { "seq", "I4" },        -- laufende Nummer, um alte Pakete zu verwerfen
            { "area", "s1" },       -- Kennung des aktuellen Bereichs (spielabhaengig)
            { "x", "f" }, { "y", "f" }, { "z", "f" },
            { "qx", "f" }, { "qy", "f" }, { "qz", "f" }, { "qw", "f" },
            { "character", "B" },  -- spielabhaengige Figur-ID
            { "flags", "B" },      -- Bitfeld, spielabhaengig
        },
    },
    -- Chat / Testnachricht.
    CHAT = {
        id = 3,
        fields = {
            { "text", "s1" },
        },
    },
    -- Animations-Dateien der Figur (Ressourcen-Pfade, spielabhaengig).
    -- Reliable, bei Aenderung und regelmaessig (Gegenseite kann neu laden).
    ANIM_BANKS = {
        id = 4,
        fields = {
            { "banks_id", "I2" },   -- laufende Nummer des Satzes, ANIM_STATE verweist darauf
            { "main", "s1" },       -- Haupt-Bank
            { "dyn1", "s1" }, { "dyn2", "s1" }, { "dyn3", "s1" }, { "dyn4", "s1" }, -- weitere Baenke, "" = keine
            -- Waffenmodell in der Hand ("" = keine) und sein Sitz relativ zum Handgelenk
            { "weapon_mesh", "s1" }, { "weapon_mdf", "s1" },
            { "wqx", "f" }, { "wqy", "f" }, { "wqz", "f" }, { "wqw", "f" },
            { "wx", "f" }, { "wy", "f" }, { "wz", "f" },
        },
    },
    -- Laufende Animationen der Ebenen 0..5, ca. 20x pro Sekunde (unreliable).
    -- Felder je Ebene siehe anim_state_fields() unten. motion = 0xFFFFFFFF
    -- heisst: Ebene leer. interp/imode/icurve beschreiben die Ueberblendung
    -- beim Wechsel (Dauer in Bildern, Art, Kurve), restart zaehlt Neustarts
    -- derselben Animation (z. B. Schuss nach Schuss).
    -- var1..var12 und bits: Steuer-Variablen der Animation (spielabhaengig,
    -- Bedeutung legt das Spielskript fest).
    ANIM_STATE = {
        id = 5,
        fields = nil, -- wird unten erzeugt
    },
    -- Spielstand-Uebertragung (Join auf den Spielstand des Hosts), alles reliable.
    -- Der Mitspieler fragt an, der Host schickt SAVE_BEGIN und danach die Stuecke.
    SAVE_REQUEST = {
        id = 6,
        fields = {
            { "reserved", "B" },
        },
    },
    SAVE_BEGIN = {
        id = 7,
        fields = {
            { "transfer", "I4" },   -- Kennung der Uebertragung
            { "size", "I4" },       -- Gesamtgroesse in Bytes, 0 = Host hat keinen Spielstand
            { "chunks", "I2" },
            { "checksum", "I4" },   -- Adler-32 der Daten
            { "info", "s1" },       -- Beschreibung fuer die Anzeige (spielabhaengig)
        },
    },
    SAVE_CHUNK = {
        id = 8,
        fields = {
            { "transfer", "I4" },
            { "index", "I2" },      -- 0-basiert
            { "data", "s2" },       -- bis 65535 Bytes
        },
    },
    -- Eingaben des Spielers (RE2: steuert beim Gegenueber eine echte zweite
    -- Spielfigur). Unzuverlaessig, bis 60x pro Sekunde. Die Felder werden
    -- unten erzeugt (input_state_fields). VERSION bleibt absichtlich 3
    -- (abgestimmt mit RE0): alte Staende ignorieren unbekannte IDs.
    INPUT_STATE = {
        id = 9,
        fields = {},
    },

    -- Gegner, Tod und Items (RE2, Konzept docs/re2r-konzept-gegner-tod-items.md).
    -- Noch in keinem Spiel aktiv. VERSION bleibt 3, bis ein Teil davon im
    -- Spiel genutzt wird (dann 4). zone = Map.ID als Zahl, 65535 = unbekannt.

    -- Besitzer der Zone -> andere Seite: Gegner erscheint (bzw. neu verbunden).
    ENEMY_SPAWN = {
        id = 10,
        fields = {
            { "eid", "I2" },        -- Netz-Kennung, gilt fuer die Verbindung
            { "kind", "s1" },       -- Art (spielabhaengig)
            { "key", "s1" },        -- stabile Kennung aus dem Spiel, "" = keine
            { "zone", "I2" },
            { "x", "f" }, { "y", "f" }, { "z", "f" }, { "yaw", "f" },
            { "hp", "f" }, { "hp_max", "f" },
            { "flags", "B" },
        },
    },
    -- Alle Gegner einer Zone, ca. 10x pro Sekunde (unreliable). data = eigenes
    -- Format des Spielskripts (RE2: re2r_coop/enemy_net.pack_states).
    ENEMY_STATE = {
        id = 11,
        fields = {
            { "seq", "I4" },
            { "zone", "I2" },
            { "data", "s2" },
        },
    },
    ENEMY_HP = {
        id = 12,
        fields = {
            { "eid", "I2" },
            { "hp", "f" },
            { "flags", "B" },       -- Bit 0 betaeubt/umgefallen, Bit 1 Koerperteil verloren
        },
    },
    ENEMY_DEAD = {
        id = 13,
        fields = {
            { "eid", "I2" },
            { "key", "s1" },
            { "zone", "I2" },
            { "killer", "B" },      -- 0 Host, 1 Mitspieler, 2 Umgebung
        },
    },
    ENEMY_DESPAWN = {
        id = 14,
        fields = {
            { "eid", "I2" },
            { "reason", "B" },      -- 0 Zone entladen, 1 Besitzwechsel
        },
    },
    -- Mitspieler -> Host: Treffer, so wie der Schuetze ihn gesehen hat.
    ENEMY_HIT = {
        id = 15,
        fields = {
            { "hit_seq", "I4" },
            { "eid", "I2" },
            { "damage", "f" },
            { "part", "B" },        -- Koerperteil (spielabhaengig)
            { "weapon", "I2" },
            { "flags", "B" },       -- Bit 0 kritisch, Bit 1 Messer
        },
    },
    -- Host -> Mitspieler: ein Gegner hat die Partner-Figur getroffen.
    PLAYER_HIT = {
        id = 16,
        fields = {
            { "eid", "I2" },
            { "damage", "f" },
            { "kind", "B" },        -- 0 normal, 1 Packen beginnt, 2 Packen endet
            { "dir", "f" },         -- Richtung des Treffers (Radiant)
        },
    },
    -- Leihbesitzer -> Host: Rueckgabe einer Zone (data = eigenes Format).
    ENEMY_HANDOVER = {
        id = 17,
        fields = {
            { "zone", "I2" },
            { "data", "s2" },
        },
    },
    -- Spieler -> Host: meine Lebenspunkte sind auf 0.
    PLAYER_DOWN = {
        id = 18,
        fields = {
            { "reserved", "B" },
        },
    },
    -- Helfer -> Host: Aufheben beginnen (1) oder abbrechen (0).
    REVIVE_REQUEST = {
        id = 19,
        fields = {
            { "action", "B" },
            { "distance", "f" },
        },
    },
    -- Host -> Mitspieler: Ergebnis des Wiederbelebens.
    REVIVE_EVENT = {
        id = 20,
        fields = {
            { "event", "B" },       -- 1 DOWNED, 2 REVIVE_BEGIN, 3 REVIVE_CANCEL, 4 REVIVED, 5 SOLO
            { "who", "B" },         -- 0 Host, 1 Mitspieler
            { "by", "B" },          -- 0 Host, 1 Mitspieler, 2 automatisch
            { "time_left", "f" },
        },
    },
    GAME_OVER = {
        id = 21,
        fields = {
            { "reason", "B" },      -- 1 beide am Boden, 2 Frist abgelaufen
            { "slot", "i2" },       -- Speicherplatz, den der Host laedt (-1 = unbekannt)
        },
    },
    -- Mitspieler -> Host: Weltitem aufgehoben.
    ITEM_PICKUP = {
        id = 22,
        fields = {
            { "item_key", "s1" },   -- Kennung des Weltitems
            { "item_id", "I4" },
            { "count", "I2" },
            { "zone", "I2" },
        },
    },
    -- Host -> Mitspieler: Weltitem ist weg.
    ITEM_TAKEN = {
        id = 23,
        fields = {
            { "item_key", "s1" },
            { "by", "B" },          -- 0 Host, 1 Mitspieler
            { "zone", "I2" },
        },
    },
    -- Finder -> anderer: Schluessel-/Story-Item auch bekommen.
    ITEM_GRANT = {
        id = 24,
        fields = {
            { "item_id", "I4" },
            { "count", "I2" },
            { "extra", "I4" },      -- spielabhaengig
        },
    },
    ITEM_DISCARD = {
        id = 25,
        fields = {
            { "item_id", "I4" },
        },
    },
    -- Host -> Mitspieler: Host hat gespeichert (Mitspieler sichert sein Inventar).
    HOST_SAVED = {
        id = 26,
        fields = {
            { "slot", "i2" },
            { "session_id", "I4" },
        },
    },
}

protocol.ANIM_LAYERS = 6

local function anim_state_fields()
    local fields = { { "seq", "I4" }, { "banks_id", "I2" } }
    for i = 0, protocol.ANIM_LAYERS - 1 do
        for _, f in ipairs({ { "bank", "I2" }, { "motion", "I4" }, { "frame", "f" }, { "interp", "f" },
            { "imode", "B" }, { "icurve", "B" }, { "restart", "B" } }) do
            fields[#fields + 1] = { f[1] .. i, f[2] }
        end
    end
    fields[#fields + 1] = { "bits", "I4" }
    for i = 1, 12 do
        fields[#fields + 1] = { "var" .. i, "f" }
    end
    return fields
end
messages.ANIM_STATE.fields = anim_state_fields()

local function input_state_fields()
    local fields = {
        { "seq", "I4" },
        { "on_lo", "I4" }, { "on_hi", "I4" }, -- 64-Bit-Knopfmaske (RE2: InputDefine.Kind)
    }
    for _, s in ipairs({ "l", "r" }) do
        for _, f in ipairs({ "x", "y", "mag", "ang", "dx", "dy", "dz" }) do
            fields[#fields + 1] = { s .. f, "f" }
        end
        for _, f in ipairs({ "pw", "pwh", "pwv" }) do
            fields[#fields + 1] = { s .. f, "B" }
        end
    end
    fields[#fields + 1] = { "al", "f" }
    fields[#fields + 1] = { "ar", "f" }
    fields[#fields + 1] = { "cam_yaw", "f" } -- Blickrichtung der Kamera (Radiant), Sticks sind kamerarelativ
    return fields
end
messages.INPUT_STATE.fields = input_state_fields()

protocol.MSG = {}
local by_id = {}

for name, def in pairs(messages) do
    local format = "<B"
    for _, field in ipairs(def.fields) do
        format = format .. field[2]
    end
    def.name = name
    def.format = format
    protocol.MSG[name] = def.id
    assert(by_id[def.id] == nil, "doppelte Nachrichten-ID " .. def.id)
    by_id[def.id] = def
end

-- Wandelt eine Tabelle in einen Binaerstring um.
-- Fehlende Zahlenfelder werden zu 0, fehlende Strings zu "".
function protocol.encode(msg_name, data)
    local def = messages[msg_name]
    assert(def, "unbekannte Nachricht: " .. tostring(msg_name))

    local values = {}
    for i, field in ipairs(def.fields) do
        local value = data[field[1]]
        if field[2]:sub(1, 1) == "s" then
            value = tostring(value or "")
            local max = (1 << (8 * tonumber(field[2]:sub(2)))) - 1
            if #value > max then
                value = value:sub(1, max)
            end
        else
            value = tonumber(value) or 0
            if field[2] ~= "f" then
                value = math.floor(value)
            end
        end
        values[i] = value
    end
    return string.pack(def.format, def.id, table.unpack(values, 1, #def.fields))
end

-- Liest einen Binaerstring. Gibt eine Tabelle mit `type` (Name) und allen
-- Feldern zurueck, oder nil + Fehlermeldung.
function protocol.decode(raw)
    if type(raw) ~= "string" or #raw < 1 then
        return nil, "leere Nachricht"
    end
    local id = string.byte(raw, 1)
    local def = by_id[id]
    if def == nil then
        return nil, "unbekannte Nachrichten-ID " .. id
    end

    local ok, result = pcall(function()
        return table.pack(string.unpack(def.format, raw))
    end)
    if not ok then
        return nil, "beschaedigte Nachricht " .. def.name .. ": " .. tostring(result)
    end

    local msg = { type = def.name }
    for i, field in ipairs(def.fields) do
        msg[field[1]] = result[i + 1]
    end
    return msg
end

return protocol
