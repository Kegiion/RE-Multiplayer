-- re2r_coop/titlemenu.lua
--
-- Eintrag "Multiplayer" im echten Hauptmenue des Titelbildschirms und ein
-- Untermenue im Stil des Spiels (gleiche Liste, gleiche Schrift, Steuerung mit
-- Tastatur/Controller). Kein imgui-Fenster.
--
-- Bestaetigt am 4. November 2026 (Konsole, RE2 RT-Version):
--   - gui.MenuMainBehavior.initList(DecidedResult) baut DecidedList
--     (List<DecidedResult>, sonst 0,1,2,3,4,6) und die Zeilen des Selectors
--     (via.gui.ScrollList "sl_list") jedes Mal neu auf.
--   - Nach initList die Liste aendern und ItemMax/ItemCount setzen: Die
--     ScrollList legt die Zeilen selbst an. Die Texte gehen dabei
--     durcheinander, deshalb vorher die MessageId jeder Zeile merken und
--     danach wieder setzen. Eigene Zeilen bekommen set_Message(...).
--     Kinder der ScrollList stehen in umgekehrter Reihenfolge.
--   - Hilfetext unten: Panel/c_guide/m_guide (via.gui.Text).
--   - Die Auswahl landet in TitleFlow.<update>b__39_19(DecidedResult).
--     Ueberspringen wir sie, sperrt das Menue seine Eingabe, bleibt aber
--     sichtbar, und der Titelablauf wartet (WAIT_GUI_ANIMATION).
--     TitleFlow.StateValue = 10 (TITLE_MENU_MAIN) oeffnet das Hauptmenue neu
--     (initList laeuft dabei wieder).
--   - Tastatur: via.hid.Keyboard.get_Device() (MergedKeyboardDevice),
--     isTrigger(via.hid.KeyboardKey).
-- UNBESTAETIGT: Zurueck-Taste (CANCEL = 8) im Untermenue, Mausklick auf
-- eigene Zeilen, Umlaute in der Spielschrift.

local game = require("re2r_coop.game")
local tr = require("re2r_coop.text")

local M = {}

M.VALUE = 7               -- MenuMainBehavior.DecidedResult.MAX, im Spiel ungenutzt
M.CANCEL = 8              -- MenuMainBehavior.DecidedResult.CANCEL
M.ROW_BASE = 100          -- eigene Zeilen: 100, 101, ...
M.POSITION = 1            -- Platz von "Multiplayer" (0 = ganz oben), unter "Kampagne"
-- Texte: tm.label und tm.label_help (re2r_coop/lang)
M.STATE_MENU_MAIN = 10    -- TitleFlow.State.TITLE_MENU_MAIN

-- Vom Hauptskript gesetzt:
--   M.rows()            -> Liste { id=, label=, help=, edit=<Feldname oder nil> }
--   M.on_action(id)     Zeile ausgewaehlt
--   M.get_field(name)   aktueller Wert eines Textfelds
--   M.set_field(name, value)
M.rows = function() return {} end
M.on_action = function() end
M.get_field = function() return "" end
M.set_field = function() end

M.installed = false
M.mode = "main"           -- main | mp (unser Untermenue) | edit (Texteingabe)
M.error = nil

local behavior = nil      -- aktuelles MenuMainBehavior
local shown = nil         -- Zeilen, die gerade im Menue stehen
local reopen = false
local edit = nil          -- { field=, buffer=, row= }

-- --- GUI-Hilfen -----------------------------------------------------------

local function children(control)
    local r = {}
    local ch = control:call("get_Child")
    while ch ~= nil do
        r[#r + 1] = ch
        ch = ch:call("get_Next")
    end
    return r
end

local function find_child(control, name)
    for _, ch in ipairs(children(control)) do
        if ch:call("get_Name") == name then
            return ch
        end
    end
    return nil
end

local function text_of(item)
    local panel = find_child(item, "c_list")
    return panel and find_child(panel, "m_list")
end

-- Zeilen in Listenreihenfolge (erste Zeile = oberster Eintrag).
local function list_rows(selector)
    local r = children(selector)
    local n = #r
    for i = 1, n // 2 do
        r[i], r[n - i + 1] = r[n - i + 1], r[i]
    end
    return r
end

-- Hilfetext unten: GUI_GeneralGuide/main/c_guide/m_guide (der c_guide im
-- Hauptmenue selbst ist unsichtbar).
local guide = nil
local function guide_text()
    if guide ~= nil then
        local ok = pcall(guide.call, guide, "get_Name")
        if ok then
            return guide
        end
        guide = nil
    end
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local guis = scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
    for _, c in ipairs(guis and guis:get_elements() or {}) do
        local go = c:call("get_GameObject")
        if go:call("get_Name") == "GUI_GeneralGuide" then
            local main = find_child(c:call("get_View"), "main")
            local panel = main and find_child(main, "c_guide")
            guide = panel and find_child(panel, "m_guide")
            return guide
        end
    end
    return nil
end

-- Eigener Text statt Text-ID des Spiels (die ID hat Vorrang vor set_Message).
local empty_id = nil
local function set_text(t, text)
    if t:call("get_Message") == text then
        return
    end
    if empty_id == nil then
        empty_id = ValueType.new(sdk.find_type_definition("System.Guid"))
    end
    t:call("set_MessageId", empty_id)
    t:call("set_Message", text)
end

-- --- Liste aufbauen ---------------------------------------------------------

-- Hauptmenue: "Multiplayer" einfuegen.
local function patch_main(b)
    local list = b:call("get_DecidedList")
    local selector = b:get_field("Selector")
    local count = list:call("get_Count")
    local values, ids = {}, {}
    local before = list_rows(selector)
    for i = 0, count - 1 do
        local v = list:call("get_Item", i)
        if v == M.VALUE then
            return
        end
        values[#values + 1] = v
        local t = before[i + 1] and text_of(before[i + 1])
        ids[v] = t and t:call("get_MessageId")
    end
    local pos = math.min(M.POSITION, count)
    list:call("Insert", pos, M.VALUE)
    table.insert(values, pos + 1, M.VALUE)
    selector:call("set_ItemMax", count + 1)
    selector:call("set_ItemCount", count + 1)
    for i, row in ipairs(list_rows(selector)) do
        local t = text_of(row)
        local v = values[i]
        if t ~= nil and v ~= nil then
            if v == M.VALUE then
                set_text(t, tr("tm.label"))
            elseif ids[v] ~= nil then
                t:call("set_MessageId", ids[v])
            end
        end
    end
end

local function row_label(row)
    if edit ~= nil and edit.row == row.id then
        return row.label_edit and row.label_edit(edit.buffer) or (edit.buffer .. "_")
    end
    return row.label
end

-- Texte der eigenen Zeilen und den Hilfetext setzen (jeden Frame).
local function refresh(b)
    if shown == nil then
        return
    end
    local selector = b:get_field("Selector")
    for i, item in ipairs(list_rows(selector)) do
        local row = shown[i]
        local t = text_of(item)
        if row ~= nil and t ~= nil then
            set_text(t, row_label(row))
        end
    end
    local g = guide_text()
    if g ~= nil then
        local help
        if edit ~= nil then
            help = edit.problem or tr("tm.edit_help")
        else
            local row = shown[selector:call("get_CursorIndex") + 1]
            help = row and row.help or ""
        end
        set_text(g, help)
    end
end

-- Untermenue: Liste durch unsere Zeilen ersetzen.
local function patch_mp(b)
    local rows = M.rows()
    local list = b:call("get_DecidedList")
    local selector = b:get_field("Selector")
    list:call("Clear")
    for i = 1, #rows do
        list:call("Add", M.ROW_BASE + i - 1)
    end
    selector:call("set_ItemMax", #rows)
    selector:call("set_ItemCount", #rows)
    shown = rows
    local cursor = math.min(M.cursor or 0, #rows - 1)
    pcall(selector.call, selector, "set_CursorIndex", cursor)
    refresh(b)
end

function M.patch(b)
    behavior = b
    if M.mode == "main" then
        shown = nil
        patch_main(b)
    else
        patch_mp(b)
    end
end

local function title_flow()
    local mfm = sdk.get_managed_singleton(game.ns("gamemastering.MainFlowManager"))
    return mfm and mfm:get_field("<Title>k__BackingField")
end

-- Menue neu oeffnen (naechster Frame), z. B. nach einer Auswahl.
function M.reopen()
    reopen = true
end

M.trace = {}              -- letzte Moduswechsel (fuer die Fehlersuche)
local function set_mode(mode, why)
    M.trace[#M.trace + 1] = M.mode .. " -> " .. mode .. " (" .. tostring(why) .. ")"
    if #M.trace > 20 then
        table.remove(M.trace, 1)
    end
    if M.mode == "edit" and mode ~= "edit" and behavior ~= nil then
        pcall(behavior.call, behavior, "set_EnableInput", true)
    end
    M.mode = mode
    if mode ~= "edit" then
        edit = nil
    end
    reopen = true
end

-- Auswahl im Menue. true = Spiel soll sie nicht verarbeiten.
local function on_decide(v)
    if M.mode == "main" then
        if v == M.VALUE then
            M.cursor = 0
            set_mode("mp", "multiplayer")
            return true
        end
        return false
    end
    if v == M.CANCEL then
        M.cursor = nil
        set_mode("main", "cancel")
        return true
    end
    local row = shown and shown[v - M.ROW_BASE + 1]
    if row == nil then
        set_mode("main", "unbekannte Zeile " .. tostring(v))
        return true
    end
    M.cursor = v - M.ROW_BASE
    if row.edit ~= nil then
        -- skip: die Taste, mit der die Zeile bestaetigt wurde, nicht als Eingabe werten
        edit = { field = row.edit, buffer = tostring(M.get_field(row.edit) or ""), row = row.id, skip = 2 }
        -- Nach einer Auswahl blendet das Spiel das Menue aus (4. November 2026).
        -- Darum neu oeffnen und waehrend der Eingabe die Menuetasten sperren.
        M.mode = "edit"
        reopen = true
        return true
    end
    if row.id == "back" then
        set_mode("main", "zurueck")
        return true
    end
    M.on_action(row.id)
    reopen = true
    return true
end

function M.install()
    if M.installed or sdk == nil or sdk.hook == nil then
        return M.installed
    end
    local mm = sdk.find_type_definition(game.ns("gui.MenuMainBehavior"))
    local tf = sdk.find_type_definition(game.ns("gamemastering.TitleFlow"))
    local init_list = mm and mm:get_method("initList")
    local decide = tf and tf:get_method("<update>b__39_19")
    if init_list == nil or decide == nil then
        M.error = "Menue-Methoden nicht gefunden"
        return false
    end
    local current
    sdk.hook(init_list, function(args)
        current = sdk.to_managed_object(args[2])
    end, function(retval)
        if current ~= nil then
            local ok, err = pcall(M.patch, current)
            if not ok then
                M.error = tostring(err)
            end
            current = nil
        end
        return retval
    end)
    sdk.hook(decide, function(args)
        local v = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local ok, skip = pcall(on_decide, v)
        if not ok then
            M.error = tostring(skip)
            return
        end
        if skip then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        return retval
    end)
    M.installed = true
    return true
end

-- --- Texteingabe ------------------------------------------------------------

local KEY_BACK, KEY_RETURN, KEY_ESCAPE, KEY_SHIFT = 8, 13, 27, 16
local KEY_ENTER_NUM = 146
local keyboard = nil

local function key_device()
    if keyboard == nil then
        keyboard = sdk.call_native_func(sdk.get_native_singleton("via.hid.Keyboard"),
            sdk.find_type_definition("via.hid.Keyboard"), "get_Device")
    end
    return keyboard
end

-- Zeichen der in diesem Frame gedrueckten Tasten (Ziffern, Buchstaben, Punkt).
local function typed_chars(dev)
    local s = ""
    local shift = dev:call("isDown", KEY_SHIFT)
    for k = 48, 57 do -- 0-9
        if dev:call("isTrigger", k) then s = s .. string.char(k) end
    end
    for k = 96, 105 do -- Ziffernblock
        if dev:call("isTrigger", k) then s = s .. string.char(k - 48) end
    end
    for k = 65, 90 do -- A-Z
        if dev:call("isTrigger", k) then s = s .. string.char(shift and k or k + 32) end
    end
    if dev:call("isTrigger", 190) or dev:call("isTrigger", 110) then s = s .. "." end
    if dev:call("isTrigger", 189) then s = s .. (shift and "_" or "-") end
    if dev:call("isTrigger", 32) then s = s .. " " end
    return s
end

-- Eingabe-Regeln je Feld. accept(buffer, zeichen) -> neuer Puffer oder nil,
-- valid(buffer) -> true oder Fehlertext.
local function ip_accept(buffer, c)
    if c == "." then
        if buffer == "" or buffer:sub(-1) == "." or select(2, buffer:gsub("%.", "")) >= 3 then
            return nil
        end
        return buffer .. c
    end
    if not c:match("%d") then
        return nil
    end
    local block = buffer:match("(%d*)$") .. c
    if #block > 3 or tonumber(block) > 255 or (#block > 1 and block:sub(1, 1) == "0") then
        return nil
    end
    return buffer .. c
end

function M.ip_valid(s)
    local a, b, c, d = s:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if a == nil then
        return tr("tm.ip_incomplete")
    end
    for _, x in ipairs({ a, b, c, d }) do
        if tonumber(x) > 255 then
            return tr("tm.ip_too_big")
        end
    end
    return true
end

M.fields = {
    address = { accept = ip_accept, valid = M.ip_valid },
    name = {
        accept = function(buffer, c)
            if #buffer >= 16 or not c:match("[%w%-_ ]") or (buffer == "" and c == " ") then
                return nil
            end
            return buffer .. c
        end,
        valid = function(s)
            return s:match("%S") ~= nil or tr("tm.name_missing")
        end,
    },
}

-- Puffer mit den Regeln des Felds um die getippten Zeichen erweitern.
function M.accept_chars(field, buffer, chars)
    local rules = M.fields[field]
    for c in chars:gmatch(".") do
        local nb = rules and rules.accept(buffer, c) or (not rules and buffer .. c) or nil
        if nb ~= nil then
            buffer = nb
        end
    end
    return buffer
end

local function update_edit()
    local dev = key_device()
    if dev == nil then
        return
    end
    if edit.skip > 0 then
        edit.skip = edit.skip - 1
        return
    end
    if dev:call("isTrigger", KEY_ESCAPE) then
        set_mode("mp", "esc")
        return
    end
    if dev:call("isTrigger", KEY_RETURN) or dev:call("isTrigger", KEY_ENTER_NUM) then
        local rules = M.fields[edit.field]
        local ok = rules == nil or rules.valid(edit.buffer)
        if ok ~= true then
            edit.problem = ok
            return
        end
        M.set_field(edit.field, edit.buffer)
        set_mode("mp", "enter")
        return
    end
    if dev:call("isTrigger", KEY_BACK) and #edit.buffer > 0 then
        edit.buffer = edit.buffer:sub(1, -2)
        edit.problem = nil
    end
    local s = typed_chars(dev)
    if s ~= "" then
        edit.buffer = M.accept_chars(edit.field, edit.buffer, s)
        edit.problem = nil
    end
end

-- --- Pro Frame ----------------------------------------------------------------

-- main = MainState (3 = Titel).
function M.update(main)
    if main ~= 3 then
        if M.mode ~= "main" then
            M.mode, edit, shown = "main", nil, nil
        end
        reopen = false
        return
    end
    if M.mode == "edit" and edit ~= nil then
        update_edit()
        if behavior ~= nil and M.mode == "edit" then
            pcall(behavior.call, behavior, "set_EnableInput", false)
        end
    end
    if reopen then
        reopen = false
        local t = title_flow()
        if t ~= nil then
            t:call("set_StateValue", M.STATE_MENU_MAIN)
        end
        return
    end
    -- Hauptmenue: Hilfetext fuer "Multiplayer" (das Spiel kennt den Wert nicht)
    if M.mode == "main" and behavior ~= nil then
        local ok, v = pcall(function()
            local sel = behavior:get_field("Selector")
            return behavior:call("get_DecidedList"):call("get_Item", sel:call("get_CursorIndex"))
        end)
        if ok and v == M.VALUE then
            local g = guide_text()
            if g ~= nil then
                set_text(g, tr("tm.label_help"))
            end
        end
        return
    end
    if M.mode ~= "main" and behavior ~= nil and shown ~= nil then
        -- Hat sich die Zahl der Zeilen geaendert (z. B. verbunden), neu aufbauen.
        local rows = M.rows()
        if #rows ~= #shown then
            reopen = true
            return
        end
        for i, r in ipairs(rows) do
            if shown[i].id ~= r.id then
                reopen = true
                return
            end
        end
        shown = rows
        refresh(behavior)
    end
end

return M
