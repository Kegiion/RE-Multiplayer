-- re2r_coop/ghost.lua
--
-- Meilenstein 1: Mitspieler als "Geist" anzeigen - eine Markierung mit Name
-- und Entfernung an seiner Position. Noch keine echte Spielfigur; die kommt
-- in Meilenstein 2, sobald die Positionsdaten zuverlaessig fliessen.

local ghost = {}

-- remote[peer_id] = { name=, target={...}, pos={x,y,z}, rot={x,y,z,w}, seq=, last_update=, area=, character= }
ghost.remote = {}

-- Optional: Funktion Figur-ID -> Anzeigename (setzt das Spielskript).
ghost.character_name = nil

local STALE_AFTER = 2.0     -- Sekunden ohne Update -> grau anzeigen
local SMOOTHING = 12.0      -- hoeher = schneller an Zielposition
local ROT_SMOOTHING = 15.0  -- dasselbe fuer die Drehung (Updates kommen nur 20x pro Sekunde)
local HEAD_HEIGHT = 1.8     -- Meter ueber den Fuessen fuer das Namensschild

local COLOR_ACTIVE = 0xFF40E0FF  -- ABGR: gelb-orange
local COLOR_STALE = 0xFF808080
local COLOR_SHADOW = 0xC0000000

-- seq-Vergleich mit Ueberlauf (uint32).
local function is_newer(seq, last)
    if last == nil then
        return true
    end
    local diff = (seq - last) % 4294967296
    return diff ~= 0 and diff < 2147483648
end

function ghost.on_state(peer, msg, now)
    local r = ghost.remote[peer.id]
    if r == nil then
        r = { pos = { x = msg.x, y = msg.y, z = msg.z }, rot = { x = msg.qx, y = msg.qy, z = msg.qz, w = msg.qw } }
        ghost.remote[peer.id] = r
    elseif not is_newer(msg.seq, r.seq) then
        return -- veraltetes Paket (UDP kann Reihenfolge vertauschen)
    end
    r.name = peer.name or ("Peer " .. peer.id)
    r.seq = msg.seq
    r.target = msg
    r.area = msg.area
    r.character = msg.character
    r.last_update = now
end

function ghost.remove(peer_id)
    ghost.remote[peer_id] = nil
end

function ghost.clear()
    ghost.remote = {}
end

-- Drehung q weich Richtung Ziel t ziehen (normalisierte lineare Interpolation
-- auf dem kuerzeren Weg). Ungueltige Ziele (Laenge 0) werden ignoriert.
local function nlerp(q, t, alpha)
    local tx, ty, tz, tw = t.qx or 0, t.qy or 0, t.qz or 0, t.qw or 1
    if q.x * tx + q.y * ty + q.z * tz + q.w * tw < 0 then
        tx, ty, tz, tw = -tx, -ty, -tz, -tw
    end
    local x, y, z, w = q.x + (tx - q.x) * alpha, q.y + (ty - q.y) * alpha, q.z + (tz - q.z) * alpha, q.w + (tw - q.w) * alpha
    local len = math.sqrt(x * x + y * y + z * z + w * w)
    if len < 1e-6 then
        return
    end
    q.x, q.y, q.z, q.w = x / len, y / len, z / len, w / len
end
ghost.nlerp = nlerp

-- Jeden Frame aufrufen: Position und Drehung weich nachziehen (gegen Ruckeln).
function ghost.update(dt)
    local alpha = 1.0 - math.exp(-SMOOTHING * math.max(dt, 0))
    local rot_alpha = 1.0 - math.exp(-ROT_SMOOTHING * math.max(dt, 0))
    for _, r in pairs(ghost.remote) do
        local t = r.target
        if t ~= nil then
            if r.rot == nil then
                r.rot = { x = t.qx or 0, y = t.qy or 0, z = t.qz or 0, w = t.qw or 1 }
            else
                nlerp(r.rot, t, rot_alpha)
            end
            local dx, dy, dz = t.x - r.pos.x, t.y - r.pos.y, t.z - r.pos.z
            -- Bei grossen Spruengen (Raumwechsel, Teleport) direkt setzen.
            if dx * dx + dy * dy + dz * dz > 25 then
                r.pos.x, r.pos.y, r.pos.z = t.x, t.y, t.z
            else
                r.pos.x = r.pos.x + dx * alpha
                r.pos.y = r.pos.y + dy * alpha
                r.pos.z = r.pos.z + dz * alpha
            end
        end
    end
end

function ghost.is_stale(r, now)
    return r.last_update == nil or (now - r.last_update) > STALE_AFTER
end

-- true, wenn beide Bereiche bekannt sind und sich unterscheiden.
function ghost.other_area(r, local_state)
    return local_state ~= nil and r.area ~= nil and r.area ~= ""
        and local_state.area ~= nil and local_state.area ~= "" and r.area ~= local_state.area
end

local function shadow_text(text, x, y, color)
    draw.text(text, x + 1, y + 1, COLOR_SHADOW)
    draw.text(text, x, y, color)
end

-- Muss in re.on_frame aufgerufen werden (nur dort funktioniert draw.*).
function ghost.draw(local_state, now)
    for _, r in pairs(ghost.remote) do
        local stale = ghost.is_stale(r, now)
        local color = stale and COLOR_STALE or COLOR_ACTIVE

        local feet = draw.world_to_screen(Vector3f.new(r.pos.x, r.pos.y, r.pos.z))
        local head = draw.world_to_screen(Vector3f.new(r.pos.x, r.pos.y + HEAD_HEIGHT, r.pos.z))

        if feet ~= nil then
            draw.outline_circle(feet.x, feet.y, 12, color, 24)
        end
        if feet ~= nil and head ~= nil then
            draw.line(feet.x, feet.y, head.x, head.y, color)
        end
        if head ~= nil then
            local label = r.name
            if ghost.character_name ~= nil and r.character ~= nil then
                label = string.format("%s [%s]", label, ghost.character_name(r.character))
            end
            if local_state ~= nil then
                local dx, dy, dz = r.pos.x - local_state.x, r.pos.y - local_state.y, r.pos.z - local_state.z
                label = string.format("%s  %.1fm", label, math.sqrt(dx * dx + dy * dy + dz * dz))
            end
            if stale then
                label = label .. "  (keine Daten)"
            elseif ghost.other_area(r, local_state) then
                label = label .. "  (anderer Bereich: " .. r.area .. ")"
            end
            shadow_text(label, head.x - 4 * #label, head.y - 18, color)
        end
    end
end

return ghost
