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
--   B = uint8, I2 = uint16, I4 = uint32, f = float32, s1 = String bis 255 Bytes

local protocol = {}

-- Muss bei beiden Spielern gleich sein, sonst wird die Verbindung abgelehnt.
protocol.VERSION = 2 -- 2: ANIM_BANKS und ANIM_STATE

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
        },
    },
    -- Laufende Animationen der Ebenen 0..3, ca. 20x pro Sekunde (unreliable).
    -- motion = 0xFFFFFFFF heisst: Ebene leer. interp/imode/icurve beschreiben
    -- die Ueberblendung beim Wechsel (Dauer in Bildern, Art, Kurve).
    -- var1..var12 und bits: Steuer-Variablen der Animation (spielabhaengig,
    -- Bedeutung legt das Spielskript fest).
    ANIM_STATE = {
        id = 5,
        fields = {
            { "seq", "I4" },
            { "banks_id", "I2" },
            { "bank0", "I2" }, { "motion0", "I4" }, { "frame0", "f" },
            { "interp0", "f" }, { "imode0", "B" }, { "icurve0", "B" },
            { "bank1", "I2" }, { "motion1", "I4" }, { "frame1", "f" },
            { "interp1", "f" }, { "imode1", "B" }, { "icurve1", "B" },
            { "bank2", "I2" }, { "motion2", "I4" }, { "frame2", "f" },
            { "interp2", "f" }, { "imode2", "B" }, { "icurve2", "B" },
            { "bank3", "I2" }, { "motion3", "I4" }, { "frame3", "f" },
            { "interp3", "f" }, { "imode3", "B" }, { "icurve3", "B" },
            { "bits", "I4" },
            { "var1", "f" }, { "var2", "f" }, { "var3", "f" }, { "var4", "f" },
            { "var5", "f" }, { "var6", "f" }, { "var7", "f" }, { "var8", "f" },
            { "var9", "f" }, { "var10", "f" }, { "var11", "f" }, { "var12", "f" },
        },
    },
}

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
            if #value > 255 then
                value = value:sub(1, 255)
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
