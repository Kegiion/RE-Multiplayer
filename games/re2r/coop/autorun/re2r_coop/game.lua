-- re2r_coop/game.lua
--
-- RE2-Remake-spezifischer Zugriff auf Spieldaten ("Adapter"). Alles, was
-- Klassen- oder Methodennamen des Spiels kennt, gehoert hier hinein. Andere
-- RE-Engine-Spiele bekommen spaeter eine eigene game.lua mit gleicher
-- Schnittstelle.
--
-- STATUS: Die Namen unten sind noch NICHT im Spiel bestaetigt. Der
-- Diagnose-Button im Menue schreibt auf, was wirklich existiert.

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

-- Figuren-IDs fuer PLAYER_STATE.character. Wird ergaenzt, sobald wir die
-- GameObject-Namen der Figuren per Diagnose kennen.
game.CHARACTERS = {
    [0] = "?",
}

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

-- Kennung des aktuellen Bereichs. Damit zeigen wir den Mitspieler spaeter
-- nur an, wenn er im selben Bereich ist.
-- TODO: Richtige Quelle per Diagnose finden (Kandidaten siehe diag.lua).
function game.get_area()
    return ""
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
    return {
        x = pos.x, y = pos.y, z = pos.z,
        qx = rot.x, qy = rot.y, qz = rot.z, qw = rot.w,
        area = game.get_area(),
        character = 0,
        flags = 0,
        object_name = game.get_name(player),
    }
end

return game
