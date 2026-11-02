-- re0hd_coop/devconsole.lua - Entwickler-Konsole fuer Claude (nur fuer die Entwicklung).
--
-- Ist sie im Menue eingeschaltet, schaut das Spiel alle 0,5 Sekunden nach der
-- Datei remods/data/claude_cmd.lua, fuehrt sie einmal aus, loescht sie und
-- schreibt das Ergebnis nach remods/data/claude_out.json. So kann Claude im
-- laufenden Spiel forschen, ohne dass der User jedes Mal klicken muss.
--
-- Im Befehl verfuegbar (zusaetzlich zur normalen Lua-Umgebung):
--   out(...)              Werte ins Ergebnis schreiben
--   task(fn)              fn jeden Frame ausfuehren (bis fn false zurueckgibt oder task(nil))
--   console.store         Tabelle, die zwischen Befehlen erhalten bleibt

local M = {}

local CMD_FILE = "claude_cmd.lua"
local OUT_FILE = "claude_out.json"
local POLL_INTERVAL = 0.5

M.enabled = false
M.store = {}
M.last_result = nil

local last_poll = 0
local current_task = nil
local run_count = 0

local function data_path(name)
    return (remods and remods.data_dir or "") .. name
end

local function to_plain(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "table" then
        if depth > 6 then return "<zu tief>" end
        local r = {}
        for k, x in pairs(v) do r[k] = to_plain(x, depth + 1) end
        return r
    elseif t == "function" or t == "userdata" or t == "thread" then
        return tostring(v)
    end
    return v
end

local function write_result(result)
    M.last_result = result
    pcall(json.dump_file, OUT_FILE, result)
end

local function run_command(code)
    run_count = run_count + 1
    local output = {}
    local env = setmetatable({
        out = function(...)
            local n = select("#", ...)
            local args = { ... }
            for i = 1, n do output[#output + 1] = to_plain(args[i]) end
            if n == 0 then output[#output + 1] = json.null end
        end,
        task = function(fn) current_task = fn end,
        console = M,
    }, { __index = _G })

    local chunk, err = load(code, "=claude_cmd", "t", env)
    local result = { run = run_count, time = os.date("%Y-%m-%d %H:%M:%S") }
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
    log.info(string.format("[devconsole] Befehl %d ausgefuehrt: %s", run_count, result.ok and "ok" or "FEHLER"))
end

function M.update(now)
    if current_task then
        local ok, keep = pcall(current_task)
        if not ok then
            write_result({ task_error = tostring(keep), time = os.date("%Y-%m-%d %H:%M:%S") })
            current_task = nil
        elseif keep == false then
            current_task = nil
        end
    end

    if not M.enabled or now - last_poll < POLL_INTERVAL then
        return
    end
    last_poll = now
    local f = io.open(data_path(CMD_FILE), "rb")
    if not f then
        return
    end
    local code = f:read("a")
    f:close()
    os.remove(data_path(CMD_FILE))
    run_command(code)
end

function M.status_text()
    if not M.enabled then
        return "aus"
    end
    local s = string.format("an, %d Befehl(e) ausgefuehrt", run_count)
    if current_task then
        s = s .. ", Aufgabe laeuft"
    end
    return s
end

return M
