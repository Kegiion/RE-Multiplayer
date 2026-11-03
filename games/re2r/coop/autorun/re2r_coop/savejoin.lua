-- re2r_coop/savejoin.lua
--
-- Join auf den Spielstand des Hosts. Der Freund fragt mit SAVE_REQUEST an,
-- der Host sammelt seinen Live-Stand ein (savestate.capture_live), wandelt ihn
-- in Bytes (remultiplayer_coop.serial) und schickt ihn in Stuecken
-- (SAVE_BEGIN/SAVE_CHUNK, remultiplayer_coop.transfer). Der Freund laedt danach
-- einen beliebigen eigenen Spielstand, beim Laden wird der Stand des Hosts auf
-- die frisch eingelesenen Objekte gespielt (Pre-Hook auf
-- SaveDataManager.loadGameSaveData, savestate.apply_to_list).
--
-- Bestaetigt am 3. November 2026 ohne Netzwerk (gleicher PC): Live-Stand der
-- Eingangshalle beim Laden der Strasse eingespielt -> Spieler steht exakt dort.
-- UNBESTAETIGT: Uebertragung zwischen zwei PCs, Spielstaende verschiedener
-- Konten, Raetsel-Daten generischer Typen (siehe research/README.md).

local transfer = require("remultiplayer_coop.transfer")
local serial = require("remultiplayer_coop.serial")
local savestate = require("re2r_coop.savestate")
local game = require("re2r_coop.game")

local M = {}

M.CHUNKS_PER_FRAME = 8     -- Host: so viele Stuecke je Frame senden (8 KB je Stueck)

-- Zustand beim Freund:
--   idle -> requested -> receiving -> ready (Stand liegt bereit, Laden abwarten)
--   -> applied | failed
M.state = "idle"
M.message = ""
M.receiver = nil
M.pending = nil      -- Teile, die beim naechsten Laden eingespielt werden
M.result = nil       -- stats/errors des letzten Einspielens

-- Host: laufende Sendungen { peer=, begin=, chunks=, next= }
M.outgoing = {}

-- Austauschbar fuer Tests.
M.capture = function()
    return savestate.capture_live()
end
M.apply = function(list, parts)
    return savestate.apply_to_list(list, parts)
end

local next_transfer = os.time() % 100000

-- Beschreibung des Host-Stands fuer die Anzeige beim Freund.
local function describe()
    local ok, ls = pcall(game.get_local_state)
    if not ok or ls == nil then
        return ""
    end
    return string.format("%s, %s", game.character_name(ls.character), tostring(ls.area))
end

-- --- Host --------------------------------------------------------------------

function M.on_request(session, peer)
    local ok, parts = pcall(M.capture)
    if not ok then
        session:log("Spielstand fuer %s nicht einsammelbar: %s", peer.name or "?", tostring(parts))
        session:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = "Host hat keinen Spielstand" }, true, peer.id)
        return
    end
    local data = serial.encode(parts)
    next_transfer = (next_transfer + 1) % 4294967296
    local begin, chunks = transfer.split(data, next_transfer, describe())
    session:send("SAVE_BEGIN", begin, true, peer.id)
    M.outgoing[#M.outgoing + 1] = { peer = peer.id, begin = begin, chunks = chunks, next = 1 }
    session:log("Sende Spielstand an %s (%d KB, %s)", peer.name or "?", #data // 1024, begin.info)
end

-- Jeden Frame: ausstehende Stuecke verteilt senden.
function M.update(session)
    for i = #M.outgoing, 1, -1 do
        local out = M.outgoing[i]
        for _ = 1, M.CHUNKS_PER_FRAME do
            local c = out.chunks[out.next]
            if c == nil then
                break
            end
            session:send("SAVE_CHUNK", c, true, out.peer)
            out.next = out.next + 1
        end
        if out.next > #out.chunks then
            table.remove(M.outgoing, i)
        end
    end
end

function M.forget_peer(peer_id)
    for i = #M.outgoing, 1, -1 do
        if M.outgoing[i].peer == peer_id then
            table.remove(M.outgoing, i)
        end
    end
end

-- --- Freund ------------------------------------------------------------------

function M.request(session)
    M.state, M.message, M.receiver, M.pending, M.result = "requested", "Warte auf den Host ...", nil, nil, nil
    session:send("SAVE_REQUEST", { reserved = 0 }, true)
end

function M.cancel()
    M.state, M.message, M.receiver, M.pending = "idle", "", nil, nil
end

local function finish(session)
    local data, err = M.receiver:result()
    M.receiver = nil
    if data == nil then
        M.state, M.message = "failed", "Uebertragung fehlerhaft: " .. tostring(err)
        session:log("Spielstand: %s", M.message)
        return
    end
    local parts, derr = serial.decode(data)
    if parts == nil then
        M.state, M.message = "failed", "Spielstand nicht lesbar: " .. tostring(derr)
        session:log("Spielstand: %s", M.message)
        return
    end
    M.pending = parts
    M.state = "ready"
    M.message = "Spielstand empfangen. Lade jetzt im Pausenmenue einen beliebigen eigenen Spielstand."
    session:log("Spielstand des Hosts empfangen (%d KB)", #data // 1024)
end

function M.on_begin(session, msg)
    if M.state ~= "requested" and M.state ~= "receiving" then
        return -- nicht angefragt
    end
    if msg.size == 0 then
        M.state, M.message = "failed", msg.info ~= "" and msg.info or "Host hat keinen Spielstand"
        return
    end
    M.receiver = transfer.receiver(msg)
    M.state = "receiving"
    M.message = "Empfange Spielstand des Hosts (" .. msg.info .. ") ..."
    if M.receiver:complete() then
        finish(session)
    end
end

function M.on_chunk(session, msg)
    if M.state ~= "receiving" or M.receiver == nil then
        return
    end
    if M.receiver:add(msg) and M.receiver:complete() then
        finish(session)
    end
end

function M.progress()
    if M.receiver ~= nil then
        return M.receiver:progress()
    end
    return M.state == "ready" and 1 or 0
end

-- Wird vom Lade-Hook mit der frisch eingelesenen GameSaveDataList aufgerufen.
function M.on_load(list)
    local parts = M.pending
    if parts == nil then
        return
    end
    M.pending = nil
    local ok, ctx = pcall(M.apply, list, parts)
    if not ok then
        M.state, M.message = "failed", "Einspielen fehlgeschlagen: " .. tostring(ctx)
        return
    end
    M.result = ctx
    M.state = "applied"
    local s = ctx.stats
    M.message = string.format("Spielstand des Hosts eingespielt (%d Teile, %d Variablen, %d nicht uebernommen).",
        s.parts, s.vars, s.failed)
end

-- Pre-Hook auf SaveDataManager.loadGameSaveData (nur im Spiel).
function M.install_hook()
    if M.hooked or sdk == nil or sdk.hook == nil then
        return false
    end
    local td = sdk.find_type_definition(game.ns("gamemastering.SaveDataManager"))
    local method = td and td:get_method("loadGameSaveData")
    if method == nil then
        return false
    end
    sdk.hook(method, function(args)
        if M.pending == nil then
            return
        end
        local ok, err = pcall(function()
            local self = sdk.to_managed_object(args[2])
            local list = self:get_field("GameSaveDataValue"):get_field("GameSaveDataList")
            M.on_load(list)
        end)
        if not ok then
            M.pending = nil
            M.state, M.message = "failed", "Lade-Hook: " .. tostring(err)
        end
    end, function(retval)
        return retval
    end)
    M.hooked = true
    return true
end

return M
