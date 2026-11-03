-- Testet den Multiplayer-Bereich im Titelbildschirm mit dem echten Hauptskript:
-- "Freund beitreten" -> verbinden -> Spielstand anfordern (Host ist erst noch im
-- Titelbildschirm, die Mod fragt nach) -> empfangen -> automatisch laden und starten.
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
local pending_clicks, texts, windows = {}, {}, {}
local function add_text(t) texts[#texts + 1] = tostring(t) end
imgui = {
    flags = { no_title = 1, no_resize = 2, no_move = 4, no_collapse = 8, auto_resize = 16, no_saved_settings = 32,
        no_decoration = 64, no_focus_on_appearing = 128, no_nav = 256, no_inputs = 512 },
    tree_node = function() return false end, tree_pop = function() end,
    text = add_text, text_colored = add_text, text_wrapped = add_text,
    separator = function() end, same_line = function() end,
    button = function(label)
        if pending_clicks[label] then pending_clicks[label] = nil; return true end
        return false
    end,
    input_text = function(_, v) return false, v end,
    checkbox = function(_, v) return false, v end,
    set_next_window_pos = function() end, set_next_window_size = function() end,
    set_next_window_bg_alpha = function() end,
    push_font_scale = function() end, pop_font_scale = function() end,
    display_size = function() return 1920, 1080 end,
    begin_window = function(name) windows[#windows + 1] = name; return true end,
    end_window = function() end,
}

-- ---- Nachgebautes Spiel (Mitspieler im Titelbildschirm) -----------------------------
local SLOT_SIZE = 1000
local fake = { title = true, busy = 0, slots = {}, current = nil, started = false, frames_since_start = 0 }
local game = {
    ID = "re0hd", supported = true, SAVE_SLOTS = 20, SAVE_SLOT_SIZE = SLOT_SIZE,
    is_title = function() return fake.title end,
    save_busy = function() return fake.busy > 0 end,
    load_save_slot = function(slot)
        if fake.busy > 0 then return false end
        fake.busy = 1
        fake.slots[slot] = string.rep("F", SLOT_SIZE) -- Laden liest die Datei neu ein
        fake.loaded = slot
        return true
    end,
    write_save_slot = function(slot, data) fake.slots[slot] = data; return true end,
    save_slot_matches = function(slot, data) return fake.slots[slot] == data end,
    set_current_save_slot = function(slot) fake.current = slot; return true end,
    current_save_slot = function() return fake.current end,
    start_game = function()
        if not fake.title then return false end
        fake.title, fake.started = false, true
        return true
    end,
    read_save_slot = function() return nil end,
    describe_save = function() return "Test" end,
    get_local_state = function()
        if fake.started and fake.frames_since_start > 5 then
            return { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, character = 2, area = "Tr04" }
        end
        return nil
    end,
    partner_object = function() return nil end,
    read_state = function() return nil end,
    place_partner = function() return false end,
    hide_partner = function() return false end,
    camera_heading = function() return 0 end,
    set_partner_key = function() end,
    set_change_key = function() end,
    same_room = function() return nil end,
}
package.loaded["re0hd_coop.game"] = game

coopnet = net_a
dofile(RE0 .. "/autorun/re0hd_coop.lua")

local function frame()
    texts, windows = {}, {}
    for _, fn in ipairs(callbacks.frame) do fn() end
    if fake.busy > 0 then fake.busy = fake.busy - 1 end
    if fake.started then fake.frames_since_start = fake.frames_since_start + 1 end
end
local function has_text(pattern)
    for _, t in ipairs(texts) do if t:find(pattern) then return t end end
end

-- ---- Host B (reine Lua-Session) -------------------------------------------------
local Session = require("remultiplayer_coop.session")
local savesync = require("re0hd_coop.savesync")
local b = Session.new({ net = net_b, game = "re0hd", mod_version = "0.9.0", name = "Housend" })
local host_save = string.rep("H", SLOT_SIZE)
local requests, transfer = 0, 0
b:on("SAVE_REQUEST", function(s, peer)
    requests = requests + 1
    transfer = transfer + 1
    if requests == 1 then
        s:send("SAVE_BEGIN", { transfer = transfer, size = 0, chunks = 0, checksum = 0,
            info = "Der Host ist noch im Titelbildschirm." }, true, peer.id)
        return
    end
    local begin, chunks = savesync.split(host_save, transfer, "Platz 3, Test")
    s:send("SAVE_BEGIN", begin, true, peer.id)
    for _, c in ipairs(chunks) do s:send("SAVE_CHUNK", c, true, peer.id) end
end)
assert(b:host(27350))

-- 1. Titelbildschirm: Lobby-Fenster mit den beiden Knoepfen
frame()
local lobby_seen = false
for _, w in ipairs(windows) do if w:find("lobby") then lobby_seen = true end end
assert(lobby_seen, "Lobby-Fenster fehlt im Titelbildschirm")
assert(has_text("RE:Multiplayer"), "Titel fehlt")

-- 2. Freund beitreten -> Verbinden
pending_clicks["Freund beitreten"] = true
frame()
pending_clicks["Verbinden"] = true
frame()
assert(net_a.status().mode ~= "idle", "Verbindung nicht gestartet")

local deadline = net_a.time() + 12
while net_a.time() < deadline and not (fake.started and fake.frames_since_start > 10) do
    b:update()
    frame()
    sleep_ms(16)
end
assert(requests >= 2, "Mod hat nicht nachgefragt, als der Host noch im Titel war (" .. requests .. " Anfragen)")
assert(fake.loaded == 19, "Platz 20 nicht geladen")
assert(fake.slots[19] == host_save, "Spielstand des Hosts liegt nicht in Platz 20")
assert(fake.current == 19, "Platz 20 nicht als aktueller Platz eingetragen")
assert(fake.started, "Spiel nicht gestartet")

-- 3. Im Spiel: Status-Anzeige statt Lobby
for i = 1, 5 do b:update(); frame(); sleep_ms(10) end
local badge = false
for _, w in ipairs(windows) do if w:find("badge") then badge = true end end
assert(badge, "Status-Anzeige fehlt im Spiel")
assert(has_text("RE:Multiplayer %- Housend"), "Status-Anzeige zeigt den Mitspieler nicht")

b:leave()
os.remove("re0hd_coop_config.json")
print("re0hd_lobby_test: alles ok")
