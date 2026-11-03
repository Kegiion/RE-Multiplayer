-- re2r_coop/devconsole.lua - Entwickler-Konsole fuer Claude (nur fuer die Entwicklung).
--
-- Ist sie im Menue eingeschaltet, liest das Spiel alle 0,5 Sekunden die Datei
-- reframework/data/claude_cmd.json = { "id": <zahl>, "code": "<Lua>" }.
-- Ist die id neu, wird der Code einmal ausgefuehrt und das Ergebnis nach
-- reframework/data/claude_out.json geschrieben (mit derselben id).
--
-- Wir nutzen nur json.load_file/json.dump_file, weil REFramework io/os im
-- Sandbox-Modus einschraenkt (UNBESTAETIGT, ob io.open hier ginge).
--
-- Im Befehl verfuegbar (zusaetzlich zur normalen Lua-Umgebung):
--   out(...)        Werte ins Ergebnis schreiben
--   task(fn)        fn jeden Frame ausfuehren (bis fn false zurueckgibt oder task(nil))
--   console.store   Tabelle, die zwischen Befehlen erhalten bleibt
--   game            re2r_coop.game (Spielzugriff)
--   camera(fn)      eigene Kamera: fn() liefert (position, ziel) als Vector3f,
--                   wird jedes Bild vor "LockScene" angewendet. camera(nil) = aus.
--                   Mit tools/spielfoto.ps1 kann Claude das Bild dann ansehen.
--                   Bestaetigt am 3. November 2026: vor LockScene gesetzt wirkt
--                   es, in BeginRendering nicht.

local game = require("re2r_coop.game")

local M = {}

M.CMD_FILE = "claude_cmd.json"
M.OUT_FILE = "claude_out.json"
local POLL_INTERVAL = 0.5
local MAX_DEPTH = 6

M.enabled = false
M.store = {}
M.last_id = nil
M.run_count = 0

local last_poll = -math.huge
local current_task = nil

-- Managed-Objekte als Text mit Typname, sonst tostring.
local function describe_userdata(v)
    local ok, td = pcall(function() return v:get_type_definition() end)
    if ok and td ~= nil then
        local ok_name, name = pcall(td.get_full_name, td)
        if ok_name then
            return "<" .. tostring(name) .. ">"
        end
    end
    return tostring(v)
end

-- Macht Werte JSON-tauglich. Tabellen, die keine luecklose Liste sind,
-- bekommen Text-Schluessel (JSON vertraegt keine gemischten Schluessel).
local function to_plain(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "table" then
        if depth > MAX_DEPTH then
            return "<zu tief>"
        end
        local count = 0
        for _ in pairs(v) do
            count = count + 1
        end
        local r = {}
        if count == #v then
            for i = 1, #v do
                r[i] = to_plain(v[i], depth + 1)
            end
        else
            for k, x in pairs(v) do
                r[tostring(k)] = to_plain(x, depth + 1)
            end
        end
        return r
    elseif t == "userdata" then
        return describe_userdata(v)
    elseif t == "function" or t == "thread" then
        return tostring(v)
    end
    return v
end
M.to_plain = to_plain

local function write_result(result)
    pcall(json.dump_file, M.OUT_FILE, result)
end

function M.run(id, code)
    M.run_count = M.run_count + 1
    local output = {}
    local env = setmetatable({
        out = function(...)
            local n = select("#", ...)
            local args = { ... }
            for i = 1, n do
                output[#output + 1] = to_plain(args[i])
            end
            if n == 0 then
                output[#output + 1] = "nil"
            end
        end,
        task = function(fn) current_task = fn end,
        camera = function(fn) M.camera_view, M.camera_error = fn, nil end,
        console = M,
        game = game,
    }, { __index = _G })

    local result = { id = id, run = M.run_count, time = os.date("%Y-%m-%d %H:%M:%S") }
    local chunk, err = load(code, "=claude_cmd", "t", env)
    if not chunk then
        result.ok, result.error = false, err
    else
        local ok, ret = xpcall(chunk, debug.traceback)
        result.ok = ok
        if ok then
            result.returned = to_plain(ret)
        else
            result.error = tostring(ret)
        end
    end
    result.output = output
    write_result(result)
    return result
end

-- Nach einem "Reset Scripts" den letzten Befehl nicht erneut ausfuehren:
-- die id des letzten Ergebnisses gilt als schon erledigt.
local function init_last_id()
    if M.last_id ~= nil then
        return
    end
    local ok, last = pcall(json.load_file, M.OUT_FILE)
    M.last_id = (ok and type(last) == "table" and tonumber(last.id)) or 0
end

function M.update(now)
    if current_task then
        local ok, keep = pcall(current_task)
        if not ok then
            write_result({ id = M.last_id, task_error = tostring(keep), time = os.date("%Y-%m-%d %H:%M:%S") })
            current_task = nil
        elseif keep == false then
            current_task = nil
        end
    end

    if not M.enabled or now - last_poll < POLL_INTERVAL then
        return
    end
    last_poll = now
    init_last_id()

    local ok, cmd = pcall(json.load_file, M.CMD_FILE)
    if not ok or type(cmd) ~= "table" then
        return
    end
    local id = tonumber(cmd.id)
    if id == nil or id <= M.last_id or type(cmd.code) ~= "string" then
        return
    end
    M.last_id = id
    M.run(id, cmd.code)
end

-- Kamera auf pos richten, Blick auf tgt (RE-Engine-Kamera schaut entlang -Z).
local function apply_camera()
    if M.camera_view == nil then
        return
    end
    local ok, err = pcall(function()
        local pos, tgt = M.camera_view()
        local cam = sdk.get_primary_camera()
        local tr = cam:call("get_GameObject"):call("get_Transform")
        tr:call("set_Position", pos)
        local dx, dy, dz = tgt.x - pos.x, tgt.y - pos.y, tgt.z - pos.z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 1e-4 then
            return
        end
        local yaw = math.atan(-dx, -dz)
        local pitch = math.asin(dy / len)
        local cy, sy = math.cos(yaw / 2), math.sin(yaw / 2)
        local cp, sp = math.cos(pitch / 2), math.sin(pitch / 2)
        tr:call("set_Rotation", Quaternion.new(cy * cp, cy * sp, sy * cp, -sy * sp))
    end)
    if not ok then
        M.camera_error = tostring(err)
        M.camera_view = nil -- bei Fehlern aus, damit der Spieler wieder sieht
    end
end

if re ~= nil and re.on_pre_application_entry ~= nil then
    re.on_pre_application_entry("LockScene", apply_camera)
end

function M.status_text()
    if not M.enabled then
        return "aus"
    end
    local s = string.format("an, %d Befehl(e) ausgefuehrt", M.run_count)
    if current_task then
        s = s .. ", Aufgabe laeuft"
    end
    if M.camera_view then
        s = s .. ", eigene Kamera an"
    end
    return s
end

return M
