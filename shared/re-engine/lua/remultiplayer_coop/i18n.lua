-- Uebersetzungen fuer alle RE-Engine-Mods (RE:Multiplayer)
--
-- Texte werden ueber Schluessel geholt:
--   local i18n = require("remultiplayer_coop.i18n")
--   local t = i18n.t
--   t("menu.host")                      -> "Hosten" / "Host"
--   t("status.ping", { ms = 40 })       -> "Ping 40 ms"
--
-- Platzhalter im Text: {name}. Fehlt ein Wert, bleibt "{name}" stehen.
--
-- Sprachdateien sind Lua-Module, die eine flache Tabelle zurueckgeben:
--   return { ["menu.host"] = "Host", ... }
-- Eine Sprachgruppe ist ein Modul-Praefix mit einer Liste der Sprachen:
--   <praefix>/languages.lua  ->  return { { code = "de", name = "Deutsch" }, ... }
--   <praefix>/de.lua, <praefix>/en.lua, ...
-- i18n.load("<praefix>") laedt alle Sprachen der Liste. Neue Sprache = neue
-- Datei + eine Zeile in languages.lua, keine Aenderung am Code der Mod.
--
-- Reihenfolge beim Nachschlagen: gewaehlte Sprache -> Englisch -> Schluessel.
--
-- Sprachwahl (i18n.set_setting):
--   "auto"  = Spielsprache (i18n.set_game_language_getter), sonst Englisch
--   "de", "en", ... = feste Sprache

local i18n = {}

i18n.FALLBACK = "en"

i18n.strings = {} -- strings[code][key] = text
i18n.names = {} -- names[code] = Anzeigename ("Deutsch")
i18n.order = {} -- Codes in Lade-Reihenfolge (fuer das Auswahlmenue)
i18n.setting = "auto"
i18n.game_language = nil -- function() -> code oder nil
i18n.groups = {} -- geladene Sprachgruppen (Praefixe)

local function add_language(code, name)
    if i18n.strings[code] == nil then
        i18n.strings[code] = {}
        i18n.order[#i18n.order + 1] = code
    end
    if name ~= nil then
        i18n.names[code] = name
    end
end

-- Texte einer Sprache hinzufuegen (spaetere ueberschreiben fruehere).
function i18n.register(code, texts, name)
    assert(type(code) == "string" and code ~= "", "Sprachcode fehlt")
    assert(type(texts) == "table", "Texte muessen eine Tabelle sein")
    add_language(code, name)
    local dst = i18n.strings[code]
    for k, v in pairs(texts) do
        if type(k) == "string" and type(v) == "string" then
            dst[k] = v
        end
    end
end

-- Alle Sprachen einer Sprachgruppe laden (siehe oben). Fehlerhafte Dateien
-- werden uebersprungen; zurueck kommt die Liste der Fehler (oder leer).
function i18n.load(prefix, require_fn)
    require_fn = require_fn or require
    local errors = {}
    i18n.groups[prefix] = true
    local ok, list = pcall(require_fn, prefix .. ".languages")
    if not ok or type(list) ~= "table" then
        errors[#errors + 1] = prefix .. ".languages: " .. tostring(list)
        return errors
    end
    for _, entry in ipairs(list) do
        local code = type(entry) == "table" and entry.code or entry
        local name = type(entry) == "table" and entry.name or nil
        if type(code) == "string" then
            local ok2, texts = pcall(require_fn, prefix .. "." .. code)
            if ok2 and type(texts) == "table" then
                i18n.register(code, texts, name)
            else
                errors[#errors + 1] = prefix .. "." .. code .. ": " .. tostring(texts)
            end
        end
    end
    return errors
end

function i18n.has_language(code)
    return type(code) == "string" and i18n.strings[code] ~= nil
end

-- Liste fuer das Auswahlmenue: { { code = "de", name = "Deutsch" }, ... }
function i18n.languages()
    local out = {}
    for _, code in ipairs(i18n.order) do
        out[#out + 1] = { code = code, name = i18n.names[code] or code }
    end
    return out
end

function i18n.set_setting(setting)
    if setting == "auto" or i18n.has_language(setting) then
        i18n.setting = setting
        return true
    end
    return false
end

-- fn() liefert den Sprachcode des Spiels ("de", "en", ...) oder nil.
function i18n.set_game_language_getter(fn)
    i18n.game_language = fn
end

-- Aktuell verwendete Sprache.
function i18n.current()
    if i18n.setting ~= "auto" and i18n.has_language(i18n.setting) then
        return i18n.setting
    end
    if i18n.game_language ~= nil then
        local ok, code = pcall(i18n.game_language)
        if ok and i18n.has_language(code) then
            return code
        end
    end
    return i18n.FALLBACK
end

local function format(text, params)
    if params == nil then
        return text
    end
    return (text:gsub("{([%w_]+)}", function(name)
        local v = params[name]
        if v == nil then
            return nil -- Platzhalter bleibt stehen
        end
        return tostring(v)
    end))
end

-- Text zu einem Schluessel. lang optional (sonst i18n.current()).
function i18n.t(key, params, lang)
    lang = lang or i18n.current()
    local texts = i18n.strings[lang]
    local text = texts and texts[key]
    if text == nil then
        local fb = i18n.strings[i18n.FALLBACK]
        text = fb and fb[key]
    end
    if text == nil then
        return key
    end
    return format(text, params)
end

-- Schluessel, die in einer Sprache fehlen (verglichen mit der Referenz).
-- Fuer Tests und die Pflege neuer Sprachen.
function i18n.missing(code, reference)
    reference = reference or i18n.FALLBACK
    local out = {}
    local ref = i18n.strings[reference] or {}
    local texts = i18n.strings[code] or {}
    for k in pairs(ref) do
        if texts[k] == nil then
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return out
end

-- Nur fuer Tests: alles zuruecksetzen.
function i18n.reset()
    i18n.strings, i18n.names, i18n.order, i18n.groups = {}, {}, {}, {}
    i18n.setting, i18n.game_language = "auto", nil
end

-- Gemeinsame Texte (Sitzung, Verbindung, Status) gleich mitladen.
i18n.load("remultiplayer_coop.lang")

return i18n
