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
game.CHANGE_KEY = 0x2F -- V (KC_change, Standardbelegung): Figur wechseln

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

-- ---- Spielstaende -------------------------------------------------------------
-- Bestaetigt am 3. November 2026 (Programmcode und Test im Spiel, Details in
-- games/re0hd/research/README.md): sSaveManager + 20 -> cSaveManager. Dort liegen
-- zwei unverschluesselte Abbilder der Spielstand-Datei data0.bin:
--   +23A718 Datei-Abbild (wird beim Laden aus der Datei gelesen, beim Speichern geschrieben)
--   +18     zuletzt uebernommener Stand
-- In beiden: +B0 + Platz * 1C850 = Platz (0..19, im Menue 1..20).
-- Beim Spielstart uebernimmt das Spiel den Platz aus dem Datei-Abbild (0x6127D0).
local SAVEMANAGER_INSTANCE = 0x00DCC018 -- statischer Zeiger auf sSaveManager
local OFF_SAVE_CURRENT = 0x24           -- sSaveManager: zuletzt geladener/gespeicherter Platz
local OFF_CSAVEMANAGER = 0x20
local SAVE_IMAGES = { 0x23A718, 0x18 }
local OFF_SLOTS = 0xB0
local GAMEINFO_INSTANCE = 0x00DCBE9C    -- statischer Zeiger auf sGameInfo
local OFF_PLAYTIME = 0x3C               -- sGameInfo: Spielzeit in Bildern (60 pro Sekunde)

game.SAVE_SLOT_SIZE = 0x1C850
game.SAVE_SLOTS = 20

local function save_manager()
    if not game.supported then
        return nil
    end
    local ssm = mem.read_u32(SAVEMANAGER_INSTANCE)
    if not ssm or ssm == 0 then
        return nil
    end
    local csm = mem.read_u32(ssm + OFF_CSAVEMANAGER)
    if not csm or csm == 0 then
        return nil
    end
    return ssm, csm
end

local function slot_address(csm, image, slot)
    return csm + image + OFF_SLOTS + slot * game.SAVE_SLOT_SIZE
end

-- Zuletzt geladener bzw. gespeicherter Platz (0-basiert) oder nil
function game.current_save_slot()
    local ssm = save_manager()
    local slot = ssm and mem.read_u32(ssm + OFF_SAVE_CURRENT)
    if slot and slot < game.SAVE_SLOTS then
        return slot
    end
    return nil
end

-- Platz als String (aus dem Datei-Abbild) oder nil
function game.read_save_slot(slot)
    local _, csm = save_manager()
    if not csm or not mem.read_bytes then
        return nil
    end
    local data = mem.read_bytes(slot_address(csm, SAVE_IMAGES[1], slot), game.SAVE_SLOT_SIZE)
    if not data or string.unpack("<I4", data, 5) & 0xFF == 0 then
        return nil -- leerer Platz
    end
    return data
end

-- Platz in beiden Abbildern ueberschreiben (nur im Speicher)
function game.write_save_slot(slot, data)
    local _, csm = save_manager()
    if not csm or not mem.write_bytes or #data ~= game.SAVE_SLOT_SIZE then
        return false
    end
    local ok = true
    for _, image in ipairs(SAVE_IMAGES) do
        ok = mem.write_bytes(slot_address(csm, image, slot), data) and ok
    end
    return ok
end

-- Stimmt der Platz in beiden Abbildern (Kopf und Spielzeit) mit data ueberein?
function game.save_slot_matches(slot, data)
    local _, csm = save_manager()
    if not csm then
        return false
    end
    local head = data:sub(1, 0x20)
    for _, image in ipairs(SAVE_IMAGES) do
        if mem.read_bytes(slot_address(csm, image, slot), 0x20) ~= head then
            return false
        end
    end
    return true
end

-- Kurzbeschreibung eines Platzes: Anzahl Speicherungen und Spielzeit
function game.describe_save(data)
    local count = string.unpack("<I4", data, 0x18 + 1)
    local frames = string.unpack("<f", data, 0x1C + 1)
    local minutes = math.floor(frames / 3600)
    return string.format("%d. Speicherung, Spielzeit %d:%02d", count, minutes // 60, minutes % 60)
end

-- Laufende Spielzeit in Bildern oder nil
function game.playtime()
    if not game.supported then
        return nil
    end
    local gi = mem.read_u32(GAMEINFO_INSTANCE)
    return gi and gi ~= 0 and mem.read_f32(gi + OFF_PLAYTIME) or nil
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

-- Partner verstecken: so tief unter den Boden setzen, dass er nicht zu sehen ist
-- (im Spiel bestaetigt am 3. November 2026: unsichtbar, kommt danach sauber zurueck).
-- Jeden Frame aufrufen, sonst holt ihn die KI zurueck.
game.HIDE_DEPTH = 3000
function game.hide_partner(x, y, z)
    return game.place_partner({ x = x, y = y - game.HIDE_DEPTH, z = z })
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

-- Taste "Figur wechseln" druecken/loslassen
function game.set_change_key(down)
    if input and input.set_key then
        input.set_key(game.CHANGE_KEY, down)
    end
end

-- Partner-Taste druecken/loslassen (ueber den DirectInput-Hook der Runtime)
function game.set_partner_key(name, down)
    if input and input.set_key then
        input.set_key(game.PARTNER_KEYS[name], down)
    end
end

return game
