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
local GAMECAMERA_INSTANCE = 0x00E2D6BC -- statischer Zeiger auf sGameCamera
local OFF_CAMERA = 0x34                -- sGameCamera: aktive Kamera (uGameFreeCamera)
local OFF_CAM_POS = 0x40               -- Kamera: Position
local OFF_CAM_TARGET = 0x60            -- Kamera: Blickpunkt
local GAMEAREA_INSTANCE = 0x00E2D8C0   -- statischer Zeiger auf sGameArea
local OFF_ROOM = 0x3834                -- sGameArea: aktueller Raum (aRoomXxNN)

-- Partner-Tasten (DIK-Codes, Standardbelegung KC_partner* = Pfeiltasten).
-- Sie wirken relativ zur Kamera: hoch = vom Betrachter weg.
game.PARTNER_KEYS = { up = 0xC8, down = 0xD0, left = 0xCB, right = 0xCD }

game.supported = remultiplayer ~= nil and remultiplayer.exe_timestamp == EXE_TIMESTAMP

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

-- Aktueller Raum als Kennung wie "Tr04" (Klasse aRoomTr04 ohne "aRoom") oder nil.
-- Das Raum-Objekt bleibt an derselben Adresse, beim Raumwechsel aendert sich
-- seine Klasse (vtable). Deshalb wird die Kennung pro vtable zwischengespeichert.
local room_cache = { vtable = nil, id = nil }
function game.room_id()
    if not game.supported or not mt then
        return nil
    end
    local ga = mem.read_u32(GAMEAREA_INSTANCE)
    local room = ga and ga ~= 0 and mem.read_u32(ga + OFF_ROOM)
    local vtable = room and room ~= 0 and mem.read_u32(room)
    if not vtable or vtable == 0 then
        return nil
    end
    if vtable ~= room_cache.vtable then
        local class = mt.class_of(room)
        room_cache.vtable = vtable
        room_cache.id = class and class:match("^aRoom(%w+)$") or nil
    end
    return room_cache.id
end

-- Sind beide im selben Raum? true/false, oder nil, wenn ein Raum unbekannt ist
-- ("" = Mitspieler kennt seinen Raum nicht)
function game.same_room(a, b)
    if a == nil or b == nil or a == "" or b == "" then
        return nil
    end
    return a == b
end

-- Zustand des lokalen Spielers fuer PLAYER_STATE (mit Raum in .area)
function game.get_local_state()
    local s = game.read_state(game.active_object())
    if s then
        s.area = game.room_id()
    end
    return s
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

-- Blickrichtung der Kamera in der Ebene (Winkel wie bei der Figur: atan(dx, dz)) oder nil
function game.camera_heading()
    if not game.supported then
        return nil
    end
    local gc = mem.read_u32(GAMECAMERA_INSTANCE)
    local cam = gc and gc ~= 0 and mem.read_u32(gc + OFF_CAMERA)
    if not cam or cam == 0 then
        return nil
    end
    local px, pz = mem.read_f32(cam + OFF_CAM_POS), mem.read_f32(cam + OFF_CAM_POS + 8)
    local tx, tz = mem.read_f32(cam + OFF_CAM_TARGET), mem.read_f32(cam + OFF_CAM_TARGET + 8)
    if not (px and pz and tx and tz) then
        return nil
    end
    return math.atan(tx - px, tz - pz)
end

-- Partner-Taste druecken/loslassen (ueber den DirectInput-Hook der Runtime)
function game.set_partner_key(name, down)
    if input and input.set_key then
        input.set_key(game.PARTNER_KEYS[name], down)
    end
end

return game
