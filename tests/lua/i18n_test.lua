-- remultiplayer_coop.i18n: Schluessel, Platzhalter, Rueckfall, Sprachwahl,
-- Vollstaendigkeit der Sprachdateien (gemeinsam und RE2).
local AUTORUN = os.getenv("REMULTIPLAYER_RE2R_AUTORUN")
if AUTORUN then
    package.path = AUTORUN .. "/?.lua;" .. package.path
end

local i18n = require("remultiplayer_coop.i18n")
local t = i18n.t

-- Gemeinsame Texte sind nach dem require schon da
assert(i18n.has_language("de") and i18n.has_language("en"), "gemeinsame Sprachen nicht geladen")
assert(i18n.current() == "en", "ohne Spielsprache muss Automatisch Englisch sein")
assert(t("conn.host") == "Host")
assert(t("conn.host", nil, "de") == "Hosten")

-- Feste Sprache
assert(i18n.set_setting("de"))
assert(i18n.current() == "de" and t("conn.join") == "Beitreten")
assert(not i18n.set_setting("xx"), "unbekannte Sprache angenommen")
assert(i18n.setting == "de")

-- Platzhalter
assert(t("status.ping", { ms = 40 }) == "Ping 40 ms", t("status.ping", { ms = 40 }))
assert(t("status.peer_short", { name = "Claire", ms = 12 }) == "Mitspieler: Claire  (Ping 12 ms)")
assert(t("status.ping") == "Ping {ms} ms", "ohne Werte bleibt der Platzhalter stehen")
assert(t("status.ping", {}) == "Ping {ms} ms")
-- Werte mit Sonderzeichen (% fuer gsub) bleiben unveraendert
assert(t("chat.you", { text = "100% {x} %1" }) == "Du: 100% {x} %1", t("chat.you", { text = "100% {x} %1" }))

-- Automatisch: Spielsprache, wenn bekannt, sonst Englisch
assert(i18n.set_setting("auto"))
i18n.set_game_language_getter(function() return "de" end)
assert(i18n.current() == "de")
i18n.set_game_language_getter(function() return "fr" end) -- keine Sprachdatei
assert(i18n.current() == "en")
i18n.set_game_language_getter(function() error("kaputt") end)
assert(i18n.current() == "en", "Fehler im Adapter darf nicht durchschlagen")
i18n.set_game_language_getter(nil)

-- Rueckfall: fehlt in Deutsch -> Englisch -> Schluessel
i18n.register("en", { ["test.only_en"] = "only english" })
i18n.register("de", { ["test.both"] = "beide" })
i18n.register("en", { ["test.both"] = "both" })
assert(t("test.only_en", nil, "de") == "only english")
assert(t("test.both", nil, "de") == "beide")
assert(t("test.nowhere", nil, "de") == "test.nowhere")
assert(t("test.nowhere") == "test.nowhere")
assert(t("test.both", nil, "zz") == "both", "unbekannte Sprache faellt auf Englisch zurueck")

-- Neue Sprache ohne Codeaenderung: nur Sprachgruppe mit Liste + Datei
local fake = {
    ["demo.languages"] = { { code = "en", name = "English" }, { code = "fr", name = "Francais" }, "broken" },
    ["demo.en"] = { ["demo.hello"] = "Hello {who}" },
    ["demo.fr"] = { ["demo.hello"] = "Bonjour {who}" },
}
local errors = i18n.load("demo", function(name)
    local v = fake[name]
    if v == nil then error("module '" .. name .. "' not found") end
    return v
end)
assert(#errors == 1 and errors[1]:find("demo.broken"), "Fehler der kaputten Datei fehlt")
assert(i18n.set_setting("fr"))
assert(t("demo.hello", { who = "Leon" }) == "Bonjour Leon")
assert(t("conn.host") == "Host", "fehlt in fr -> Englisch")
local names = {}
for _, l in ipairs(i18n.languages()) do names[l.code] = l.name end
assert(names.fr == "Francais" and names.de == "Deutsch" and names.en == "English")
assert(#i18n.load("gibtsnicht", function() error("nope") end) == 1)

-- Vollstaendigkeit: jede Sprachdatei hat dieselben Schluessel wie Englisch
local function check_group(prefix)
    i18n.reset()
    local errs = i18n.load(prefix)
    assert(#errs == 0, prefix .. ": " .. table.concat(errs, "; "))
    for _, l in ipairs(i18n.languages()) do
        local miss = i18n.missing(l.code, "en")
        assert(#miss == 0, prefix .. "." .. l.code .. " fehlt: " .. table.concat(miss, ", "))
        local extra = i18n.missing("en", l.code)
        assert(#extra == 0, prefix .. ".en fehlt (aus " .. l.code .. "): " .. table.concat(extra, ", "))
    end
end
check_group("remultiplayer_coop.lang")
if AUTORUN then
    check_group("re2r_coop.lang")
end

print("i18n_test: alles ok")
