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
local tr = require("re2r_coop.text")

local M = {}

M.CHUNKS_PER_FRAME = 8     -- Host: so viele Stuecke je Frame senden (8 KB je Stueck)

-- Zustand beim Freund:
--   idle -> requested -> receiving -> ready (Stand liegt bereit, Laden abwarten)
--   -> applied | failed
M.state = "idle"
M.message = ""       -- Meldung in der Sprache beim Setzen (Log, Tests)
M.message_key = nil  -- Textschluessel (join.*) oder rohe Meldung, siehe M.text()
M.message_params = nil
M.receiver = nil
M.pending = nil      -- Teile, die beim naechsten Laden eingespielt werden
M.result = nil       -- stats/errors des letzten Einspielens

-- Host: laufende Sendungen { peer=, begin=, chunks=, next= }
M.outgoing = {}

-- Meldung setzen: Schluessel plus Werte merken, damit M.text() nach einem
-- Sprachwechsel neu uebersetzt. Unbekannte Schluessel (rohe Texte, z. B. vom
-- Host) kommen unveraendert zurueck.
local function say(key, params)
    M.message_key, M.message_params = key, params
    M.message = key ~= nil and tr(key, params) or ""
end

-- Meldung fuer die Anzeige in der aktuellen Sprache.
function M.text()
    if M.message_key == nil then
        return M.message
    end
    return tr(M.message_key, M.message_params)
end

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

-- Antwort, wenn der Host noch nicht im Spiel ist (der Freund fragt dann
-- regelmaessig nach). Im Titel eingesammelt hat der Stand keinen gueltigen
-- Ort (LoadLocation 0), das Laden beim Freund haengt dann bei 10 %
-- (bestaetigt am 4. November 2026 mit dem Testbot-Spiegel).
M.HOST_NOT_READY = "Host ist noch nicht im Spiel"
-- Antwort, wenn der Host nichts einsammeln kann. Beide Texte gehen so ueber
-- das Netz (Feld info) und bleiben fuer aeltere Versionen unveraendert; der
-- Freund zeigt sie uebersetzt an.
M.HOST_NO_SAVE = "Host hat keinen Spielstand"
M.RETRY_INTERVAL = 5.0

function M.on_request(session, peer)
    local main = M.main_state()
    if main ~= nil and main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE then
        session:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = M.HOST_NOT_READY }, true, peer.id)
        return
    end
    local ok, parts = pcall(M.capture)
    if not ok then
        session:logt("join.log_capture_failed", { name = peer.name or "?", error = tostring(parts) })
        session:send("SAVE_BEGIN", { transfer = 0, size = 0, chunks = 0, checksum = 0, info = M.HOST_NO_SAVE }, true, peer.id)
        return
    end
    local data = serial.encode(parts)
    next_transfer = (next_transfer + 1) % 4294967296
    local begin, chunks = transfer.split(data, next_transfer, describe())
    session:send("SAVE_BEGIN", begin, true, peer.id)
    M.outgoing[#M.outgoing + 1] = { peer = peer.id, begin = begin, chunks = chunks, next = 1 }
    session:logt("join.log_sending", { name = peer.name or "?", kb = #data // 1024, info = begin.info })
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
    M.state, M.receiver, M.pending, M.result = "requested", nil, nil, nil
    say("join.wait_host")
    M.auto_retry_at, M.loader, M.session = nil, nil, session
    session:send("SAVE_REQUEST", { reserved = 0 }, true)
end

function M.cancel()
    M.state, M.receiver, M.pending, M.loader = "idle", nil, nil, nil
    say(nil)
end

local function finish(session)
    local data, err = M.receiver:result()
    M.receiver = nil
    if data == nil then
        M.state = "failed"
        say("join.transfer_failed", { error = tostring(err) })
        session:logt("join.log_failed", { text = M.message })
        return
    end
    local parts, derr = serial.decode(data)
    if parts == nil then
        M.state = "failed"
        say("join.unreadable", { error = tostring(derr) })
        session:logt("join.log_failed", { text = M.message })
        return
    end
    M.pending = parts
    M.state = "ready"
    say("join.received")
    session:logt("join.log_received", { kb = #data // 1024 })
end

function M.on_begin(session, msg)
    if M.state ~= "requested" and M.state ~= "receiving" then
        return -- nicht angefragt
    end
    if msg.size == 0 then
        if msg.info == M.HOST_NOT_READY then
            M.state = "waiting_host"
            say("join.wait_host_save")
            M.request_at = nil -- update_auto setzt die naechste Anfrage
            return
        end
        M.state = "failed"
        say((msg.info == "" or msg.info == M.HOST_NO_SAVE) and "join.host_no_save" or msg.info)
        return
    end
    M.receiver = transfer.receiver(msg)
    M.state = "receiving"
    say("join.receiving_from", { info = msg.info })
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
        M.state = "failed"
        say("join.apply_failed", { error = tostring(ctx) })
        return
    end
    M.result = ctx
    M.state = "applied"
    local s = ctx.stats
    say("join.applied", { parts = s.parts, vars = s.vars, failed = s.failed })
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
            M.state = "failed"
            say("join.load_hook", { error = tostring(err) })
        end
    end, function(retval)
        return retval
    end)
    M.hooked = true
    return true
end

-- --- Automatisch laden (Freund) ----------------------------------------------
--
-- Bestaetigt am 3. November 2026: Aus dem laufenden Spiel direkt
-- goLoadGameData aufzurufen haengt (der Hauptablauf steht noch auf IN_GAME).
-- Funktioniert: goResetGameToStoryContinue (zurueck zum Titel, MainState 3),
-- dann requestLoadGameData(Modus, Platz), warten bis die Datei gelesen ist
-- (saveLoadStep wieder 1), dann MainFlowManager.goLoadGameData -> nach ca.
-- 2,4 s IN_GAME (6). Steuerung danach normal.
--
-- Bestaetigt am 4. November 2026: Aus dem Titelmenue (MainState 3) geht
-- dasselbe ohne Zuruecksetzen, auch aus dem Hauptmenue (GUI_MenuMain). Das
-- Spiel laedt, aber die gerade offenen Menues (GUI_MenuMain, GUI_TitleMenu,
-- GUI_GeneralGuide ...) bleiben ueber dem Spiel stehen. Das war beim ersten
-- echten Test "haengt im Titelmenue". Das Spiel selbst blendet seine Menues
-- ueber Behavior.enableObject(false) aus (DrawSelf und UpdateSelf aus), das
-- machen wir nach dem Laden mit allen Titel-Menues auch.
-- TitleFlow.StateValue = TITLE_SAVEDATA_LOAD_END (27) zu setzen bewirkt
-- dagegen nichts.

M.MAIN_TITLE = 3
M.MAIN_IN_GAME = 6
M.MAIN_PAUSE = 9
M.LOAD_TIMEOUT = 60

-- Menues des Titelbildschirms, die nach dem Laden weg muessen.
M.TITLE_GUIS = {
    GUI_TitleMenu = true, GUI_MenuMain = true, GUI_MenuStory = true, GUI_Load = true,
    GUI_MenuScenario = true, GUI_TitleFirst = true, GUI_TitleL = true, GUI_TitleR = true,
    GUI_GeneralGuide = true, GUI_SelectDifficulty = true, GUI_Costume = true,
}

M.auto = false       -- setzt das Hauptskript aus der Konfiguration
M.loader = nil       -- laufender automatischer Ladevorgang

local function managers()
    local mfm = sdk.get_managed_singleton(game.ns("gamemastering.MainFlowManager"))
    local sdm = sdk.get_managed_singleton(game.ns("gamemastering.SaveDataManager"))
    return mfm, sdm
end

local function main_state(mfm)
    return mfm:get_field("_CurrentMainState")
end

-- Hauptzustand des Spiels (3 = Titel, 6 = im Spiel, 9 = Pause) oder nil.
function M.main_state()
    if sdk == nil or sdk.get_managed_singleton == nil then
        return nil
    end
    local mfm = managers()
    return mfm and main_state(mfm) or nil
end

-- Blendet alle noch sichtbaren Titel-Menues aus. Gibt die Namen zurueck.
function M.hide_title_menus()
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local guis = scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
    local hidden = {}
    for _, c in ipairs(guis and guis:get_elements() or {}) do
        local go = c:call("get_GameObject")
        local name = go:call("get_Name")
        if M.TITLE_GUIS[name] and go:call("get_DrawSelf") then
            local done = false
            for _, comp in ipairs(go:call("get_Components"):get_elements()) do
                local tn = comp:get_type_definition():get_full_name()
                if tn:find("Behavior$") then
                    done = pcall(comp.call, comp, "enableObject(System.Boolean)", false)
                    break
                end
            end
            if not done or go:call("get_DrawSelf") then
                go:call("set_DrawSelf", false)
                go:call("set_UpdateSelf", false)
            end
            hidden[#hidden + 1] = name
        end
    end
    return hidden
end

-- Neuester belegter Speicherplatz (SaveDataManager.getSaveFileDetailList,
-- bestaetigt am 4. November 2026: get_Slot = Platz fuer requestLoadGameData,
-- leere Plaetze sind nil) oder nil.
function M.newest_slot(sdm, mode)
    local list = sdm:call("getSaveFileDetailList", mode)
    if list == nil then
        return nil
    end
    local best, best_time
    for i = 0, list:call("get_Count") - 1 do
        local d = list:call("get_Item", i)
        if d ~= nil and not d:call("get_EmptyData") then
            local t = d:call("get_LastUpdateTimeStamp")
            if best_time == nil or (t ~= nil and t > best_time) then
                best, best_time = d:call("get_Slot"), t
            end
        end
    end
    return best
end

-- Startet das automatische Laden (Stand muss bereitliegen). Geht im Spiel,
-- in der Pause und im Titelbildschirm (auch in dessen Untermenues).
function M.start_auto_load(now)
    local mfm, sdm = managers()
    if mfm == nil or sdm == nil then
        M.state = "failed"
        say("join.game_not_ready")
        return false
    end
    local main = main_state(mfm)
    if main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE and main ~= M.MAIN_TITLE then
        say("join.wait_game")
        return false
    end
    local ok, mode = pcall(sdm.call, sdm, "getSaveModeFromCurrentScenarioType")
    mode = ok and mode or 1
    local index = sdm:get_field("<LoadGameDataIndex>k__BackingField")
    if index == nil or index < 0 then
        local ok_slot, slot = pcall(M.newest_slot, sdm, mode)
        index = ok_slot and slot or nil
    end
    if index == nil or index < 0 then
        say("join.no_own_save")
        return false
    end
    local phase = main == M.MAIN_TITLE and "title" or "reset"
    M.loader = { phase = phase, since = now, start = now, index = index, mode = mode }
    say("join.loading")
    return true
end

local function step_loader(now)
    local L = M.loader
    local mfm, sdm = managers()
    local main = main_state(mfm)
    if now - L.start > M.LOAD_TIMEOUT then
        M.loader = nil
        M.state = "failed"
        say("join.load_timeout", { state = tostring(main) })
        return
    end
    if L.phase == "reset" then
        if main == M.MAIN_TITLE then
            L.phase, L.since = "title", now
        elseif not L.reset_called then
            L.reset_called = true
            mfm:call("goResetGameToStoryContinue")
        end
    elseif L.phase == "title" then
        -- Titel kurz zur Ruhe kommen lassen (nach dem Zuruecksetzen)
        if now - L.since >= (L.reset_called and 1.0 or 0.1) then
            sdm:call("requestLoadGameData", L.mode, L.index)
            L.phase, L.since, L.saw_read = "read", now, false
        end
    elseif L.phase == "read" then
        local step = sdm:call("get_saveLoadStep")
        if step ~= 1 then
            L.saw_read = true
        end
        -- Ist im Titel "Spiel laden" offen, laedt das Spiel nach
        -- requestLoadGameData selbst weiter (TitleFlow FINALIZE, MainState 4,
        -- bestaetigt am 4. November 2026). Dann kein zweites goLoadGameData.
        if main ~= M.MAIN_TITLE and main ~= M.MAIN_IN_GAME and main ~= M.MAIN_PAUSE then
            L.phase, L.since = "loading", now
        elseif now - L.since >= 0.3 and ((L.saw_read and step == 1) or now - L.since > 3.0) then
            mfm:call("goLoadGameData")
            L.phase, L.since = "loading", now
        end
    elseif L.phase == "loading" then
        if main == M.MAIN_IN_GAME and game.get_local_state() ~= nil then
            pcall(M.hide_title_menus)
            M.loader = nil
        end
    end
end

-- Jeden Frame (Freund): automatisch anfordern war schon, hier laden.
function M.update_auto(now)
    -- Host war noch nicht im Spiel: regelmaessig neu anfragen.
    if M.state == "waiting_host" and M.session ~= nil then
        M.request_at = M.request_at or (now + M.RETRY_INTERVAL)
        if now >= M.request_at then
            M.request_at = nil
            local session = M.session
            M.request(session)
            say("join.wait_host_save")
        end
        return
    end
    if M.loader ~= nil then
        local ok, err = pcall(step_loader, now)
        if not ok then
            M.loader = nil
            M.state = "failed"
            say("join.auto_load_failed", { error = tostring(err) })
        end
        return
    end
    -- Startet, sobald das Spiel bereit ist (sonst alle 2 s neu pruefen).
    if M.auto and M.state == "ready" and M.pending ~= nil and now >= (M.auto_retry_at or 0) then
        if not M.start_auto_load(now) then
            M.auto_retry_at = now + 2.0
        end
    end
end

return M
