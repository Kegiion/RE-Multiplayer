-- re2r_coop/ghost.lua
--
-- Meilenstein 1: Mitspieler als "Geist" anzeigen - eine Markierung mit Name
-- und Entfernung an seiner Position. Noch keine echte Spielfigur; die kommt
-- in Meilenstein 2, sobald die Positionsdaten zuverlaessig fliessen.

local ghost = {}

-- remote[peer_id] = { name=, target={...}, pos={x,y,z}, seq=, last_update=, area=, character= }
ghost.remote = {}

-- Optional: Funktion Figur-ID -> Anzeigename (setzt das Spielskript).
ghost.character_name = nil

local STALE_AFTER = 2.0     -- Sekunden ohne Update -> grau anzeigen
local SMOOTHING = 12.0      -- hoeher = schneller an Zielposition
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
        r = { pos = { x = msg.x, y = msg.y, z = msg.z } }
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

-- Jeden Frame aufrufen: Position weich nachziehen (gegen Ruckeln).
function ghost.update(dt)
    local alpha = 1.0 - math.exp(-SMOOTHING * math.max(dt, 0))
    for _, r in pairs(ghost.remote) do
        local t = r.target
        if t ~= nil then
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
