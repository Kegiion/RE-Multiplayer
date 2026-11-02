-- re0hd_coop/game.lua - Zugriff auf Spieldaten von RE0 HD.
--
-- STAND: NOCH NICHTS BESTAETIGT. Die Adressen fuer Rebecca und Billy
-- (Position, Lebenspunkte, Partner-Steuerung) suchen wir mit Cheat Engine
-- und pruefen sie dann im Menue unter "Speicher-Werkzeug".
-- Bestaetigte Fakten gehoeren nach games/re0hd/research/README.md.

local game = {
    ID = "re0hd",
    -- Figur-IDs fuer PLAYER_STATE.character (unsere eigene Nummerierung)
    CHARACTERS = { [1] = "Rebecca", [2] = "Billy" },
}

-- Zustand des lokalen Spielers fuer PLAYER_STATE oder nil, solange wir die
-- Adressen nicht kennen.
function game.get_local_state()
    return nil
end

return game
