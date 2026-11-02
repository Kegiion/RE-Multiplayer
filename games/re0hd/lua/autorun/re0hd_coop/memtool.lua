-- re0hd_coop/memtool.lua - Speicher-Werkzeug fuer die Forschung.
--
-- Adressen aus Cheat Engine im Spiel pruefen, ohne Cheat Engine offen zu
-- haben. Ausdruecke (Zahlen immer hexadezimal, wie in Cheat Engine):
--   "1A2B3C4D"                    feste Adresse
--   "re0hd.exe+1A2B"              Modul + Offset
--   "re0hd.exe+1A2B, 10, 4"       Zeiger-Kette: [[re0hd.exe+1A2B]+10]+4
--                                 (entspricht einem Cheat-Engine-Pointer mit Offsets 10 und 4)

local M = {}

M.TYPES = { "u32", "i32", "f32", "u16", "u8", "ptr", "string" }

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_hex(s)
    s = trim(s):gsub("^0[xX]", "")
    if not s:match("^%x+$") then
        return nil
    end
    return tonumber(s, 16)
end

-- Ausdruck -> Adresse | nil, fehler
function M.resolve(expr)
    if type(expr) ~= "string" or trim(expr) == "" then
        return nil, "keine Adresse"
    end
    local parts = {}
    for part in (expr .. ","):gmatch("([^,]*),") do
        parts[#parts + 1] = trim(part)
    end

    local addr
    local module_name, offset = parts[1]:match("^(.-)%s*%+%s*(.+)$")
    if module_name then
        local base = mem.module(module_name)
        if not base then
            return nil, "Modul '" .. module_name .. "' nicht geladen"
        end
        local off = parse_hex(offset)
        if not off then
            return nil, "ungueltiger Offset '" .. offset .. "'"
        end
        addr = base + off
    else
        addr = parse_hex(parts[1])
        if not addr then
            return nil, "ungueltige Adresse '" .. parts[1] .. "'"
        end
    end

    for i = 2, #parts do
        local off = parse_hex(parts[i])
        if not off then
            return nil, "ungueltiger Offset '" .. parts[i] .. "'"
        end
        local p = mem.read_ptr(addr)
        if not p or p == 0 then
            return nil, string.format("Zeiger bei Stufe %d ungueltig (0x%08X)", i - 1, addr)
        end
        addr = p + off
    end
    return addr
end

local READERS = {
    u8 = "read_u8", u16 = "read_u16", u32 = "read_u32", i32 = "read_i32",
    f32 = "read_f32", ptr = "read_ptr", string = "read_string",
}

-- Wert lesen -> roher Wert | nil, fehler
function M.read(expr, value_type)
    local addr, err = M.resolve(expr)
    if not addr then
        return nil, err
    end
    local reader = mem[READERS[value_type] or "read_u32"]
    local v = reader(addr)
    if v == nil then
        return nil, string.format("0x%08X nicht lesbar", addr)
    end
    return v, nil, addr
end

-- Lesbare Darstellung
function M.format(v, value_type)
    if v == nil then
        return "?"
    elseif value_type == "f32" then
        return string.format("%.4f", v)
    elseif value_type == "ptr" then
        return string.format("0x%08X", v)
    elseif value_type == "string" then
        return string.format("%q", v)
    end
    return string.format("%d (0x%X)", v, v & 0xFFFFFFFF)
end

-- Ein Eintrag als Text: "Name: Ausdruck -> 0xADRESSE = Wert"
function M.describe(watch)
    local v, err, addr = M.read(watch.expr, watch.type)
    if v == nil then
        return string.format("%s [%s]: %s", watch.name, watch.type, err)
    end
    return string.format("%s [%s]: 0x%08X = %s", watch.name, watch.type, addr, M.format(v, watch.type))
end

-- Werte aller Eintraege fuer die Diagnose-Datei
function M.snapshot(watches)
    local result = {}
    for _, w in ipairs(watches) do
        local v, err, addr = M.read(w.expr, w.type)
        result[#result + 1] = {
            name = w.name, expr = w.expr, type = w.type,
            address = addr and string.format("0x%08X", addr) or nil,
            value = v, error = err,
        }
    end
    return result
end

return M
