-- re2r_coop/diag.lua
--
-- Diagnose fuer unsere Duo-Arbeit: Schreibt auf, welche Klassen, Manager,
-- Methoden und Felder es im Spiel wirklich gibt, wo der Spieler steht usw.
--
-- Ergebnis: <RE2-Ordner>/reframework/data/re2r_coop_diag_<situation>.json
-- -> diese Datei ins Repo unter games/re2r/research/ legen oder mir schicken.

local game = require("re2r_coop.game")

local diag = {}

diag.FILE_PREFIX = "re2r_coop_diag"

-- Klassen, die wir uns immer genau ansehen (ohne "app.ropeway."-Praefix).
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

-- Stichworte fuer die Klassensuche (nur mit Plugin moeglich). Daraus finden
-- wir z. B. die Bereichs-ID (Meilenstein 1) und wie das Spiel Figuren
-- erzeugt (Meilenstein 2).
diag.SEARCH_KEYWORDS = {
    "Area", "Map", "Location", "Scenario", "Flag", "Spawn", "Prefab",
    "Survivor", "Player", "Door", "Item", "Enemy", "Event", "Movie",
    "Save", "Flow", "Network", "Npc", "Actor", "Puppet", "Character",
}

-- Manager, deren Name eines dieser Worte enthaelt, beschreiben wir komplett.
diag.INTERESTING_SINGLETON_WORDS = {
    "Map", "Area", "Location", "Scenario", "Flow", "Player", "Survivor",
    "Scene", "Enemy", "Spawn", "Flag", "Door", "Item", "Npc", "Actor", "Character",
}

local MAX_MEMBERS = 400
local MAX_SEARCH_RESULTS = 300
local MAX_DESCRIBED_SINGLETONS = 40

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
    info.has_managed_singleton = safe(sdk.get_managed_singleton, full_name) ~= nil

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

-- Enum als Liste "wert = NAME" (JSON vertraegt keine luecken-/negativen
-- Zahlenschluessel).
local function list_enum(type_name)
    local names = game.enum_names(type_name)
    local values = {}
    for v in pairs(names) do
        values[#values + 1] = v
    end
    table.sort(values)
    local result = {}
    for _, v in ipairs(values) do
        result[#result + 1] = string.format("%d = %s", v, names[v])
    end
    return result
end

local function contains_any(text, words)
    local lower = text:lower()
    for _, w in ipairs(words) do
        if lower:find(w:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Komponenten eines GameObjects (z. B. Motion, CharacterController, ...).
-- Wichtig fuer Meilenstein 2: Was braucht eine Spielfigur alles?
local function list_components(game_object)
    local result = {}
    local components = safe(game_object.call, game_object, "get_Components")
    if components == nil then
        return result
    end
    local elements = safe(components.get_elements, components)
    if elements == nil then
        local size = safe(components.call, components, "get_Count")
            or safe(components.call, components, "get_Length") or 0
        elements = {}
        for i = 0, size - 1 do
            elements[#elements + 1] = safe(components.call, components, "Get", i)
        end
    end
    for _, comp in ipairs(elements) do
        local td = safe(comp.get_type_definition, comp)
        table.insert(result, type_name(td))
    end
    return result
end

-- Nur Buchstaben, Ziffern, - und _ im Dateinamen.
function diag.sanitize_label(label)
    label = tostring(label or ""):gsub("[^%w%-_]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return label:sub(1, 40)
end

function diag.filename(label)
    label = diag.sanitize_label(label)
    if label == "" then
        return diag.FILE_PREFIX .. ".json"
    end
    return diag.FILE_PREFIX .. "_" .. label .. ".json"
end

function diag.collect(extra)
    local result = {
        coopnet_version = coopnet and coopnet.version() or "Plugin fehlt",
        game_name = safe(function() return reframework:get_game_name() end),
        reframework_commit_count = safe(function() return reframework:get_commit_count() end),
        namespace = game.ns(""),
        research_available = coopnet ~= nil and coopnet.find_types ~= nil,
        types = {},
    }

    -- Spieler
    local player = game.get_player()
    result.player = {
        found = player ~= nil,
        source = game.player_source,
        object_name = player and game.get_name(player) or nil,
        state = game.get_local_state(),
        components = player and list_components(player) or nil,
        condition = game.get_condition_info(game.get_condition(player)),
    }

    -- Enums fuer Figur und Bereich (Werte -> Namen)
    result.enums = {}
    for _, name in ipairs({ game.ENUM_SURVIVOR_TYPE, game.ENUM_MAP_ID, game.ENUM_MAP_AREA,
        game.ENUM_PLAYER_TYPE, game.ENUM_LOCATION_ID }) do
        result.enums[name] = list_enum(name)
    end

    -- Feste Kandidaten
    for _, name in ipairs(diag.CANDIDATE_TYPES) do
        result.types[game.ns(name)] = describe_type(game.ns(name))
    end

    -- Erweiterte Forschung ueber das Plugin
    if result.research_available then
        local ns = game.ns("")

        local singletons = safe(coopnet.list_singletons) or {}
        result.singletons = singletons

        local described = 0
        for _, name in ipairs(singletons) do
            if described >= MAX_DESCRIBED_SINGLETONS then break end
            if name:sub(1, #ns) == ns and result.types[name] == nil
                and contains_any(name:sub(#ns + 1), diag.INTERESTING_SINGLETON_WORDS) then
                result.types[name] = describe_type(name)
                described = described + 1
            end
        end

        result.type_search = {}
        for _, word in ipairs(diag.SEARCH_KEYWORDS) do
            local hits = {}
            for _, name in ipairs(safe(coopnet.find_types, word, 5000) or {}) do
                if name:sub(1, #ns) == ns then
                    hits[#hits + 1] = name
                    if #hits >= MAX_SEARCH_RESULTS then break end
                end
            end
            result.type_search[word] = hits
        end
    end

    if extra then
        for k, v in pairs(extra) do
            result[k] = v
        end
    end
    return result
end

-- Schreibt die Diagnose-Datei. Gibt (true, pfad) oder (false, fehler) zurueck.
function diag.write(extra, label)
    local ok, data = pcall(diag.collect, extra)
    if not ok then
        return false, tostring(data)
    end
    data.label = label
    local file = diag.filename(label)
    if not json.dump_file(file, data) then
        return false, "json.dump_file fehlgeschlagen"
    end
    return true, "reframework/data/" .. file
end

return diag
