-- Testet die Host-Seite des Joins mit dem echten Hauptskript:
-- 1. Der Freund fragt, waehrend der Host noch im Titelbildschirm ist -> Absage
-- 2. Der Host kommt im Spiel an -> der Spielstand geht von selbst raus (ohne neue Anfrage)
-- 3. Neues Spiel (Spielzeit unter der des Platzes) -> Absage mit Hinweis auf die Schreibmaschine
local RE0 = assert(os.getenv("REMULTIPLAYER_RE0HD_LUA"), "Umgebungsvariable REMULTIPLAYER_RE0HD_LUA fehlt")
package.path = RE0 .. "/lib/?.lua;" .. RE0 .. "/autorun/?.lua;" .. package.path

remultiplayer = {
    version = "0.5.0", game = "re0hd", data_dir = "", exe_timestamp = 0, exe_base = 0, exe_size = 0,
    show_cursor = function() end, menu_open = function() return false end, ui_scale = function() return 1 end,
    local_ips = function() return { "192.168.1.20" } end,
}
log = { info = function() end, warn = function() end, error = function() end }
json = require("json")
mem = setmetatable({ write_bytes = function() return true end },
    { __index = function() return function() return nil end end })
os.remove("re0hd_coop_config.json")

local callbacks = { frame = {}, ui = {} }
re = {
    on_frame = function(fn) table.insert(callbacks.frame, fn) end,
    on_draw_ui = function(fn) table.insert(callbacks.ui, fn) end,
}
local pending_clicks, texts = {}, {}
local function add_text(t) texts[#texts + 1] = tostring(t) end
imgui = {
    flags = {}, tree_node = function() return false end, tree_pop = function() end,
    text = add_text, text_colored = add_text, text_wrapped = add_text,
    separator = function() end, same_line = function() end,
    button = function(label)
        if pending_clicks[label] then pending_clicks[label] = nil; return true end
        return false
    end,
    input_text = function(_, v) return false, v end,
    checkbox = function(_, v) return false, v end,
    set_next_window_pos = function() end, set_next_window_size = function() end,
    set_next_window_bg_alpha = function() end, push_font_scale = function() end, pop_font_scale = function() end,
    display_size = function() return 1920, 1080 end,
    begin_window = function() return true end, end_window = function() end,
}

-- ---- Nachgebautes Spiel des Hosts ------------------------------------------------------
local SLOT_SIZE = 1000
local function make_slot(fill, playtime_frames)
    local head = string.rep(fill, 0x1C) .. string.pack("<f", playtime_frames)
    return head .. string.rep(fill, SLOT_SIZE - #head)
end
local fake = { title = true, playtime = 0, slot = 2, data = make_slot("H", 36000) } -- Platz mit 10 Minuten
local game = {
    ID = "re0hd", supported = true, SAVE_SLOTS = 20, SAVE_SLOT_SIZE = SLOT_SIZE,
    is_title = function() return fake.title end,
    current_save_slot = function() return fake.slot end,
    read_save_slot = function() return fake.data end,
    playtime = function() return fake.playtime end,
    describe_save = function() return "Test" end,
    save_busy = function() return false end, load_save_slot = function() return false end,
    write_save_slot = function() return true end, save_slot_matches = function() return true end,
    set_current_save_slot = function() return true end, start_game = function() return false end,
    get_local_state = function()
        if fake.title then return nil end
        return { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, character = 1, area = "Tr04" }
    end,
    partner_object = function() return nil end, read_state = function() return nil end,
    place_partner = function() return false end, hide_partner = function() return false end,
    camera_heading = function() return 0 end, set_partner_key = function() end, set_change_key = function() end,
    same_room = function() return nil end,
}
package.loaded["re0hd_coop.game"] = game

coopnet = net_a
dofile(RE0 .. "/autorun/re0hd_coop.lua")
local function frame()
    texts = {}
    for _, fn in ipairs(callbacks.frame) do fn() end
end

-- Host starten (ueber die Lobby)
pending_clicks["Spiel hosten"] = true
frame()
assert(net_a.status().mode == "hosting", "Host nicht gestartet")

-- ---- Freund B -------------------------------------------------------------------------
local Session = require("remultiplayer_coop.session")
local b = Session.new({ net = net_b, game = "re0hd", mod_version = "0.9.1", name = "Housend" })
local begins = {}
b:on("SAVE_BEGIN", function(_, _, msg) begins[#begins + 1] = msg end)
b:on("SAVE_CHUNK", function() end)
assert(b:join("127.0.0.1", 27350))

local function run(seconds, until_fn)
    local deadline = net_a.time() + seconds
    while net_a.time() < deadline do
        b:update()
        frame()
        if until_fn and until_fn() then return true end
        sleep_ms(16)
    end
    return false
end
assert(run(3, function() return #b:ready_peers() > 0 end), "Freund nicht verbunden")
run(0.3)

-- 1. Anfrage im Titelbildschirm -> Absage
b:send("SAVE_REQUEST", {}, true)
assert(run(2, function() return #begins >= 1 end), "keine Antwort auf SAVE_REQUEST")
assert(begins[1].size == 0 and begins[1].info:find("Titelbildschirm"), "falsche Absage: " .. tostring(begins[1].info))

-- 2. Host laedt (Spielzeit = Platz) -> Spielstand kommt ohne neue Anfrage
fake.title, fake.playtime = false, 36000
assert(run(3, function() return #begins >= 2 end), "Host schickt den Spielstand nicht von selbst")
assert(begins[2].size == SLOT_SIZE, "falsche Groesse: " .. tostring(begins[2].size))

-- 3. Neues Spiel: Spielzeit 1 Minute, Platz hat 10 Minuten -> Absage
fake.playtime = 3600
b:send("SAVE_REQUEST", {}, true)
assert(run(2, function() return #begins >= 3 end), "keine Antwort im neuen Spiel")
assert(begins[3].size == 0 and begins[3].info:find("neues Spiel"), "neues Spiel nicht erkannt: " .. tostring(begins[3].info))

-- Nach dem Speichern (Platz mit aktueller Spielzeit) geht es wieder, ebenfalls von selbst
fake.data = make_slot("N", 3600)
assert(run(3, function() return #begins >= 4 end), "nach dem Speichern kein Spielstand")
assert(begins[4].size == SLOT_SIZE)

b:leave()
os.remove("re0hd_coop_config.json")
print("re0hd_host_test: alles ok")
