-- re0hd_coop/explorer.lua - Oberflaeche fuer den MT-Explorer (Forschung).
--
-- Ablauf im Spiel:
--   1. "Speicher durchsuchen" (laeuft ueber einige Sekunden verteilt, das Spiel bleibt fluessig)
--   2. Klasse suchen, z. B. "uPlayer", und ein Objekt anklicken
--   3. Objekt-Ansicht: Werte live, geaenderte Werte gelb, Zeigern folgen mit ">"
--   4. "Schnappschuss speichern" mit kurzer Beschreibung, was gerade passiert
--      (z. B. "rebecca_steht", "rebecca_laeuft_vor"). Die Dateien landen in
--      remods/data/ und werden dort ausgewertet.

local M = {}

local QUICK = { "uPlayerRebecca", "uPlayerBilly", "sPlayer", "sGameArea", "sFlagManager", "sItem", "sUnit" }
local VIEW_SIZE = 0x300   -- angezeigte Bytes pro Objekt
local CHANGE_HIGHLIGHT = 1.0 -- Sekunden
local SCAN_BUDGET_MS = 8      -- Rechenzeit pro Frame fuer die Speichersuche

local state = {
    scan_result = nil,
    filter = "uPlayer",
    show_empty = false,
    selected_class = nil,
    stack = {},       -- Navigation: { {addr=, name=}, ... }, oberstes = angezeigtes Objekt
    prev = {},        -- [offset] = letzter Wert
    changed_at = {},  -- [offset] = Zeitpunkt der letzten Aenderung
    snap_label = "",
    message = nil,
}

local function now()
    return coopnet and coopnet.time() or os.clock()
end

local function hex(v)
    return string.format("0x%08X", v & 0xFFFFFFFF)
end

local function current()
    return state.stack[#state.stack]
end

local function open_object(addr, name)
    table.insert(state.stack, { addr = addr, name = name or mt.class_of(addr) or "?" })
    state.prev, state.changed_at = {}, {}
end

local function is_plausible_float(f)
    if f == nil or f ~= f then return false end
    local a = math.abs(f)
    return a == 0 or (a > 1e-4 and a < 1e6)
end

-- Ein Objekt als Tabelle fuer die Diagnose-Datei
local function dump_object(addr, size)
    local words, floats = {}, {}
    for off = 0, size - 4, 4 do
        local v = mem.read_u32(addr + off)
        words[#words + 1] = v and hex(v) or "??"
        local f = mem.read_f32(addr + off)
        floats[#floats + 1] = is_plausible_float(f) and f or json.null
    end
    return { addr = hex(addr), class = mt.class_of(addr), size = size, words = words, floats = floats }
end

local function save_file(name, data)
    local ok, err = json.dump_file(name, data)
    state.message = ok and ("Gespeichert: remods/data/" .. name) or ("Fehler: " .. tostring(err))
end

local function safe_label(text)
    local label = text:gsub("[^%w_%-]", "_")
    return label ~= "" and label or "ohne_name"
end

-- Laufende Speichersuche Stueck fuer Stueck weiterfuehren (auch bei geschlossenem Menue)
re.on_frame(function()
    if state.scan_result and state.scan_result.active then
        state.scan_result = mt.scan_step(SCAN_BUDGET_MS)
    end
end)

-- ---- Teile der Oberflaeche ------------------------------------------------

local function draw_scan()
    local r = state.scan_result
    if r and r.active then
        imgui.text(string.format("Suche laeuft: %d %%  (%.0f MB, %d Objekte bisher)",
            math.floor(r.progress * 100), r.scanned_mb, r.instances))
    elseif imgui.button("Speicher durchsuchen") then
        state.scan_result = mt.scan()
    end
    imgui.same_line()
    if imgui.button("Klassenliste speichern") then
        save_file("re0hd_classes.json", {
            time = os.date("%Y-%m-%d %H:%M:%S"),
            exe_timestamp = hex(remods.exe_timestamp),
            info = mt.info(),
            scan = state.scan_result,
            classes = mt.classes(""),
        })
    end
    if r and r.finished then
        imgui.text(string.format("%d Klassen (DTI), %d Objekte in %d Klassen, %.0f MB in %.0f ms (%.0f MB uebersprungen)",
            r.dti, r.instances, r.classes_with_instances, r.scanned_mb, r.ms, r.skipped_mb))
    elseif not r then
        imgui.text("Noch nicht durchsucht.")
    end
end

local function draw_class_list()
    local changed
    changed, state.filter = imgui.input_text("Klasse suchen", state.filter)
    changed, state.show_empty = imgui.checkbox("Auch Klassen ohne Objekte", state.show_empty)

    imgui.text("Schnellwahl:")
    for _, name in ipairs(QUICK) do
        imgui.same_line()
        if imgui.button(name) then
            state.filter = name
            state.selected_class = name
        end
    end

    if state.filter == "" then
        return
    end
    local shown = 0
    for _, c in ipairs(mt.classes(state.filter)) do
        if state.show_empty or c.count > 0 then
            shown = shown + 1
            if shown > 40 then
                imgui.text("... weitere Treffer, Suche genauer eingrenzen")
                break
            end
            if imgui.button(string.format("%s  (%d)##cls", c.name, c.count)) then
                state.selected_class = c.name
            end
        end
    end
end

local function draw_instances()
    local name = state.selected_class
    if not name then
        return
    end
    local list = mt.instances(name)
    imgui.text(string.format("Objekte von %s: %d", name, #list))
    local raw = mt.dti_raw(name)
    if raw then
        imgui.text(string.format("  DTI %s, Elternklasse: %s", hex(raw.addr), tostring(raw.parent)))
    end
    for i, addr in ipairs(list) do
        if i > 20 then
            imgui.text("  ...")
            break
        end
        if imgui.button(hex(addr) .. "##inst" .. i) then
            state.stack = {}
            open_object(addr, name)
        end
        if i % 4 ~= 0 then imgui.same_line() end
    end
    if #list > 0 then imgui.text("") end
end

local function draw_object()
    local obj = current()
    if not obj then
        return
    end
    imgui.separator()
    imgui.text(string.format("Objekt %s  (%s)", hex(obj.addr), obj.name))
    if #state.stack > 1 then
        imgui.same_line()
        if imgui.button("< Zurueck") then
            table.remove(state.stack)
            state.prev, state.changed_at = {}, {}
            return
        end
    end
    imgui.same_line()
    if imgui.button("Adresse kopieren") then
        imgui.set_clipboard(string.format("%08X", obj.addr))
    end

    local changed
    changed, state.snap_label = imgui.input_text("Was passiert gerade?", state.snap_label)
    if imgui.button("Schnappschuss speichern") then
        local label = safe_label(state.snap_label)
        local data = dump_object(obj.addr, VIEW_SIZE)
        data.label = state.snap_label
        data.time = os.date("%Y-%m-%d %H:%M:%S")
        data.path = {}
        for _, s in ipairs(state.stack) do
            data.path[#data.path + 1] = { addr = hex(s.addr), class = s.name }
        end
        save_file("re0hd_snap_" .. label .. ".json", data)
    end
    if state.message then
        imgui.text(state.message)
    end

    local t = now()
    local follow = nil
    imgui.begin_child("##object_view", 0, 420)
    for off = 0, VIEW_SIZE - 4, 4 do
        local v = mem.read_u32(obj.addr + off)
        if v == nil then
            imgui.text_colored(string.format("+%03X  nicht lesbar", off), 0xFF4040FF)
            break
        end
        if state.prev[off] ~= nil and state.prev[off] ~= v then
            state.changed_at[off] = t
        end
        state.prev[off] = v

        local f = mem.read_f32(obj.addr + off)
        local line = string.format("+%03X  %s", off, hex(v))
        if is_plausible_float(f) and v ~= 0 then
            line = line .. string.format("  f=%.4f", f)
        elseif v ~= 0 and v < 0x10000 then
            line = line .. string.format("  i=%d", v)
        end
        local target = (v >= 0x10000) and mt.class_of(v) or nil
        if target then
            line = line .. "  -> " .. target
        end

        local recent = state.changed_at[off] and (t - state.changed_at[off] < CHANGE_HIGHLIGHT)
        if recent then
            imgui.text_colored(line, 0xFF40E0FF) -- gelb (ABGR)
        else
            imgui.text(line)
        end
        if target then
            imgui.same_line()
            if imgui.button(">##follow" .. off) then
                follow = { addr = v, name = target }
            end
        end
    end
    imgui.end_child()
    if follow then
        open_object(follow.addr, follow.name)
    end
end

function M.draw()
    draw_scan()
    imgui.separator()
    draw_class_list()
    draw_instances()
    draw_object()
end

return M
