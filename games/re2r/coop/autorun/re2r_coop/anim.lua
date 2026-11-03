-- re2r_coop/anim.lua
--
-- Animationen des Spielers lesen (zum Senden) und auf die Puppe uebertragen.
--
-- Bestaetigt im Spiel am 2. November 2026 (Entwickler-Konsole, Leon):
--   - via.motion.Motion hat 6 Ebenen (TreeLayer). Genutzt werden 0..3:
--     0 = Koerper (z. B. 1/160 Idle, 1/190 Gehen, 1/230 Joggen, 2/120 Zielen
--     und seitlich gehen), 3 = Zielen beginnen (2/140), sonst leer.
--     get_MotionBankID/get_MotionID der Ebene zeigt auf einen Animations-Baum
--     (Bank 1 = LCM_TREE, 2 = HLD_TREE ...), dessen Knoten Leons Bewegungen
--     aus den dynamischen Baenken (1000 = BareHand, 2000 ...) abspielen.
--   - Die Puppe (Actor-Prefab) hat anfangs keine Animationsdateien. Sie braucht
--     die Haupt-Bank (set_MotionBankAsset, pl_common.motbank) UND die
--     dynamischen Baenke des Spielers (BareHand.motbank, wp0000.motbank),
--     danach setupMotionBank. Erst dann werden Gelenke animiert.
--   - Baenke lassen sich per Pfad laden: sdk.create_resource(
--     "via.motion.MotionBankResource", pfad):create_holder(...).
--   - Die Ueberblendung beim Wechsel ist je Uebergang verschieden (6 bis 36
--     Bilder, InterpolationMode 1 FrontFade / 2 CrossFade / 3 SyncCrossFade,
--     Kurve 0..3) und steht nach dem Wechsel in get_InterpolationFrame/-Mode/
--     -Curve der Ebene. Ohne sie wechselt die Puppe hart (Zucken). Das Tempo
--     (get_Speed) war beim Gehen, Joggen und Zielen immer 1.
--   - changeMotion(bank, motion, frame, ...) nur beim Wechsel aufrufen und das Bild
--     danach NICHT jeden Frame setzen, sonst bleibt die Ueberblendung haengen
--     und die Puppe zeigt nur Idle. Die MotionFsm2 der Puppe setzt die Ebenen
--     nicht zurueck (0 Ruecksetzer in 21000 Frames).
--   - Leere Ebene: changeMotion(0, 0xFFFFFFFF, 0) leert sie.
--   - Die Mischung im Baum (z. B. Gehen vorwaerts/seitwaerts, Treppe) kommt aus
--     den Steuer-Variablen der Motion (get_VariablesHub, 47 Stueck, z. B.
--     MoveDir, WatchDir, SlopeAngle, Pitch, Jog). Ohne sie spielt die Puppe im
--     Geh-Baum immer Knoten 240 mit Gewicht 1 (Rutschen). Die Werte lassen sich
--     an der Puppe mit set_F32/set_Bool setzen und bleiben stehen.
--   - RootMotion der Puppe auf None (0) stellen, sonst schiebt die Laufanimation
--     das Modell nach vorne (Springen/Verschwinden). Die Position kommt aus dem
--     Netzwerk.
--   - Schiessen: Ebene 4 (2/1100 HG_Hold_Shoot, davor 1 Bild 2/1120 NoAmmo),
--     Nachladen: Ebene 3 (2000/1200 HG_Hold_Reload). Der Schalter Fire ist
--     nur ein Bild lang an. Bei schnellen Schuessen springt Ebene 4 je Schuss
--     fuer genau ein Bild auf 2/1120 und zurueck auf 2/1100. Mit 20 Paketen
--     pro Sekunde sieht die Gegenseite das fast nie, deshalb zaehlt anim.track
--     jeden Start einer Animation auf den Aktions-Ebenen (restartN). Mit dem
--     Testbot bestaetigt: 7 schnelle Schuesse -> 7 Schuesse bei der Puppe.
-- UNBESTAETIGT: Claire, andere Waffen, Ebene 5, Zwischensequenzen.

local game = require("re2r_coop.game")

local anim = {}

anim.LAYER_COUNT = 6
-- Ebenen mit einmaligen Aktionen (Nachladen, Schuss): hier zaehlen wir Neustarts
-- derselben Animation, damit die Puppe auch Schuss auf Schuss nachspielt.
anim.RESTART_LAYERS = { [3] = true, [4] = true }
anim.MAX_DYNAMIC = 4
anim.NO_MOTION = 4294967295
anim.ROOT_MOTION_NONE = 0
anim.CHANGE_SIG = "changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, "
    .. "via.motion.InterpolationMode, via.motion.InterpolationCurve)"

-- Steuer-Variablen, die wir uebertragen (Reihenfolge = var1..var12 bzw. Bit 0..).
-- Beim Gehen, Joggen, Zielen und auf Treppen im Spiel beobachtet (Leon).
-- Ereignis-Schalter (Fire, Damage, Dead, EndReload ...) bewusst noch nicht:
-- UNBESTAETIGT, ob die Puppe damit selbst Aktionen ausloest.
anim.FLOAT_VARS = {
    "SlopeAngle", "MoveDir", "TargetMoveDir", "WatchDir", "TargetWatchDir", "CameraDir",
    "WheelBlendRate", "WheelSpeed", "Pitch", "MoveStickPower", "WatchStickPowerH", "FireSlur",
}
anim.BOOL_VARS = {
    "StepLeft", "Jog", "Relax", "HoldUp", "Heat", "Burn", "Cold", "CanRapidFire", "LowAttack",
}

local try_call = game.try_call

-- Variablen-Objekte je Motion-Komponente zwischenspeichern (findVariable ist
-- ein String-Lookup). Schluessel: Adresse der Komponente.
local var_cache = {}

local function var_handles(motion)
    local addr = motion:get_address()
    local h = var_cache[addr]
    if h ~= nil then
        return h
    end
    local hub = try_call(motion, "get_VariablesHub")
    if hub == nil then
        return nil
    end
    h = { floats = {}, bools = {} }
    for i, name in ipairs(anim.FLOAT_VARS) do
        h.floats[i] = try_call(hub, "findVariable(System.String)", name)
    end
    for i, name in ipairs(anim.BOOL_VARS) do
        h.bools[i] = try_call(hub, "findVariable(System.String)", name)
    end
    var_cache[addr] = h
    return h
end

function anim.forget(motion)
    if motion ~= nil then
        local ok, addr = pcall(motion.get_address, motion)
        if ok then
            var_cache[addr] = nil
        end
    end
end

-- Steuer-Variablen in msg schreiben (var1..var12, bits).
function anim.read_vars(motion, msg)
    local h = var_handles(motion)
    if h == nil then
        return
    end
    for i in ipairs(anim.FLOAT_VARS) do
        msg["var" .. i] = try_call(h.floats[i], "get_CastF32") or 0
    end
    local bits = 0
    for i in ipairs(anim.BOOL_VARS) do
        if try_call(h.bools[i], "get_Bool") == true then
            bits = bits | (1 << (i - 1))
        end
    end
    msg.bits = bits
end

-- Steuer-Variablen aus msg auf die Puppe setzen.
function anim.apply_vars(motion, msg)
    local h = var_handles(motion)
    if h == nil then
        return
    end
    for i in ipairs(anim.FLOAT_VARS) do
        local v = h.floats[i]
        if v ~= nil then
            v:call("set_F32", msg["var" .. i] or 0)
        end
    end
    local bits = math.floor(msg.bits or 0)
    for i in ipairs(anim.BOOL_VARS) do
        local v = h.bools[i]
        if v ~= nil then
            v:call("set_Bool", (bits >> (i - 1)) & 1 == 1)
        end
    end
end

local function motion_type()
    return sdk.typeof("via.motion.Motion")
end

function anim.get_motion(go)
    return try_call(go, "getComponent(System.Type)", motion_type())
end

local function resource_path(holder)
    return holder ~= nil and try_call(holder, "get_ResourcePath") or nil
end

-- Pfade der Animationsdateien: { main = "...", dyn = { "...", ... } } oder nil.
function anim.read_banks(motion)
    local main = resource_path(try_call(motion, "get_MotionBankAsset"))
    if main == nil or main == "" then
        return nil
    end
    local banks = { main = main, dyn = {} }
    local n = try_call(motion, "getDynamicMotionBankCount") or 0
    for i = 0, math.min(n, anim.MAX_DYNAMIC) - 1 do
        local bank = try_call(motion, "getDynamicMotionBank", i)
        local path = resource_path(try_call(bank, "get_MotionBank"))
        if path ~= nil and path ~= "" then
            banks.dyn[#banks.dyn + 1] = path
        end
    end
    return banks
end

-- Vergleichsschluessel fuer einen Bank-Satz.
function anim.banks_key(banks)
    if banks == nil then
        return ""
    end
    return banks.main .. "|" .. table.concat(banks.dyn, "|")
end

-- Bank-Satz <-> Felder von ANIM_BANKS.
function anim.banks_to_msg(banks, banks_id)
    local msg = { banks_id = banks_id, main = banks.main }
    for i = 1, anim.MAX_DYNAMIC do
        msg["dyn" .. i] = banks.dyn[i] or ""
    end
    return msg
end

function anim.banks_from_msg(msg)
    if msg.main == nil or msg.main == "" then
        return nil
    end
    local banks = { main = msg.main, dyn = {} }
    for i = 1, anim.MAX_DYNAMIC do
        local path = msg["dyn" .. i]
        if path ~= nil and path ~= "" then
            banks.dyn[#banks.dyn + 1] = path
        end
    end
    return banks
end

-- Jeden Frame fuer den eigenen Spieler aufrufen: zaehlt jeden Start einer
-- Animation auf den Aktions-Ebenen (Wechsel auf eine andere Animation oder
-- dieselbe beginnt von vorne). tracker = Tabelle, die der Aufrufer behaelt.
function anim.track(motion, tracker)
    for i in pairs(anim.RESTART_LAYERS) do
        local layer = try_call(motion, "getLayer", i)
        local id = try_call(layer, "get_MotionID")
        local frame = try_call(layer, "get_Frame") or 0
        local t = tracker[i] or { restart = 0 }
        tracker[i] = t
        if id ~= nil and id ~= anim.NO_MOTION and t.id ~= nil
            and (id ~= t.id or frame + 0.5 < (t.frame or 0)) then
            t.restart = (t.restart + 1) % 256
        end
        t.id, t.frame = id, frame
    end
end

-- Laufende Animationen als Felder fuer ANIM_STATE (ohne seq/banks_id).
function anim.read_layers(motion, tracker)
    local msg = {}
    for i = 0, anim.LAYER_COUNT - 1 do
        local layer = try_call(motion, "getLayer", i)
        local t = tracker and tracker[i]
        msg["restart" .. i] = t and t.restart or 0
        msg["bank" .. i] = try_call(layer, "get_MotionBankID") or 0
        msg["motion" .. i] = try_call(layer, "get_MotionID") or anim.NO_MOTION
        msg["frame" .. i] = try_call(layer, "get_Frame") or 0
        msg["interp" .. i] = try_call(layer, "get_InterpolationFrame") or 0
        msg["imode" .. i] = try_call(layer, "get_InterpolationMode") or 0
        msg["icurve" .. i] = try_call(layer, "get_InterpolationCurve") or 0
    end
    anim.read_vars(motion, msg)
    return msg
end

local function load_holder(path, holder_type)
    local res = sdk.create_resource("via.motion.MotionBankResource", path)
    if res == nil then
        error("Animationsdatei nicht geladen: " .. path)
    end
    if res.add_ref then
        res = res:add_ref()
    end
    local holder = res:create_holder(holder_type)
    if holder == nil then
        error("kein Holder fuer " .. path)
    end
    if holder.add_ref then
        holder = holder:add_ref()
    end
    return holder
end

-- Animationsdateien auf die Puppe setzen. Wirft bei Fehlern.
function anim.apply_banks(motion, banks)
    motion:call("set_MotionBankAsset", load_holder(banks.main, "via.motion.MotionBankResourceHolder"))
    motion:call("setDynamicMotionBankCount", #banks.dyn)
    for i, path in ipairs(banks.dyn) do
        local bank = sdk.create_instance("via.motion.DynamicMotionBank", true)
        if bank == nil then
            error("DynamicMotionBank nicht erzeugt")
        end
        if bank.add_ref then
            bank = bank:add_ref()
        end
        bank:call("set_MotionBank", load_holder(path, "via.motion.MotionBankResourceHolder"))
        motion:call("setDynamicMotionBank", i - 1, bank)
    end
    -- Wie beim Spieler (dort 1). UNBESTAETIGT, ob das fuer Claire gleich ist.
    motion:call("set_TargetBankType", 1)
    motion:call("setupMotionBank")
    motion:call("set_RootMotion", anim.ROOT_MOTION_NONE)
end

-- Animationen aus ANIM_STATE auf die Puppe uebertragen. Nur Ebenen, deren
-- Animation abweicht oder neu gestartet wurde, bekommen changeMotion (mit dem
-- Bild des Mitspielers). seen = Tabelle je Puppe (zuletzt gesehene Neustarts).
-- Gibt die Anzahl der Wechsel zurueck.
function anim.apply_layers(motion, msg, seen)
    local changes = 0
    seen = seen or {}
    for i = 0, anim.LAYER_COUNT - 1 do
        local layer = motion:call("getLayer", i)
        local bank, id = msg["bank" .. i] or 0, msg["motion" .. i] or anim.NO_MOTION
        local restart = msg["restart" .. i] or 0
        local restarted = seen[i] ~= nil and seen[i] ~= restart
        seen[i] = restart
        if layer ~= nil and (restarted or layer:call("get_MotionBankID") ~= bank or layer:call("get_MotionID") ~= id) then
            local frame = id == anim.NO_MOTION and 0 or (msg["frame" .. i] or 0)
            layer:call(anim.CHANGE_SIG, bank, id, frame,
                msg["interp" .. i] or 0, msg["imode" .. i] or 0, msg["icurve" .. i] or 0)
            changes = changes + 1
        end
    end
    return changes
end

return anim
