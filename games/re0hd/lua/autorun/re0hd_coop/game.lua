-- re0hd_coop/game.lua - Zugriff auf Spieldaten von RE0 HD.
--
-- Bestaetigt am 2. November 2026 fuer re0hd.exe mit Zeitstempel 0x6799D40F
-- (Details: games/re0hd/research/README.md). Andere exe-Versionen: Adressen
-- vermutlich anders, dann liefern die Funktionen nil.

local game = {
    ID = "re0hd",
    -- Figur-IDs fuer PLAYER_STATE.character (unsere eigene Nummerierung)
    CHARACTERS = { [1] = "Rebecca", [2] = "Billy" },
}

local EXE_TIMESTAMP = 0x6799D40F
local SPLAYER_INSTANCE = 0x00DCBF3C -- statischer Zeiger auf sPlayer
local OFF_ACTIVE = 0x2C              -- sPlayer: gesteuerte Figur
local OFF_PARTNER = 0x3C             -- sPlayer: Partner
local OFF_POS = 0x40                 -- Figur: Position (x, y, z)
local OFF_QUAT = 0x50                -- Figur: Drehung (x, y, z, w)

game.supported = remods ~= nil and remods.exe_timestamp == EXE_TIMESTAMP

local CLASS_TO_CHARACTER = { uPlayerRebecca = 1, uPlayerBilly = 2 }

local function player_manager()
    if not game.supported then
        return nil
    end
    local sp = mem.read_u32(SPLAYER_INSTANCE)
    if not sp or sp == 0 then
        return nil
    end
    return sp
end

local function character_at(offset)
    local sp = player_manager()
    if not sp then
        return nil
    end
    local obj = mem.read_u32(sp + offset)
    if not obj or obj == 0 then
        return nil
    end
    return obj
end

function game.active_object()
    return character_at(OFF_ACTIVE)
end

function game.partner_object()
    return character_at(OFF_PARTNER)
end

-- Zustand einer Figur: { x, y, z, qx, qy, qz, qw, character } oder nil
function game.read_state(obj)
    if not obj then
        return nil
    end
    local x = mem.read_f32(obj + OFF_POS)
    if x == nil then
        return nil
    end
    local class = mt and mt.class_of(obj)
    return {
        x = x, y = mem.read_f32(obj + OFF_POS + 4), z = mem.read_f32(obj + OFF_POS + 8),
        qx = mem.read_f32(obj + OFF_QUAT), qy = mem.read_f32(obj + OFF_QUAT + 4),
        qz = mem.read_f32(obj + OFF_QUAT + 8), qw = mem.read_f32(obj + OFF_QUAT + 12),
        character = CLASS_TO_CHARACTER[class] or 0,
        class = class,
    }
end

-- Zustand des lokalen Spielers fuer PLAYER_STATE
function game.get_local_state()
    return game.read_state(game.active_object())
end

-- Partner an eine Position/Drehung setzen (jeden Frame aufrufen, sonst laeuft die KI weiter)
function game.place_partner(s)
    local obj = game.partner_object()
    if not obj or not s then
        return false
    end
    mem.write_f32(obj + OFF_POS, s.x)
    mem.write_f32(obj + OFF_POS + 4, s.y)
    mem.write_f32(obj + OFF_POS + 8, s.z)
    if s.qw then
        mem.write_f32(obj + OFF_QUAT, s.qx or 0)
        mem.write_f32(obj + OFF_QUAT + 4, s.qy or 0)
        mem.write_f32(obj + OFF_QUAT + 8, s.qz or 0)
        mem.write_f32(obj + OFF_QUAT + 12, s.qw)
    end
    return true
end

return game
