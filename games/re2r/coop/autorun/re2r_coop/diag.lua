-- re2r_coop/diag.lua
--
-- Diagnose fuer unsere Duo-Arbeit: Schreibt auf, welche Klassen, Methoden
-- und Felder es im Spiel wirklich gibt, wo der Spieler steht usw.
--
-- Ergebnis: <RE2-Ordner>/reframework/data/re2r_coop_diag.json
-- -> diese Datei ins Repo unter games/re2r/research/ legen oder mir schicken.

local game = require("re2r_coop.game")

local diag = {}

diag.FILE = "re2r_coop_diag.json"

-- Klassen, die wir uns ansehen wollen (ohne "app.ropeway."-Praefix).
-- Nicht vorhandene werden einfach als "nicht gefunden" vermerkt.
diag.CANDIDATE_TYPES = {
    "PlayerManager",
    "EnemyManager",
    "SurvivorManager",
    "gamemastering.MainFlowManager",
    "gamemastering.MapManager",
    "gamemastering.LocationManager",
    "gamemastering.SceneLoadManager",
    "gamemastering.UIMapManager",
    "gamemastering.InventoryManager",
    "gamemastering.ItemManager",
    "survivor.SurvivorCondition",
    "survivor.player.PlayerCondition",
    "MapAreaDefineTable",
    "camera.CameraSystem",
    "gui.GUIMaster",
}

local MAX_MEMBERS = 400

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function type_name(td)
    return td and safe(td.get_full_name, td) or "?"
end

local function describe_type(full_name)
    local td = sdk.find_type_definition(full_name)
    if td == nil then
        return { found = false }
    end

    local info = { found = true, methods = {}, fields = {} }
    info.parent = type_name(safe(td.get_parent_type, td))
    info.has_managed_singleton = sdk.get_managed_singleton(full_name) ~= nil

    for i, m in ipairs(safe(td.get_methods, td) or {}) do
        if i > MAX_MEMBERS then break end
        table.insert(info.methods, string.format("%s%s(%d) -> %s",
            safe(m.is_static, m) and "static " or "",
            safe(m.get_name, m) or "?",
            safe(m.get_num_params, m) or -1,
            type_name(safe(m.get_return_type, m))))
    end
    for i, f in ipairs(safe(td.get_fields, td) or {}) do
        if i > MAX_MEMBERS then break end
        table.insert(info.fields, string.format("%s%s : %s",
            safe(f.is_static, f) and "static " or "",
            safe(f.get_name, f) or "?",
            type_name(safe(f.get_type, f))))
    end
    return info
end

function diag.collect(extra)
    local result = {
        coopnet_version = coopnet and coopnet.version() or "Plugin fehlt",
        game_name = safe(function() return reframework:get_game_name() end),
        reframework_commit_count = safe(function() return reframework:get_commit_count() end),
        namespace = game.ns(""),
        types = {},
    }

    local player = game.get_player()
    result.player = {
        found = player ~= nil,
        source = game.player_source,
        object_name = player and game.get_name(player) or nil,
        state = game.get_local_state(),
    }

    for _, name in ipairs(diag.CANDIDATE_TYPES) do
        result.types[game.ns(name)] = describe_type(game.ns(name))
    end

    if extra then
        for k, v in pairs(extra) do
            result[k] = v
        end
    end
    return result
end

-- Schreibt die Diagnose-Datei. Gibt (true, dateiname) oder (false, fehler) zurueck.
function diag.write(extra)
    local ok, data = pcall(diag.collect, extra)
    if not ok then
        return false, tostring(data)
    end
    if not json.dump_file(diag.FILE, data) then
        return false, "json.dump_file fehlgeschlagen"
    end
    return true, "reframework/data/" .. diag.FILE
end

return diag
