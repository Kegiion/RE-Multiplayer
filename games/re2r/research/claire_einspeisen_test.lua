-- Versuch vom 3. November 2026 (im Spiel bestaetigt): Claire bekommt ihre
-- Eingaben aus einem eigenen Speicher (st.r). Schleifen-Test: Der Speicher
-- wird jeden Frame mit den Eingaben des lokalen Spielers gefuellt, Claire
-- laeuft, zielt und schiesst dann wie Leon.
--
-- Voraussetzung: vorher claire_eingaben_test.lua ausfuehren (Claire erzeugen,
-- Update-Hooks pro Thread). Dieses Skript nutzt dessen Tabelle als `T`
-- (in der Konsole hiess sie console.store.t, im Skript claire_eingaben_test.lua
-- console.store.claire_input). Fuer das Netzwerk: R.loopback = false setzen
-- und R.on (UInt64-Bits von InputDefine.Kind), R.ls/R.rs (AnalogStick) und
-- R.al/R.ar selbst fuellen.
--
-- Ausgefuehrt wurde exakt dieser Code (console.store.t aus den Einzelversuchen).

local st = console.store
local T = st.t
T.enabled = false -- alte "keine Eingabe"-Hooks aus
local isys = sdk.get_managed_singleton(game.ns("InputSystem"))
local KIND_T, MASK_T, SKIND_T, TRIG_T = game.ns("InputDefine.Kind"), "System.UInt64", game.ns("InputDefine.AnalogStick.Kind"), game.ns("InputDefine.Trigger")
local STICK_T = game.ns("InputSystem.AnalogStick")
local MOVE, WATCH = 1, 2
st.r = st.r or {}
local R = st.r
R.enabled, R.loopback = true, true
R.on, R.prev, R.down, R.up, R.al, R.ar = 0, 0, 0, 0, 0.0, 0.0
R.n_bool, R.n_stick, R.n_trig, R.errors = 0, 0, 0, {}
local function new_stick()
  local s = sdk.create_instance(STICK_T, true):add_ref()
  pcall(s.call, s, ".ctor")
  return s
end
R.ls = R.ls or new_stick()
R.rs = R.rs or new_stick()
local STICK_PROPS = { "Axis", "AxisOld", "RawAxis", "Direction", "Angle", "AngleOld", "AngularVelocity", "Magnitude", "Power", "PowerH", "PowerV", "MagnitudeOld", "PowerOld" }
local function copy_stick(src, dst)
  for _, p in ipairs(STICK_PROPS) do dst:call("set_" .. p, src:call("get_" .. p)) end
end
-- Pro Frame vor den Behavior-Updates: Eingaben fuer Claire setzen
if not R.step_installed then
  re.on_pre_application_entry("UpdateBehavior", function()
    if not R.enabled then return end
    local ok, err = pcall(function()
      if R.loopback then
        local unit = isys:call("getActiveUserInputUnit")
        local b = unit:get_field("<_ButtonBits>k__BackingField")
        R.on = b:get_field("On")
        copy_stick(unit:get_field("<_LStick>k__BackingField"), R.ls)
        copy_stick(unit:get_field("<_RStick>k__BackingField"), R.rs)
        R.al, R.ar = unit:get_field("<_AnalogL>k__BackingField"), unit:get_field("<_AnalogR>k__BackingField")
      end
      R.down = R.on & ~R.prev
      R.up = R.prev & ~R.on
      R.prev = R.on
    end)
    if not ok and #R.errors < 5 then R.errors[#R.errors + 1] = "step: " .. tostring(err) end
  end)
  R.step_installed = true
end
-- Abfragen beantworten
local function param_index(m, tname)
  for i, t in ipairs(m:get_param_types() or {}) do if t:get_full_name() == tname then return i end end
end
if not R.hooks_installed then
  local td = sdk.find_type_definition(game.ns("InputSystem"))
  for _, m in ipairs(td:get_methods()) do
    local n, rt = m:get_name(), m:get_return_type():get_full_name()
    local base = m:is_static() and 1 or 2 -- args[base + i] = Parameter i
    local spec
    if rt == "System.Boolean" and (n == "isOn" or n == "isDown" or n == "isUp") then
      local ki, mi = param_index(m, KIND_T), param_index(m, MASK_T)
      if ki or mi then spec = { kind = "bits", field = (n == "isOn" and "on") or (n == "isDown" and "down") or "up", idx = ki or mi, all_idx = mi and (mi + 1) } end
    elseif rt == "System.Boolean" and (n:match("^is[FBLR]") or n == "checkCommand") then
      spec = { kind = "false" }
    elseif rt == STICK_T then
      spec = { kind = "stick", ki = param_index(m, KIND_T), si = param_index(m, SKIND_T), fixed = (n:find("RStick") and "R") or (n:find("LStick") and "L") }
    elseif n == "getAnalogTrigger" then
      spec = { kind = "trig", ti = param_index(m, TRIG_T) }
    end
    if spec then
      sdk.hook(m, function(args)
        local s = thread.get_hook_storage()
        s.mine = R.enabled and (T.inside[thread.get_id()] or 0) > 0
        if not s.mine then return end
        if spec.idx then s.a = sdk.to_int64(args[base + spec.idx]) end
        if spec.all_idx then s.all = (sdk.to_int64(args[base + spec.all_idx]) & 1) == 1 end
        if spec.ki then s.k = sdk.to_int64(args[base + spec.ki]) & 0xFFFFFFFF end
        if spec.si then s.sk = sdk.to_int64(args[base + spec.si]) & 0xFFFFFFFF end
        if spec.ti then s.t = sdk.to_int64(args[base + spec.ti]) & 0xFFFFFFFF end
      end, function(retval)
        local s = thread.get_hook_storage()
        if not s.mine then return retval end
        if spec.kind == "bits" then
          R.n_bool = R.n_bool + 1
          local bits, mask = R[spec.field], s.a
          local hit
          if s.all then hit = (bits & mask) == mask else hit = (bits & mask) ~= 0 end
          return sdk.to_ptr(hit and 1 or 0)
        elseif spec.kind == "false" then
          return sdk.to_ptr(0)
        elseif spec.kind == "stick" then
          R.n_stick = R.n_stick + 1
          local right = spec.fixed == "R" or (s.k == WATCH) or (s.sk == 2)
          return sdk.to_ptr((right and R.rs or R.ls):get_address())
        elseif spec.kind == "trig" then
          R.n_trig = R.n_trig + 1
          local v = (s.t == 2) and R.ar or R.al
          return sdk.float_to_ptr(v)
        end
        return retval
      end)
    end
  end
  R.hooks_installed = true
end
out("Einspeisen aktiv (Schleife: Claire bekommt Leons Eingaben)", sdk.float_to_ptr ~= nil)
