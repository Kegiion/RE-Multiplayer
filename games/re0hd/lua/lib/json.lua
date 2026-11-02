-- json.lua - kleiner JSON-Kodierer/-Dekodierer in reinem Lua.
--
-- Die RE0-Runtime laedt diese Datei als globale Tabelle `json`, damit
-- Skripte dieselbe API wie in REFramework haben:
--   json.dump_file(pfad, tabelle) -> bool      (relativ zu remods/data/)
--   json.load_file(pfad)          -> tabelle | nil
--   json.encode(wert [, pretty])  -> string
--   json.decode(text)             -> wert   (wirft Fehler bei kaputtem JSON)

local json = {}

-- null aus JSON wird zu json.null (damit Arrays keine Loecher bekommen)
json.null = setmetatable({}, { __tostring = function() return "null" end })

-- ---- Kodieren ---------------------------------------------------------------

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if math.type(k) ~= "integer" or k < 1 then
            return false
        end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true, n
end

local encode_value

local function encode_table(t, pretty, indent, seen)
    if seen[t] then
        error("json.encode: Tabelle enthaelt sich selbst")
    end
    seen[t] = true
    local nl = pretty and "\n" or ""
    local inner = pretty and (indent .. "  ") or ""
    local sep = pretty and ": " or ":"
    local parts = {}
    local array, n = is_array(t)
    local result
    if array and n > 0 then
        for i = 1, n do
            parts[i] = inner .. encode_value(t[i], pretty, inner, seen)
        end
        result = "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. indent .. "]"
    elseif array then
        result = "[]"
    else
        local keys = {}
        for k in pairs(t) do
            local kt = type(k)
            if kt ~= "string" and kt ~= "number" then
                error("json.encode: Schluessel vom Typ " .. kt .. " nicht erlaubt")
            end
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys) -- feste Reihenfolge => Dateien lassen sich gut vergleichen
        for i, k in ipairs(keys) do
            local v = t[k]
            if v == nil then
                v = t[tonumber(k)]
            end
            parts[i] = inner .. encode_string(k) .. sep .. encode_value(v, pretty, inner, seen)
        end
        result = "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. indent .. "}"
    end
    seen[t] = nil
    return result
end

encode_value = function(v, pretty, indent, seen)
    local t = type(v)
    if v == nil or v == json.null then
        return "null"
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "null" -- NaN/unendlich gibt es in JSON nicht
        end
        if math.type(v) == "integer" then
            return string.format("%d", v)
        end
        return string.format("%.17g", v)
    elseif t == "string" then
        return encode_string(v)
    elseif t == "table" then
        return encode_table(v, pretty, indent, seen)
    end
    return encode_string(tostring(v)) -- Funktionen u. a. als Text
end

function json.encode(value, pretty)
    return encode_value(value, pretty, "", {})
end

-- ---- Dekodieren -------------------------------------------------------------

local function decode_error(text, pos, msg)
    error(string.format("json.decode: %s bei Zeichen %d", msg, pos), 0)
end

local function skip_ws(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local decode_value

local function decode_string(text, pos)
    local parts = {}
    local i = pos + 1
    while true do
        local c = text:sub(i, i)
        if c == "" then
            decode_error(text, pos, "String nicht beendet")
        elseif c == '"' then
            return table.concat(parts), i + 1
        elseif c == "\\" then
            local e = text:sub(i + 1, i + 1)
            local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
            if map[e] then
                parts[#parts + 1] = map[e]
                i = i + 2
            elseif e == "u" then
                local hex = text:sub(i + 2, i + 5)
                local code = tonumber(hex, 16)
                if not code or #hex ~= 4 then
                    decode_error(text, i, "ungueltiges \\u")
                end
                -- Ersatzpaare (Surrogates) fuer Zeichen ausserhalb der BMP
                if code >= 0xD800 and code <= 0xDBFF and text:sub(i + 6, i + 7) == "\\u" then
                    local low = tonumber(text:sub(i + 8, i + 11), 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        i = i + 6
                    end
                end
                parts[#parts + 1] = utf8.char(code)
                i = i + 6
            else
                decode_error(text, i, "ungueltiges Escape")
            end
        else
            local j = text:find('["\\]', i) or #text + 1
            parts[#parts + 1] = text:sub(i, j - 1)
            i = j
        end
    end
end

local function decode_array(text, pos)
    local result = {}
    pos = skip_ws(text, pos + 1)
    if text:sub(pos, pos) == "]" then
        return result, pos + 1
    end
    while true do
        local v
        v, pos = decode_value(text, pos)
        result[#result + 1] = v
        pos = skip_ws(text, pos)
        local c = text:sub(pos, pos)
        if c == "]" then
            return result, pos + 1
        elseif c ~= "," then
            decode_error(text, pos, "',' oder ']' erwartet")
        end
        pos = skip_ws(text, pos + 1)
    end
end

local function decode_object(text, pos)
    local result = {}
    pos = skip_ws(text, pos + 1)
    if text:sub(pos, pos) == "}" then
        return result, pos + 1
    end
    while true do
        if text:sub(pos, pos) ~= '"' then
            decode_error(text, pos, "Schluessel erwartet")
        end
        local key
        key, pos = decode_string(text, pos)
        pos = skip_ws(text, pos)
        if text:sub(pos, pos) ~= ":" then
            decode_error(text, pos, "':' erwartet")
        end
        local v
        v, pos = decode_value(text, skip_ws(text, pos + 1))
        result[key] = v
        pos = skip_ws(text, pos)
        local c = text:sub(pos, pos)
        if c == "}" then
            return result, pos + 1
        elseif c ~= "," then
            decode_error(text, pos, "',' oder '}' erwartet")
        end
        pos = skip_ws(text, pos + 1)
    end
end

decode_value = function(text, pos)
    pos = skip_ws(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then
        return decode_object(text, pos)
    elseif c == "[" then
        return decode_array(text, pos)
    elseif c == '"' then
        return decode_string(text, pos)
    elseif text:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif text:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif text:sub(pos, pos + 3) == "null" then
        return json.null, pos + 4
    end
    local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if num and #num > 0 then
        local v = math.tointeger(tonumber(num)) or tonumber(num)
        if v == nil then
            decode_error(text, pos, "ungueltige Zahl")
        end
        return v, pos + #num
    end
    decode_error(text, pos, "unerwartetes Zeichen '" .. c .. "'")
end

function json.decode(text)
    local value, pos = decode_value(text, 1)
    pos = skip_ws(text, pos)
    if pos <= #text then
        decode_error(text, pos, "Text nach dem Ende")
    end
    return value
end

-- ---- Dateien (wie REFramework: nur relativ, kein "..") -----------------------

local function data_path(path)
    assert(type(path) == "string" and path ~= "", "Pfad fehlt")
    if path:find("%.%.") or path:find("^[/\\]") or path:find(":") then
        error("json: nur relative Pfade ohne '..' erlaubt: " .. path)
    end
    local dir = (remods and remods.data_dir) or ""
    return dir .. path
end

function json.dump_file(path, value)
    local ok, text = pcall(json.encode, value, true)
    if not ok then
        return false, text
    end
    local f, err = io.open(data_path(path), "wb")
    if not f then
        return false, err
    end
    f:write(text, "\n")
    f:close()
    return true
end

function json.load_file(path)
    local f = io.open(data_path(path), "rb")
    if not f then
        return nil
    end
    local text = f:read("a")
    f:close()
    local ok, value = pcall(json.decode, text)
    if not ok then
        if log then
            log.warn("json.load_file(" .. path .. "): " .. tostring(value))
        end
        return nil
    end
    return value
end

return json
