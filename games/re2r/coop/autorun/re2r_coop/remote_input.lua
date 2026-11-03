-- re2r_coop/remote_input.lua
--
-- Eingaben fuer eine echte zweite Spielfigur (Mitspieler). Das Spiel fragt
-- Tasten ueber das globale app.ropeway.InputSystem ab. Die Engine aktualisiert
-- die Figuren parallel in mehreren Threads, deshalb merken wir PRO THREAD, ob
-- er gerade eine Komponente der gesteuerten Figur aktualisiert, und
-- beantworten nur dann die Abfragen aus unserem eigenen Speicher.
--
-- Bestaetigt im Spiel am 3. November 2026 (Entwickler-Konsole, Claire als
-- zweite Figur in Leons Spiel):
--   - mit "keine Eingabe" steht Claire still, Leon laesst sich normal steuern
--   - mit Leons eigenen Eingaben als Quelle laeuft, zielt und schiesst Claire mit
--   - Sackgassen: PlayerCondition.get_PadKind umbiegen, ActiveUserPadKind
--     global umschalten (trifft wegen der Threads auch Leon)
-- UNBESTAETIGT: Umrechnung der Sticks auf die eigene Kamera (cam_yaw),
--   analoge Trigger (getAnalogTrigger wurde im Test nie aufgerufen).

local game = require("re2r_coop.game")

local M = {}

-- Vorzeichen der Kamera-Umrechnung (UNBESTAETIGT, ggf. auf -1 drehen).
M.YAW_SIGN = 1

local KIND_MOVE, KIND_WATCH = 1, 2
local STICK_PROPS = { "Axis", "AxisOld", "RawAxis", "Direction", "Angle", "AngleOld", "AngularVelocity",
    "Magnitude", "Power", "PowerH", "PowerV", "MagnitudeOld", "PowerOld" }

-- Komponenten der gesteuerten Figur, deren update/lateUpdate wir verfolgen.
M.UPDATE_TYPES = {
    "survivor.SurvivorController", "survivor.SurvivorActionOrderer", "survivor.SurvivorCondition",
    "survivor.SurvivorUserVariablesUpdater", "survivor.SurvivorCharacterController", "survivor.Equipment",
    "survivor.SurvivorWallHitChecker", "survivor.SurvivorBuriedArmCorrector", "survivor.SurvivorIKLeftArmController",
    "survivor.player.PlayerForbidAimController", "LookAtBase", "MotionSpeedController",
}

-- Zustand der gesteuerten Figur
M.addrs = {}          -- Adressen ihrer Komponenten -> true
M.inside = {}         -- thread_id -> Tiefe
M.on, M.prev, M.down, M.up = 0, 0, 0, 0
M.al, M.ar = 0.0, 0.0
M.pending = nil       -- zuletzt empfangene Nachricht, wird in step() uebernommen
M.installed = false
M.stats = { bool = 0, stick = 0, trig = 0 }
M.last_error = nil

local function isys()
    return sdk.get_managed_singleton(game.ns("InputSystem"))
end

-- --- Hilfen ------------------------------------------------------------------

function M.split64(v)
    return v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF
end

function M.join64(lo, hi)
    return (lo & 0xFFFFFFFF) | ((hi & 0xFFFFFFFF) << 32)
end

-- Gierwinkel der aktiven Kamera (Radiant), nil wenn unbekannt.
function M.camera_yaw()
    local cam = sdk.get_primary_camera and sdk.get_primary_camera()
    local go = cam and game.try_call(cam, "get_GameObject")
    local tr = go and game.try_call(go, "get_Transform")
    local z = tr and game.try_call(tr, "get_AxisZ")
    if z == nil then
        return nil
    end
    return math.atan(z.x, z.z)
end

local function rotate2(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end

-- --- Senden: eigene Eingaben lesen ------------------------------------------

local function read_stick(msg, prefix, stick)
    local axis = stick:call("get_Axis")
    local dir = stick:call("get_Direction")
    msg[prefix .. "x"], msg[prefix .. "y"] = axis.x, axis.y
    msg[prefix .. "mag"] = stick:call("get_Magnitude")
    msg[prefix .. "ang"] = stick:call("get_Angle")
    msg[prefix .. "dx"], msg[prefix .. "dy"], msg[prefix .. "dz"] = dir.x, dir.y, dir.z
    msg[prefix .. "pw"] = stick:call("get_Power") & 0xFF
    msg[prefix .. "pwh"] = stick:call("get_PowerH") & 0xFF
    msg[prefix .. "pwv"] = stick:call("get_PowerV") & 0xFF
end

-- Liest die Eingaben des lokalen Spielers als INPUT_STATE-Felder (ohne seq).
function M.read_local()
    local sys = isys()
    local unit = sys and sys:call("getActiveUserInputUnit")
    if unit == nil then
        return nil
    end
    local bits = unit:get_field("<_ButtonBits>k__BackingField")
    local msg = {}
    msg.on_lo, msg.on_hi = M.split64(bits:get_field("On"))
    read_stick(msg, "l", unit:get_field("<_LStick>k__BackingField"))
    read_stick(msg, "r", unit:get_field("<_RStick>k__BackingField"))
    msg.al = unit:get_field("<_AnalogL>k__BackingField") or 0.0
    msg.ar = unit:get_field("<_AnalogR>k__BackingField") or 0.0
    msg.cam_yaw = M.camera_yaw() or 0.0
    return msg
end

-- --- Empfangen: Speicher der gesteuerten Figur -------------------------------

local function new_stick()
    local s = sdk.create_instance(game.ns("InputSystem.AnalogStick"), true)
    if s == nil then
        return nil
    end
    s = s:add_ref()
    pcall(s.call, s, ".ctor")
    return s
end

local function write_stick(stick, msg, prefix, yaw_delta)
    -- alte Werte nachziehen, damit das Spiel Aenderungen erkennt
    stick:call("set_AxisOld", stick:call("get_Axis"))
    stick:call("set_AngleOld", stick:call("get_Angle"))
    stick:call("set_MagnitudeOld", stick:call("get_Magnitude"))
    stick:call("set_PowerOld", stick:call("get_Power"))

    local x, y = rotate2(msg[prefix .. "x"], msg[prefix .. "y"], yaw_delta)
    local dx, dz = rotate2(msg[prefix .. "dx"], msg[prefix .. "dz"], yaw_delta)
    stick:call("set_Axis", Vector2f.new(x, y))
    stick:call("set_RawAxis", Vector2f.new(x, y))
    stick:call("set_Direction", Vector3f.new(dx, msg[prefix .. "dy"], dz))
    stick:call("set_Angle", msg[prefix .. "ang"] + yaw_delta)
    stick:call("set_Magnitude", msg[prefix .. "mag"])
    stick:call("set_Power", msg[prefix .. "pw"])
    stick:call("set_PowerH", msg[prefix .. "pwh"])
    stick:call("set_PowerV", msg[prefix .. "pwv"])
end

-- Neue Eingaben des Mitspielers (INPUT_STATE). Uebernommen wird in step().
function M.receive(msg)
    M.pending = msg
end

-- Einmal pro Frame vor den Behavior-Updates: Knoepfe und Sticks setzen,
-- gerade gedrueckt/losgelassen ausrechnen.
function M.step()
    local msg = M.pending
    if msg ~= nil then
        M.ls = M.ls or new_stick()
        M.rs = M.rs or new_stick()
        local local_yaw = M.camera_yaw()
        local delta = 0
        if local_yaw ~= nil and msg.cam_yaw ~= nil then
            delta = M.YAW_SIGN * (local_yaw - msg.cam_yaw)
        end
        M.on = M.join64(msg.on_lo, msg.on_hi)
        if M.ls then write_stick(M.ls, msg, "l", delta) end
        if M.rs then write_stick(M.rs, msg, "r", delta) end
        M.al, M.ar = msg.al or 0.0, msg.ar or 0.0
    end
    M.down = M.on & ~M.prev
    M.up = M.prev & ~M.on
    M.prev = M.on
end

-- Figur festlegen (GameObject) oder loesen (nil). Ohne Figur sind die Hooks
-- wirkungslos.
function M.attach(go)
    local addrs = {}
    if go ~= nil then
        for _, comp in ipairs(go:call("get_Components"):get_elements()) do
            if comp:get_type_definition():get_full_name():find("^app%.ropeway%.survivor") then
                addrs[comp:get_address()] = true
            end
        end
    end
    M.addrs = addrs
    M.on, M.prev, M.down, M.up, M.al, M.ar = 0, 0, 0, 0, 0.0, 0.0
    M.pending = nil
end

function M.attached()
    return next(M.addrs) ~= nil
end

-- --- Hooks -------------------------------------------------------------------

local function param_index(m, tname)
    for i, t in ipairs(m:get_param_types() or {}) do
        if t:get_full_name() == tname then
            return i
        end
    end
end

local function hook_update(m, hooked)
    if m == nil then
        return
    end
    local key = m:get_declaring_type():get_full_name() .. "." .. m:get_name()
    if hooked[key] then
        return
    end
    hooked[key] = true
    sdk.hook(m, function(args)
        local s = thread.get_hook_storage()
        s.mark = false
        if M.addrs[sdk.to_int64(args[2])] then
            local id = thread.get_id()
            M.inside[id] = (M.inside[id] or 0) + 1
            s.mark = true
        end
    end, function(r)
        local s = thread.get_hook_storage()
        if s.mark then
            local id = thread.get_id()
            M.inside[id] = (M.inside[id] or 1) - 1
        end
        return r
    end)
end

local function in_partner_thread()
    return (M.inside[thread.get_id()] or 0) > 0
end

local function hook_query(m, spec)
    local base = m:is_static() and 1 or 2 -- args[base + i] = Parameter i
    sdk.hook(m, function(args)
        local s = thread.get_hook_storage()
        s.mine = in_partner_thread()
        if not s.mine then
            return
        end
        if spec.idx then s.a = sdk.to_int64(args[base + spec.idx]) end
        if spec.all_idx then s.all = (sdk.to_int64(args[base + spec.all_idx]) & 1) == 1 end
        if spec.ki then s.k = sdk.to_int64(args[base + spec.ki]) & 0xFFFFFFFF end
        if spec.si then s.sk = sdk.to_int64(args[base + spec.si]) & 0xFFFFFFFF end
        if spec.ti then s.t = sdk.to_int64(args[base + spec.ti]) & 0xFFFFFFFF end
    end, function(retval)
        local s = thread.get_hook_storage()
        if not s.mine then
            return retval
        end
        if spec.kind == "bits" then
            M.stats.bool = M.stats.bool + 1
            local bits, mask = M[spec.field], s.a or 0
            local hit
            if s.all then
                hit = (bits & mask) == mask
            else
                hit = (bits & mask) ~= 0
            end
            return sdk.to_ptr(hit and 1 or 0)
        elseif spec.kind == "false" then
            return sdk.to_ptr(0)
        elseif spec.kind == "stick" then
            local right = spec.fixed == "R" or s.k == KIND_WATCH or s.sk == 2
            local stick = right and M.rs or M.ls
            if stick == nil then
                return retval
            end
            M.stats.stick = M.stats.stick + 1
            return sdk.to_ptr(stick:get_address())
        elseif spec.kind == "trig" then
            M.stats.trig = M.stats.trig + 1
            return sdk.float_to_ptr((s.t == 2) and M.ar or M.al)
        end
        return retval
    end)
end

-- Einmal pro Lua-Zustand. REFramework kann Hooks nicht entfernen, sie bleiben
-- bis "Reset Scripts" und sind ohne attach() wirkungslos.
function M.install()
    if M.installed then
        return
    end
    M.installed = true

    local hooked = {}
    for _, short in ipairs(M.UPDATE_TYPES) do
        local td = sdk.find_type_definition(game.ns(short))
        if td ~= nil then
            hook_update(td:get_method("update"), hooked)
            hook_update(td:get_method("lateUpdate"), hooked)
        end
    end

    local KIND_T, MASK_T = game.ns("InputDefine.Kind"), "System.UInt64"
    local SKIND_T, TRIG_T = game.ns("InputDefine.AnalogStick.Kind"), game.ns("InputDefine.Trigger")
    local STICK_T = game.ns("InputSystem.AnalogStick")
    local td = sdk.find_type_definition(game.ns("InputSystem"))
    for _, m in ipairs(td:get_methods()) do
        local n, rt = m:get_name(), m:get_return_type():get_full_name()
        local spec
        if rt == "System.Boolean" and (n == "isOn" or n == "isDown" or n == "isUp") then
            local ki, mi = param_index(m, KIND_T), param_index(m, MASK_T)
            if ki or mi then
                spec = { kind = "bits", field = (n == "isOn" and "on") or (n == "isDown" and "down") or "up",
                    idx = ki or mi, all_idx = mi and (mi + 1) }
            end
        elseif rt == "System.Boolean" and (n:match("^is[FBLR]") or n == "checkCommand") then
            spec = { kind = "false" }
        elseif rt == STICK_T then
            spec = { kind = "stick", ki = param_index(m, KIND_T), si = param_index(m, SKIND_T),
                fixed = (n:find("RStick") and "R") or (n:find("LStick") and "L") or nil }
        elseif n == "getAnalogTrigger" and sdk.float_to_ptr ~= nil then
            spec = { kind = "trig", ti = param_index(m, TRIG_T) }
        end
        if spec ~= nil then
            hook_query(m, spec)
        end
    end

    re.on_pre_application_entry("UpdateBehavior", function()
        if not M.attached() then
            return
        end
        local ok, err = pcall(M.step)
        if not ok then
            M.last_error = tostring(err)
        end
    end)
end

return M
