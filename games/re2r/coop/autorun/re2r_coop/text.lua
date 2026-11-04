-- re2r_coop/text.lua
--
-- Texte der RE2-Mod: laedt die Sprachgruppe re2r_coop.lang (zusaetzlich zu den
-- gemeinsamen Texten aus remultiplayer_coop.lang) und gibt i18n.t zurueck.
--   local tr = require("re2r_coop.text")
--   tr("join.fetch")

local i18n = require("remultiplayer_coop.i18n")

if not i18n.groups["re2r_coop.lang"] then
    local errors = i18n.load("re2r_coop.lang")
    for _, err in ipairs(errors) do
        if log and log.info then
            log.info("[re2r_coop] Sprachdatei fehlerhaft: " .. err)
        end
    end
end

return i18n.t
