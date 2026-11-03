-- re2r_coop/savestate.lua
--
-- Spielstand aus dem RAM kopieren und wieder einspielen (Join auf den Stand
-- des Hosts). RE2 haelt den Spielstand beim Laden als Objektgraph in
-- SaveDataManager.GameSaveDataValue.GameSaveDataList (32 Teile, ca. 25.000
-- Objekte). Der Host sammelt seinen Live-Stand ein (capture_live) und macht
-- daraus Lua-Baeume (snapshot), die als Bytes verschickt werden
-- (remultiplayer_coop.serial). Beim Freund werden sie beim Laden auf die frisch
-- eingelesenen Objekte gespielt (apply_to_list).
--
-- Bestaetigt am 3. November 2026: Durchlaufen dauert ca. 0,2 s. Einspielen
-- der ORIGINAL-Objekte eines frueheren Ladevorgangs haengt in
-- LOAD_LEVEL_FOLDER_WAIT, deshalb diese echte Kopie.
-- UNBESTAETIGT: apply_to_list im Spiel (Dictionaries, neue Listen ueber
-- Vorlagen), Uebertragung zwischen zwei PCs.

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

-- Werte einer via.userdata.Variable (Engine-Objekt, keine lesbaren Felder).
-- TypeKind: 1 Enum, 2 Boolean, 3..8 Ganzzahlen, 9/10 64 Bit, 11/12 Kommazahl,
-- 15 String, 16 Trigger (wird nicht uebertragen).
local VAR_ACCESS = {
    [1] = "S32", [2] = "Bool", [3] = "S32", [4] = "U32", [5] = "S32", [6] = "U32", [7] = "S32", [8] = "U32",
    [9] = "U64", [10] = "U64", [11] = "F32", [12] = "F32", [15] = "String",
}
M.VAR_ACCESS = VAR_ACCESS

local function read_var(v)
    local ok, kind = pcall(v.call, v, "get_TypeKind")
    if not ok then
        return nil
    end
    local acc = VAR_ACCESS[kind]
    if acc == nil then
        return { kind = kind }
    end
    local ok2, value = pcall(v.call, v, "get_" .. acc)
    if not ok2 then
        return { kind = kind }
    end
    if type(value) == "userdata" then
        value = tostring(value) -- System.String
    end
    return { kind = kind, value = value }
end

local function is_list(tn)
    return tn:find("^System%.Collections%.Generic%.List`1") ~= nil
end

local function is_dict(tn)
    return tn:find("^System%.Collections%.Generic%.Dictionary`2") ~= nil
end

-- Felder einer generischen Liste (Namen je nach Laufzeit verschieden,
-- in RE2 bestaetigt: mItems/mSize).
local function list_fields(obj)
    for _, names in ipairs({ { "mItems", "mSize", "mVersion" }, { "_items", "_size", "_version" } }) do
        local ok, items = pcall(obj.get_field, obj, names[1])
        if ok and items ~= nil then
            return names[1], names[2], names[3], items
        end
    end
    return nil
end

-- Eintraege eines Dictionary: Liste von { key, value } (rohe Spielwerte).
-- UNBESTAETIGT im Spiel: Feldnamen _entries/_count und key/value/hashCode/next.
local function dict_entries(obj)
    local ok, count = pcall(obj.call, obj, "get_Count")
    if not ok or count == 0 then
        return {}
    end
    local entries
    for _, name in ipairs({ "_entries", "entries", "mEntries" }) do
        local ok2, e = pcall(obj.get_field, obj, name)
        if ok2 and e ~= nil then
            entries = e
            break
        end
    end
    if entries == nil then
        error("Dictionary ohne Eintraege-Feld: " .. obj:get_type_definition():get_full_name())
    end
    local els = entries:get_elements() or {}
    local okc, used = pcall(obj.get_field, obj, "_count")
    used = (okc and used) or #els
    local list = {}
    for i, e in ipairs(els) do
        if i > used then
            break
        end
        local hash = e:get_field("hashCode")
        local nxt = e:get_field("next")
        -- freie Plaetze: hashCode < 0 (aeltere .NET) bzw. next < -1 (neuere)
        if (hash == nil or hash >= 0) and (nxt == nil or nxt >= -1) then
            list[#list + 1] = { e:get_field("key"), e:get_field("value") }
        end
    end
    return list
end

-- Baut einen Baum aus Lua-Tabellen:
--   Objekt:    { t = Typ, id = n, f = { Feld = Wert, ... } }
--   Array:     { t = Typ, id = n, a = { [1..n] = Wert }, n = Laenge }
--   Liste:     { t = Typ, id = n, l = { [1..n] = Wert }, n = Laenge }
--   Dictionary:{ t = Typ, id = n, d = { { Schluessel, Wert }, ... } }
--   Variable:  { t = "via.userdata.Variable", id = n, var = { kind =, value = } }
--   Werttyp:   { t = Typ, vt = true, f = {...} }
--   behalten:  { t = Typ, keep = true } (Engine-Objekte, Delegates: nicht anfassen)
--   Verweis:   { ref = id } (dasselbe Objekt mehrfach)
--   Text:      { t = "System.String", id = n, s = "..." }
--   Vektor:    { v3 = {x,y,z} } / { q = {x,y,z,w} } / ...
--   sonst:     Zahl, bool; nil-Felder fehlen
-- state (optional) teilt die Nummern ueber mehrere Wurzeln (Verweise zwischen
-- den 32 Teilen eines Spielstands).
function M.snapshot(root, stats, state)
    stats = stats or { objects = 0, fields = 0 }
    state = state or { seen = {}, next_id = 0 }
    local seen = state.seen

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
        local elem_tn = tn:sub(-2) == "[]" and tn:sub(1, -3) or tn
        if tn ~= "via.userdata.Variable" and not M.should_clone(elem_tn) then
            return { t = tn, keep = true }
        end
        local addr = obj:get_address()
        local id = seen[addr]
        if id ~= nil then
            return { ref = id }
        end
        state.next_id = state.next_id + 1
        id = state.next_id
        seen[addr] = id
        stats.objects = stats.objects + 1
        if tn == "System.String" then
            return { t = tn, id = id, s = obj:call("ToString") }
        end
        if tn == "via.userdata.Variable" then
            return { t = tn, id = id, var = read_var(obj) }
        end
        if tn:sub(-2) == "[]" then
            local n = { t = tn, id = id, a = {} }
            local els = obj:get_elements() or {}
            n.n = #els
            for i, e in ipairs(els) do
                n.a[i] = value(e, elem_tn, depth + 1)
            end
            return n
        end
        if is_list(tn) then
            local _, _, _, items = list_fields(obj)
            local size = obj:call("get_Count")
            local n = { t = tn, id = id, l = {}, n = size }
            local els = items and items:get_elements() or {}
            for i = 1, size do
                n.l[i] = value(els[i], nil, depth + 1)
            end
            return n
        end
        if is_dict(tn) then
            local n = { t = tn, id = id, d = {} }
            for i, kv in ipairs(dict_entries(obj)) do
                n.d[i] = { value(kv[1], nil, depth + 1), value(kv[2], nil, depth + 1) }
            end
            return n
        end
        local n = { t = tn, id = id, f = {} }
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

-- --- Live-Stand einsammeln (Host) ---------------------------------------------

local function ns(name)
    if sdk.game_namespace then
        return sdk.game_namespace(name)
    end
    return "app.ropeway." .. name
end

-- Liefert alle Spielstand-Teile des laufenden Spiels als Baeume (wie beim
-- Speichern: jeder Manager in SaveDataManager.GameSaveManagerDic gibt mit
-- saveGameSaveData() seinen Teil). Bestaetigt am 3. November 2026: 32 Teile,
-- Strasse ca. 7.000 Objekte in 0,07 s, ohne zu speichern.
function M.capture_live(stats)
    local sdm = sdk.get_managed_singleton(ns("gamemastering.SaveDataManager"))
    if sdm == nil then
        error("SaveDataManager fehlt")
    end
    local dic = sdm:get_field("GameSaveManagerDic")
    local parts = {}
    stats = stats or { objects = 0, fields = 0 }
    local state = { seen = {}, next_id = 0 }
    for _, kv in ipairs(dict_entries(dic)) do
        local manager = kv[2]
        if manager ~= nil then
            local data = manager:call("saveGameSaveData")
            if data ~= nil then
                local part = M.snapshot(data, stats, state)
                -- Das Feld Hash (Schluessel des Managers) traegt das Spiel erst
                -- beim Speichern ein, live steht bei manchen Teilen 0. Beim
                -- Laden werden die Teile danach verteilt; mit 0 hing das Laden
                -- in LOAD_SCENE_FOLDER_WAIT (3. November 2026).
                if part ~= nil and part.f ~= nil and part.f.Hash ~= nil then
                    part.f.Hash = kv[1]
                end
                parts[#parts + 1] = part
            end
        end
    end
    return parts, stats
end

-- --- Einspielen auf frisch geladene Objekte (Freund) --------------------------

local td_cache = {}
local function find_td(name)
    local td = td_cache[name]
    if td == nil then
        td = sdk.find_type_definition(name)
        td_cache[name] = td or false
    end
    return td or nil
end

local function type_name(v)
    if type(v) ~= "userdata" then
        return nil
    end
    local td = td_of(v)
    return td and td:get_full_name()
end

-- Ein Exemplar je Typ aus dem Objektgraphen sammeln (Vorlagen fuer Typen,
-- die sich nicht direkt anlegen lassen, z. B. generische Listen).
function M.collect_templates(root, templates, budget)
    templates = templates or {}
    budget = budget or { left = 200000 }
    local visited = {}
    local function walk(obj, depth)
        if depth > M.MAX_DEPTH or budget.left <= 0 then
            return
        end
        local td = td_of(obj)
        if td == nil or td:is_value_type() then
            return
        end
        local tn = td:get_full_name()
        if tn == "System.String" or not M.should_clone(tn:sub(-2) == "[]" and tn:sub(1, -3) or tn) then
            return
        end
        local addr = obj:get_address()
        if visited[addr] then
            return
        end
        visited[addr] = true
        budget.left = budget.left - 1
        if templates[tn] == nil then
            templates[tn] = obj
        end
        if tn:sub(-2) == "[]" then
            for _, e in ipairs(obj:get_elements() or {}) do
                if type(e) == "userdata" then
                    walk(e, depth + 1)
                end
            end
            return
        end
        for _, fi in ipairs(inst_fields(td)) do
            local ok, v = pcall(fi.field.get_data, fi.field, obj)
            if ok and type(v) == "userdata" then
                walk(v, depth + 1)
            end
        end
    end
    walk(root, 0)
    return templates
end

local function add_ref(v)
    if v ~= nil and v.add_ref then
        return v:add_ref()
    end
    return v
end

-- Neues Objekt vom Typ tn: direkt anlegen, sonst eine Vorlage klonen.
local function new_object(tn, ctx)
    local td = find_td(tn)
    if td ~= nil and not is_list(tn) and not is_dict(tn) then
        local ok, obj = pcall(td.create_instance, td)
        if ok and obj ~= nil then
            return add_ref(obj)
        end
    end
    local tpl = ctx.templates[tn]
    if tpl ~= nil then
        local ok, obj = pcall(tpl.call, tpl, "MemberwiseClone")
        if ok and obj ~= nil then
            obj = add_ref(obj)
            if is_dict(tn) then
                -- ein geklontes Dictionary teilt sonst die Eintraege der Vorlage
                pcall(obj.set_field, obj, "_buckets", nil)
                pcall(obj.set_field, obj, "_entries", nil)
                pcall(obj.set_field, obj, "_count", 0)
                pcall(obj.set_field, obj, "_freeList", -1)
                pcall(obj.set_field, obj, "_freeCount", 0)
            end
            return obj
        end
    end
    return nil
end

local function write_var(v, var)
    if var == nil or var.value == nil then
        return false
    end
    local acc = VAR_ACCESS[var.kind]
    if acc == nil then
        return false
    end
    local value = var.value
    if acc == "String" then
        value = sdk.create_managed_string(value)
    end
    return (pcall(v.call, v, "set_" .. acc, value))
end

local function only_key(t)
    local only
    for k in pairs(t) do
        if only ~= nil then
            return nil
        end
        only = k
    end
    return only
end

-- Baut aus einem Knoten einen Spielwert. existing = der Wert, der an dieser
-- Stelle beim Freund steht (wird weiterverwendet, wenn der Typ passt).
local function build(node, existing, ctx)
    if type(node) ~= "table" then
        return node
    end
    if node.v3 then
        return Vector3f.new(node.v3[1], node.v3[2], node.v3[3])
    elseif node.q then
        return Quaternion.new(node.q[4], node.q[1], node.q[2], node.q[3])
    elseif node.v2 then
        return Vector2f.new(node.v2[1], node.v2[2])
    elseif node.v4 then
        return Vector4f.new(node.v4[1], node.v4[2], node.v4[3], node.v4[4])
    end
    if node.ref ~= nil then
        local v = ctx.map[node.ref]
        if v == nil then
            ctx.stats.missing_refs = ctx.stats.missing_refs + 1
        end
        return v
    end
    if node.keep then
        return existing
    end
    local tn = node.t
    if node.s ~= nil then
        local s = add_ref(sdk.create_managed_string(node.s))
        ctx.map[node.id] = s
        return s
    end
    if node.vt then
        local f = node.f or {}
        -- verpackte Zahl/Enum (z. B. Element eines Int32[]): nur der Wert
        local k = only_key(f)
        if k == "mValue" or k == "value__" or k == "m_value" then
            return f[k]
        end
        local base = existing
        if type_name(base) ~= tn then
            local td = find_td(tn)
            if td == nil then
                ctx.stats.failed = ctx.stats.failed + 1
                return existing
            end
            base = ValueType.new(td)
        end
        for fname, fnode in pairs(f) do
            local ok, cur = pcall(base.get_field, base, fname)
            local nv = build(fnode, ok and cur or nil, ctx)
            pcall(base.set_field, base, fname, nv)
        end
        return base
    end
    if node.var ~= nil then
        if existing ~= nil and write_var(existing, node.var) then
            ctx.stats.vars = ctx.stats.vars + 1
        elseif existing == nil then
            ctx.stats.failed = ctx.stats.failed + 1
        end
        ctx.map[node.id] = existing
        return existing
    end

    local obj = existing
    if type_name(obj) ~= tn then
        obj = nil
    end

    if node.a ~= nil then
        local n = node.n or #node.a
        local els
        if obj ~= nil then
            els = obj:get_elements() or {}
            if #els ~= n then
                obj = nil
            end
        end
        if obj == nil then
            local etd = find_td(tn:sub(1, -3))
            local ok, arr = pcall(sdk.create_managed_array, etd, n)
            if not ok or arr == nil then
                ctx.stats.failed = ctx.stats.failed + 1
                ctx.errors[#ctx.errors + 1] = "Array nicht anlegbar: " .. tn
                return existing
            end
            obj = add_ref(arr)
            els = {}
            ctx.stats.created = ctx.stats.created + 1
        end
        ctx.map[node.id] = obj
        for i = 1, n do
            local nv = build(node.a[i], els[i], ctx)
            if nv ~= nil then
                obj[i - 1] = nv
            end
        end
        ctx.stats.arrays = ctx.stats.arrays + 1
        return obj
    end

    if obj == nil then
        obj = new_object(tn, ctx)
        if obj == nil then
            ctx.stats.failed = ctx.stats.failed + 1
            ctx.errors[#ctx.errors + 1] = "nicht anlegbar: " .. tostring(tn)
            return existing
        end
        ctx.stats.created = ctx.stats.created + 1
    end
    ctx.map[node.id] = obj

    if node.l ~= nil then
        local items_name, size_name, version_name, items = list_fields(obj)
        if items_name == nil then
            ctx.stats.failed = ctx.stats.failed + 1
            return obj
        end
        local n = node.n or #node.l
        local ets = type_name(items)
        local etd = ets and find_td(ets:sub(1, -3))
        local ok, arr = pcall(sdk.create_managed_array, etd, math.max(n, 1))
        if not ok or arr == nil then
            ctx.stats.failed = ctx.stats.failed + 1
            ctx.errors[#ctx.errors + 1] = "Liste nicht anlegbar: " .. tn
            return obj
        end
        arr = add_ref(arr)
        local old = items:get_elements() or {}
        for i = 1, n do
            local nv = build(node.l[i], old[i], ctx)
            if nv ~= nil then
                arr[i - 1] = nv
            end
        end
        obj:set_field(items_name, arr)
        obj:set_field(size_name, n)
        pcall(function() obj:set_field(version_name, (obj:get_field(version_name) or 0) + 1) end)
        ctx.stats.lists = ctx.stats.lists + 1
        return obj
    end

    if node.d ~= nil then
        pcall(obj.call, obj, "Clear")
        for _, kv in ipairs(node.d) do
            local key = build(kv[1], nil, ctx)
            local val = build(kv[2], nil, ctx)
            local ok, err = pcall(obj.call, obj, "set_Item", key, val)
            if not ok then
                ctx.stats.failed = ctx.stats.failed + 1
                if #ctx.errors < 40 then
                    ctx.errors[#ctx.errors + 1] = "Dictionary " .. tn .. ": " .. tostring(err)
                end
            end
        end
        ctx.stats.dicts = ctx.stats.dicts + 1
        return obj
    end

    for fname, fnode in pairs(node.f or {}) do
        local ok, cur = pcall(obj.get_field, obj, fname)
        cur = ok and cur or nil
        local nv = build(fnode, cur, ctx)
        if type(nv) == "userdata" or nv ~= cur then
            local ok2, err = pcall(obj.set_field, obj, fname, nv)
            if not ok2 then
                ctx.stats.failed = ctx.stats.failed + 1
                if #ctx.errors < 40 then
                    ctx.errors[#ctx.errors + 1] = tostring(tn) .. "." .. fname .. ": " .. tostring(err)
                end
            end
        end
    end
    ctx.stats.objects = ctx.stats.objects + 1
    return obj
end

function M.new_ctx()
    return {
        map = {}, templates = {}, errors = {},
        stats = { objects = 0, arrays = 0, lists = 0, dicts = 0, vars = 0, created = 0, failed = 0, missing_refs = 0, parts = 0 },
    }
end
M.build = build

-- Spielt die Teile (aus capture_live) in die beim Laden frisch eingelesene
-- GameSaveDataList ein. Zuordnung ueber den Typnamen des Teils.
-- Gibt ctx (stats, errors) zurueck.
function M.apply_to_list(list, parts)
    local ctx = M.new_ctx()
    local count = list:call("get_Count")
    local current = {}
    for i = 0, count - 1 do
        local item = list:call("get_Item", i)
        current[i] = item
        if item ~= nil then
            M.collect_templates(item, ctx.templates)
        end
    end
    local by_type = {}
    for _, p in ipairs(parts) do
        if p.t ~= nil then
            by_type[p.t] = p
        end
    end
    for i = 0, count - 1 do
        local item = current[i]
        local tn = type_name(item)
        local part = tn and by_type[tn]
        if part ~= nil then
            local nv = build(part, item, ctx)
            if nv ~= nil and nv ~= item then
                list:call("set_Item", i, nv)
            end
            ctx.stats.parts = ctx.stats.parts + 1
            by_type[tn] = nil
        end
    end
    for tn in pairs(by_type) do
        ctx.errors[#ctx.errors + 1] = "Teil ohne Gegenstueck: " .. tn
    end
    return ctx
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
