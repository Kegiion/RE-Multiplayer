-- re2r_coop/game.lua
--
-- RE2-Remake-spezifischer Zugriff auf Spieldaten ("Adapter"). Alles, was
-- Klassen- oder Methodennamen des Spiels kennt, gehoert hier hinein. Andere
-- RE-Engine-Spiele bekommen spaeter eine eigene game.lua mit gleicher
-- Schnittstelle.
--
-- STATUS (Test im Spiel am 2. November 2026, Entwickler-Konsole):
--   bestaetigt: PlayerManager.get_CurrentPlayer -> GameObject "pl0000",
--               Transform-Position/-Rotation,
--               PlayerCondition.get_SurvivorType = 0 ("PL0000") fuer Leon,
--               PlayerCondition.get_StaySceneAreaID liefert Map.ID
--               (Tankstelle: st1_411_0). Map.ID ist eine Zone, kein Raum:
--               die Tuer in der Tankstelle bleibt in derselben Zone.
--               Zonenwechsel Tankstelle -> st8_410_0 -> st4_201_0 ->
--               st4_101_0 (Polizeistation) beobachtet. In Zwischensequenzen
--               ist die Zone kurz "Invalid" und die Position springt.
--   UNBESTAETIGT: Namen der anderen Figuren.

local game = {}

game.ID = "re2r"

-- RE2R nutzt den Namespace "app.ropeway." (RE3R uebrigens auch).
local function ns(name)
    if sdk.game_namespace then
        return sdk.game_namespace(name)
    end
    return "app.ropeway." .. name
end
game.ns = ns

-- Enum-Typen, deren Namen wir zur Laufzeit aus dem Spiel lesen.
game.ENUM_SURVIVOR_TYPE = ns("SurvivorDefine.SurvivorType")
game.ENUM_MAP_ID = ns("gamemastering.Map.ID")
game.ENUM_MAP_AREA = ns("gamemastering.Map.Area")
game.ENUM_PLAYER_TYPE = ns("PlayerDefine.PlayerType")
game.ENUM_LOCATION_ID = ns("gamemastering.Location.ID")

-- SurvivorType-Namen (aus dem Spiel) -> Anzeigename.
game.CHARACTER_NAMES = {
    PL0000 = "Leon",   -- bestaetigt 2. November 2026
    PL1000 = "Claire", -- UNBESTAETIGT
}

-- PLAYER_STATE.character ist ein Byte. Werte ausserhalb 0..254 senden wir
-- als 255 ("unbekannt").
game.CHARACTER_UNKNOWN = 255

-- Wie wir den Spieler gefunden haben (fuer UI/Diagnose).
game.player_source = nil

local function try_call(obj, method, ...)
    if obj == nil then
        return nil
    end
    local ok, result = pcall(obj.call, obj, method, ...)
    if ok then
        return result
    end
    return nil
end
game.try_call = try_call

-- Liefert das GameObject (via.GameObject) des lokalen Spielers oder nil
-- (z. B. im Hauptmenue oder waehrend Ladebildschirmen).
function game.get_player()
    local pm = sdk.get_managed_singleton(ns("PlayerManager"))
    if pm ~= nil then
        local player = try_call(pm, "get_CurrentPlayer")
        if player ~= nil then
            game.player_source = "PlayerManager.get_CurrentPlayer"
            return player
        end
    end
    game.player_source = nil
    return nil
end

function game.get_transform(game_object)
    return try_call(game_object, "get_Transform")
end

function game.get_name(game_object)
    return try_call(game_object, "get_Name")
end

-- Enum-Wert -> Name, gelesen aus den statischen Feldern der Enum-Klasse.
-- Ergebnis wird pro Typ gecacht (die Typdatenbank aendert sich nicht).
local enum_cache = {}

function game.enum_names(type_name)
    local names = enum_cache[type_name]
    if names ~= nil then
        return names
    end
    names = {}
    local td = sdk.find_type_definition(type_name)
    local ok, fields = pcall(function() return td:get_fields() end)
    for _, f in ipairs(ok and fields or {}) do
        local ok_static, is_static = pcall(f.is_static, f)
        if ok_static and is_static then
            local ok_data, value = pcall(f.get_data, f, nil)
            if ok_data and type(value) == "number" then
                names[value] = f:get_name()
            end
        end
    end
    enum_cache[type_name] = names
    return names
end

-- Name zu einem Enum-Wert, "#<zahl>" wenn unbekannt, "" ohne Wert.
function game.enum_name(type_name, value)
    if type(value) ~= "number" then
        return ""
    end
    return game.enum_names(type_name)[value] or ("#" .. tostring(value))
end

-- PlayerCondition-Komponente des Spielers (Figur, Bereich, Zustand).
function game.get_condition(player)
    if player == nil or sdk.typeof == nil then
        return nil
    end
    local t = sdk.typeof(ns("survivor.player.PlayerCondition"))
    if t == nil then
        return nil
    end
    return try_call(player, "getComponent(System.Type)", t)
end

-- Rohwerte aus PlayerCondition (fuer Debug-Anzeige und Diagnose).
-- UNBESTAETIGT, welche der beiden Bereichs-IDs beim Tuerwechsel zuverlaessig
-- wechselt. Wir nutzen vorerst StaySceneAreaID.
function game.get_condition_info(condition)
    if condition == nil then
        return nil
    end
    local info = {
        survivor_type = try_call(condition, "get_SurvivorType"),
        scene_area_id = try_call(condition, "get_StaySceneAreaID"),
        space_area_id = try_call(condition, "get_StaySpaceAreaID"),
        map_area = try_call(condition, "get_StaySceneMapArea"),
    }
    info.survivor_name = game.enum_name(game.ENUM_SURVIVOR_TYPE, info.survivor_type)
    info.scene_area_name = game.enum_name(game.ENUM_MAP_ID, info.scene_area_id)
    info.space_area_name = game.enum_name(game.ENUM_MAP_ID, info.space_area_id)
    info.map_area_name = game.enum_name(game.ENUM_MAP_AREA, info.map_area)
    return info
end

-- Kennung des aktuellen Bereichs (Name aus Map.ID). Damit erkennen wir, ob
-- der Mitspieler im selben Bereich ist. "" = unbekannt (auch waehrend
-- Zwischensequenzen, dort meldet das Spiel "Invalid").
function game.get_area(info)
    local name = info and info.scene_area_name or ""
    if name == "Invalid" then
        return ""
    end
    return name
end

-- Figur als Byte fuer PLAYER_STATE.character (Wert aus SurvivorType).
function game.get_character(info)
    local value = info and info.survivor_type
    if type(value) ~= "number" or value < 0 or value >= game.CHARACTER_UNKNOWN then
        return game.CHARACTER_UNKNOWN
    end
    return math.floor(value)
end

function game.character_name(value)
    if value == nil or value == game.CHARACTER_UNKNOWN then
        return "?"
    end
    local name = game.enum_name(game.ENUM_SURVIVOR_TYPE, value)
    return game.CHARACTER_NAMES[name] or name
end

-- Liest den Zustand des lokalen Spielers. Gibt nil zurueck, wenn es (gerade)
-- keinen Spieler gibt.
function game.get_local_state()
    local player = game.get_player()
    if player == nil then
        return nil
    end
    local transform = game.get_transform(player)
    if transform == nil then
        return nil
    end
    local pos = try_call(transform, "get_Position")
    local rot = try_call(transform, "get_Rotation")
    if pos == nil or rot == nil then
        return nil
    end
    local info = game.get_condition_info(game.get_condition(player))
    return {
        x = pos.x, y = pos.y, z = pos.z,
        qx = rot.x, qy = rot.y, qz = rot.z, qw = rot.w,
        area = game.get_area(info),
        character = game.get_character(info),
        flags = 0,
        object_name = game.get_name(player),
        condition = info,
    }
end

-- --- Spielsprache (fuer remultiplayer_coop.i18n, Einstellung "Automatisch") ---
--
-- Forschungspunkt L1 "Wo speichert RE2 die Spielsprache?":
-- native Singleton via.gui.GUISystem, get_MessageLanguage (Textsprache, Enum
-- via.Language). Bestaetigt am 4. November 2026 (Konsole, RT-Version):
-- deutscher Spieltext -> 4. get_SubtitleLanguage/get_SpeechLanguage gibt es
-- so nicht (nil). UNBESTAETIGT: alle anderen Werte (1 = Englisch erwartet).
-- Nur bestaetigte Werte werden benutzt, alles andere -> nil -> Englisch.
-- Pruefen ueber die Entwickler-Konsole: out(game.read_game_language_raw())
game.LANGUAGE_CONFIRMED = { [4] = true }

-- via.Language -> Sprachcode (nur 4 bestaetigt, Rest aus anderen RE-Engine-Mods)
game.LANGUAGE_CODES = {
    [0] = "ja", [1] = "en", [2] = "fr", [3] = "it", [4] = "de", [5] = "es",
    [6] = "ru", [7] = "pl", [8] = "nl", [9] = "pt", [10] = "pt-br",
    [11] = "ko", [12] = "zh-hant", [13] = "zh-hans",
}

-- Rohwert der Spielsprache (Zahl) oder nil, err. Nur fuer die Forschung.
function game.read_game_language_raw()
    local ok, value = pcall(function()
        local gui = sdk.get_native_singleton("via.gui.GUISystem")
        if gui == nil then
            return nil
        end
        return sdk.call_native_func(gui, sdk.find_type_definition("via.gui.GUISystem"), "get_MessageLanguage")
    end)
    if not ok then
        return nil, tostring(value)
    end
    return value
end

-- Sprachcode der Spielsprache ("de", "en", ...) oder nil, wenn unbekannt.
function game.get_game_language()
    local raw = tonumber((game.read_game_language_raw()))
    if raw == nil or not game.LANGUAGE_CONFIRMED[raw] then
        return nil
    end
    return game.LANGUAGE_CODES[raw]
end

return game
