-- re2r_coop/savestate.lua
--
-- Spielstand aus dem RAM kopieren und wieder einspielen (Join auf den Stand
-- des Hosts). RE2 haelt den Spielstand beim Laden als Objektgraph in
-- SaveDataManager.GameSaveDataValue.GameSaveDataList (32 Teile, ca. 25.000
-- Objekte). Wir kopieren ihn per Reflection in eine Lua-Tabelle
-- (snapshot), erzeugen daraus wieder Spielobjekte (restore) und koennen ihn
-- als Bytes verschicken (encode/decode).
--
-- Bestaetigt am 3. November 2026: Durchlaufen dauert ca. 0,2 s. Einspielen
-- der ORIGINAL-Objekte eines frueheren Ladevorgangs haengt in
-- LOAD_LEVEL_FOLDER_WAIT, deshalb diese echte Kopie.
-- UNBESTAETIGT: restore (Objekte/Arrays/Werttypen anlegen), ob die Kopie
-- sauber laedt.

local M = {}

M.MAX_DEPTH = 40

local field_cache = {}

-- Instanzfelder eines Typs inklusive Basisklassen.
local function inst_fields(td)
    local key = td:get_full_name()
    local c = field_cache[key]
    if c then
        return c
    end
    c = {}
    local t = td
    while t ~= nil do
        local tn = t:get_full_name()
        if tn == "System.Object" or tn == "System.ValueType" then
            break
        end
        for _, f in ipairs(t:get_fields()) do
            if not f:is_static() then
                c[#c + 1] = { name = f:get_name(), field = f, type = f:get_type():get_full_name() }
            end
        end
        t = t:get_parent_type()
    end
    field_cache[key] = c
    return c
end
M.inst_fields = inst_fields

local function td_of(v)
    if type(v) ~= "userdata" or v.get_type_definition == nil then
        return nil
    end
    local ok, td = pcall(v.get_type_definition, v)
    if ok then
        return td
    end
end

-- glm-Vektoren aus REFramework (via.vec2/vec3/vec4/Quaternion) haben x/y/z/w.
local function vec_node(v, tn)
    if tn == "via.Quaternion" then
        return { q = { v.x, v.y, v.z, v.w } }
    elseif tn == "via.vec2" then
        return { v2 = { v.x, v.y } }
    elseif tn == "via.vec4" or tn == "via.Float4" then
        return { v4 = { v.x, v.y, v.z, v.w } }
    end
    return { v3 = { v.x, v.y, v.z } }
end

-- --- Schnappschuss ----------------------------------------------------------

-- Baut einen Baum aus Lua-Tabellen:
--   Objekt:   { t = Typ, id = n, f = { Feld = Wert, ... } }
--   Array:    { t = Typ, id = n, a = { [1..n] = Wert }, n = Laenge }
--   Werttyp:  { t = Typ, vt = true, f = {...} }
--   Verweis:  { ref = id } (dasselbe Objekt mehrfach)
--   Vektor:   { v3 = {x,y,z} } / { q = {x,y,z,w} } / ...
--   sonst:    Zahl, bool, string; nil-Felder fehlen
function M.snapshot(root, stats)
    stats = stats or { objects = 0, fields = 0 }
    local seen, next_id = {}, 0

    local value -- forward

    local function node(obj, depth)
        if depth > M.MAX_DEPTH then
            error("zu tief verschachtelt")
        end
        local td = td_of(obj)
        if td == nil then
            return nil
        end
        local tn = td:get_full_name()
        if td:is_value_type() then
            local n = { t = tn, vt = true, f = {} }
            for _, fi in ipairs(inst_fields(td)) do
                local ok, v = pcall(fi.field.get_data, fi.field, obj)
                if ok then
                    n.f[fi.name] = value(v, fi.type, depth + 1)
                end
            end
            return n
        end
        local addr = obj:get_address()
        local id = seen[addr]
        if id ~= nil then
            return { ref = id }
        end
        next_id = next_id + 1
        seen[addr] = next_id
        stats.objects = stats.objects + 1
        if tn == "System.String" then
            return { t = tn, id = next_id, s = obj:call("ToString") }
        end
        if tn:sub(-2) == "[]" then
            local n = { t = tn, id = next_id, a = {} }
            local els = obj:get_elements() or {}
            n.n = #els
            local et = tn:sub(1, -3)
            for i, e in ipairs(els) do
                n.a[i] = value(e, et, depth + 1)
            end
            return n
        end
        local n = { t = tn, id = next_id, f = {} }
        for _, fi in ipairs(inst_fields(td)) do
            stats.fields = stats.fields + 1
            local ok, v = pcall(fi.field.get_data, fi.field, obj)
            if ok then
                n.f[fi.name] = value(v, fi.type, depth + 1)
            end
        end
        return n
    end

    value = function(v, declared, depth)
        local k = type(v)
        if k == "number" or k == "boolean" or k == "string" or k == "nil" then
            return v
        end
        if k == "userdata" then
            if td_of(v) ~= nil then
                return node(v, depth)
            end
            if v.x ~= nil then
                return vec_node(v, declared)
            end
        end
        return nil
    end

    local tree = node(root, 0)
    return tree, stats
end

-- --- Tiefe Kopie im Spiel ------------------------------------------------------

-- Kopiert einen Objektgraphen mit MemberwiseClone (Objekte) bzw. Clone
-- (Arrays) und biegt alle Verweise auf die Kopien um. Neue Objekte direkt
-- anzulegen geht in REFramework fuer generische Listen und Arrays von
-- Spieltypen nicht (create_instance liefert nil, Array.CreateInstance wirft),
-- Klonen schon (bestaetigt 3. November 2026).
-- Zeichenketten sind unveraenderlich und werden geteilt.
-- Welche Objekte geklont werden. Engine-Objekte (via.*) koennen native
-- Ressourcen besitzen: Ein Klon davon liess RE2 abstuerzen ("Fatal D3D
-- error 25", 3. November 2026). Sie werden deshalb geteilt, ebenso
-- Delegates und Typobjekte.
function M.should_clone(tn)
    if tn:sub(1, 4) == "via." then
        return false
    end
    if tn:find("^System%.Action") or tn:find("^System%.Func") or tn:find("Delegate")
        or tn == "System.RuntimeType" or tn == "System.Type" then
        return false
    end
    return true
end

function M.deep_clone(root, stats)
    stats = stats or { objects = 0, arrays = 0, structs = 0, shared = 0 }
    stats.shared = stats.shared or 0
    local done = {}

    local clone -- forward

    -- Werttyp (REValueType-Kopie): Verweisfelder darin umbiegen. Gibt true
    -- zurueck, wenn etwas geaendert wurde.
    local function patch_struct(vt, depth)
        local td = td_of(vt)
        if td == nil then
            return false
        end
        local changed = false
        for _, fi in ipairs(inst_fields(td)) do
            local ok, v = pcall(fi.field.get_data, fi.field, vt)
            if ok and type(v) == "userdata" then
                local vtd = td_of(v)
                if vtd ~= nil then
                    if vtd:is_value_type() then
                        if patch_struct(v, depth + 1) then
                            vt:set_field(fi.name, v)
                            changed = true
                        end
                    elseif vtd:get_full_name() ~= "System.String" then
                        vt:set_field(fi.name, clone(v, depth + 1))
                        changed = true
                    end
                end
            end
        end
        return changed
    end

    clone = function(obj, depth)
        if depth > M.MAX_DEPTH then
            error("zu tief verschachtelt")
        end
        local td = td_of(obj)
        local tn = td:get_full_name()
        if tn == "System.String" then
            return obj
        end
        local elem_tn = tn:sub(-2) == "[]" and tn:sub(1, -3) or tn
        if not M.should_clone(elem_tn) then
            stats.shared = stats.shared + 1
            return obj
        end
        local addr = obj:get_address()
        local c = done[addr]
        if c ~= nil then
            return c
        end

        if tn:sub(-2) == "[]" then
            c = obj:call("Clone")
            if c == nil then
                error("Clone fehlgeschlagen: " .. tn)
            end
            c = c:add_ref()
            done[addr] = c
            stats.arrays = stats.arrays + 1
            local els = obj:get_elements() or {}
            for i, e in ipairs(els) do
                local etd = td_of(e)
                if etd ~= nil then
                    local etn = etd:get_full_name()
                    if etd:is_value_type() then
                        -- Struct-Element: nur anfassen, wenn es Verweise enthaelt
                        if patch_struct(e, depth + 1) then
                            c[i - 1] = e
                            stats.structs = stats.structs + 1
                        end
                    elseif etn ~= "System.String" then
                        c[i - 1] = clone(e, depth + 1)
                    end
                end
            end
            return c
        end

        c = obj:call("MemberwiseClone")
        if c == nil then
            error("MemberwiseClone fehlgeschlagen: " .. tn)
        end
        c = c:add_ref()
        done[addr] = c
        stats.objects = stats.objects + 1
        for _, fi in ipairs(inst_fields(td)) do
            local ok, v = pcall(fi.field.get_data, fi.field, obj)
            if ok and type(v) == "userdata" then
                local vtd = td_of(v)
                if vtd ~= nil then
                    if vtd:is_value_type() then
                        if patch_struct(v, depth + 1) then
                            c:set_field(fi.name, v)
                            stats.structs = stats.structs + 1
                        end
                    elseif vtd:get_full_name() ~= "System.String" then
                        c:set_field(fi.name, clone(v, depth + 1))
                    end
                end
            end
        end
        return c
    end

    return clone(root, 0), stats
end

return M
