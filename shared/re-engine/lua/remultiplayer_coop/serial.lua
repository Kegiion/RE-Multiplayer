-- remultiplayer_coop/serial.lua
--
-- Lua-Werte (Tabellen, Zeichenketten, Zahlen, bool) als Bytes und zurueck.
-- Fuer grosse Datenbaeume (z. B. Spielstaende): Zeichenketten werden in einer
-- Tabelle gesammelt und nur einmal gespeichert, Zahlen je nach Groesse kompakt.
-- Spielunabhaengig, ohne Spielzugriff (getestet in tests/lua/serial_test.lua).
--
-- Format: "RMS1", Anzahl Zeichenketten, Zeichenketten (Laenge + Bytes), dann
-- der Wert. Werte beginnen mit einem Kennbyte (siehe T_*). Zaehler, Nummern
-- und ganze Zahlen sind Varints (7 Bit je Byte, ganze Zahlen per ZigZag).

local M = {}

local MAGIC = "RMS1"

local T_NIL, T_FALSE, T_TRUE = 0, 1, 2
local T_INT, T_DOUBLE = 3, 4
local T_STR, T_TABLE = 5, 6

local pack, unpack = string.pack, string.unpack
local char, byte = string.char, string.byte

-- Vorzeichenlose 64-Bit-Zahl als Varint (Vergleich vorzeichenlos, >> ist logisch).
local function varint(n)
    if not math.ult(0x7F, n) then
        return char(n)
    end
    local b = {}
    while math.ult(0x7F, n) do
        b[#b + 1] = char((n & 0x7F) | 0x80)
        n = n >> 7
    end
    b[#b + 1] = char(n)
    return table.concat(b)
end

local function read_varint(data, pos)
    local n, shift = 0, 0
    while true do
        local c = byte(data, pos)
        if c == nil then
            error("Varint abgeschnitten")
        end
        pos = pos + 1
        n = n | ((c & 0x7F) << shift)
        if c < 0x80 then
            return n, pos
        end
        shift = shift + 7
        if shift > 63 then
            error("Varint zu lang")
        end
    end
end

-- ZigZag: kleine negative Zahlen bleiben klein.
local function zigzag(v)
    return (v << 1) ~ -(v >> 63) -- >> ist logisch: -(v >> 63) ist 0 oder -1
end

local function unzigzag(n)
    return (n >> 1) ~ -(n & 1)
end

function M.encode(value)
    local strings, string_index = {}, {}
    local out = {}

    local function str_id(s)
        local id = string_index[s]
        if id == nil then
            strings[#strings + 1] = s
            id = #strings
            string_index[s] = id
        end
        return id
    end

    local write -- forward
    write = function(v, depth)
        if depth > 200 then
            error("serial.encode: zu tief verschachtelt")
        end
        local k = type(v)
        if v == nil then
            out[#out + 1] = pack("B", T_NIL)
        elseif v == false then
            out[#out + 1] = pack("B", T_FALSE)
        elseif v == true then
            out[#out + 1] = pack("B", T_TRUE)
        elseif k == "number" then
            if math.type(v) == "integer" then
                out[#out + 1] = char(T_INT) .. varint(zigzag(v))
            else
                out[#out + 1] = pack("<Bd", T_DOUBLE, v)
            end
        elseif k == "string" then
            out[#out + 1] = char(T_STR) .. varint(str_id(v))
        elseif k == "table" then
            -- Listenteil 1..n, dann die uebrigen Schluessel
            local n = #v
            local rest = {}
            for key in pairs(v) do
                if not (math.type(key) == "integer" and key >= 1 and key <= n) then
                    rest[#rest + 1] = key
                end
            end
            out[#out + 1] = char(T_TABLE) .. varint(n) .. varint(#rest)
            for i = 1, n do
                write(v[i], depth + 1)
            end
            for _, key in ipairs(rest) do
                write(key, depth + 1)
                write(v[key], depth + 1)
            end
        else
            error("serial.encode: Typ nicht unterstuetzt: " .. k)
        end
    end

    write(value, 0)
    local body = table.concat(out)
    local head = { MAGIC, varint(#strings) }
    for _, s in ipairs(strings) do
        head[#head + 1] = varint(#s) .. s
    end
    return table.concat(head) .. body
end

-- Gibt den Wert zurueck oder nil + Fehlermeldung.
function M.decode(data)
    if type(data) ~= "string" or data:sub(1, 4) ~= MAGIC then
        return nil, "kein serial-Format"
    end
    local ok, result = pcall(function()
        local pos = 5
        local count
        count, pos = read_varint(data, pos)
        local strings = {}
        for i = 1, count do
            local len
            len, pos = read_varint(data, pos)
            if pos + len - 1 > #data then
                error("Zeichenkette abgeschnitten")
            end
            strings[i] = data:sub(pos, pos + len - 1)
            pos = pos + len
        end

        local read -- forward
        read = function()
            local tag
            tag, pos = unpack("B", data, pos)
            if tag == T_NIL then
                return nil
            elseif tag == T_FALSE then
                return false
            elseif tag == T_TRUE then
                return true
            elseif tag == T_INT then
                local n
                n, pos = read_varint(data, pos)
                return unzigzag(n)
            elseif tag == T_DOUBLE then
                local v
                v, pos = unpack("<d", data, pos)
                return v
            elseif tag == T_STR then
                local id
                id, pos = read_varint(data, pos)
                local s = strings[id]
                if s == nil then
                    error("Zeichenkette " .. id .. " fehlt")
                end
                return s
            elseif tag == T_TABLE then
                local n, nrest
                n, pos = read_varint(data, pos)
                nrest, pos = read_varint(data, pos)
                local t = {}
                for i = 1, n do
                    t[i] = read()
                end
                for _ = 1, nrest do
                    local key = read()
                    t[key] = read()
                end
                return t
            end
            error("unbekanntes Kennbyte " .. tostring(tag))
        end

        local value = read()
        if pos ~= #data + 1 then
            error("Daten nach dem Ende")
        end
        return value
    end)
    if not ok then
        return nil, "beschaedigte Daten: " .. tostring(result)
    end
    return result
end

return M
