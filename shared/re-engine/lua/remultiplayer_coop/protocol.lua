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
protocol.VERSION = 1

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
