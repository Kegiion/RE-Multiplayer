-- RE2-Mod: Deutsch
return {
    -- Plugin fehlt
    ["re2r.plugin_missing"] = "Plugin remultiplayer_coopnet.dll nicht gefunden!",
    ["re2r.plugin_where"] = "Es gehoert nach: <RE2-Ordner>/reframework/plugins/",
    ["re2r.plugin_restart"] = "Danach das Spiel neu starten.",

    -- Menue
    ["re2r.menu_title"] = "RE2 Koop",
    ["re2r.loaded"] = "RE2 Koop {version} geladen (coopnet {coopnet})",
    ["re2r.error_log"] = "FEHLER {text}",

    -- Spielstand des Hosts (Join)
    ["join.title"] = "Spielstand des Hosts uebernehmen",
    ["join.auto"] = "Beim Beitreten automatisch laden",
    ["join.fetch"] = "Spielstand des Hosts holen",
    ["join.receiving"] = "Empfange ... {percent} %",
    ["join.manual_hint"] = "Pause -> Spiel laden -> beliebiger Spielstand. Du landest beim Host.",

    -- Titel-Fenster
    ["title.window"] = "RE:Multiplayer - Koop fuer Resident Evil 2",
    ["title.host_hint"] = "Lade jetzt deinen Spielstand. Dein Freund kommt automatisch nach.",
    ["title.more_settings"] = "Mehr Einstellungen: Taste Einfg -> RE2 Koop",

    -- Einstellungen
    ["opt.show_ghosts"] = "Mitspieler-Markierung anzeigen",
    ["opt.show_puppets"] = "Mitspieler als Spielfigur anzeigen",
    ["opt.real_partner"] = "VERSUCH: Mitspieler als echte Spielfigur (vorher speichern!)",
    ["opt.title_window"] = "Multiplayer-Fenster im Titelbildschirm",
    ["opt.show_debug"] = "Debug-Infos",
    ["opt.devconsole"] = "Entwickler-Konsole fuer Claude",

    -- Diagnose
    ["diag.label"] = "Situation (z. B. hauptmenue)",
    ["diag.save"] = "Diagnose speichern",
    ["diag.saved"] = "Gespeichert: {file}",
    ["diag.no_find_types"] = "(Erweiterte Klassensuche nicht verfuegbar - altes Plugin?)",

    -- Debug-Infos
    ["debug.none"] = "keine",
    ["debug.player"] = "Spieler: {name}  via {source}",
    ["debug.position"] = "Position: {x}  {y}  {z}",
    ["debug.rotation"] = "Rotation: {x}  {y}  {z}  {w}",
    ["debug.character"] = "Figur: {name} ({survivor}, {type})",
    ["debug.area_scene"] = "Bereich (Scene): {name} ({id})",
    ["debug.area_space"] = "Bereich (Space): {name} ({id})",
    ["debug.map_area"] = "Map-Area: {name} ({id})",
    ["debug.no_condition"] = "PlayerCondition: nicht gefunden",
    ["debug.no_player"] = "Spieler: nicht gefunden (Menue/Ladebildschirm?)",
    ["debug.remote"] = "Remote {id} ({name}): {x} {y} {z}  seq {seq}  Figur {character}  Bereich {area}",
    ["debug.remote_puppet"] = "  Figur im Spiel: {text}",
    ["debug.remote_partner"] = "  Echte Figur: {text}",
    ["debug.stats"] = "Gesendet: {sent} Nachr. / {sent_bytes} B   Empfangen: {received} Nachr. / {received_bytes} B",
    ["debug.versions"] = "coopnet {coopnet}   Mod {mod}",
    ["debug.puppet_anim_error"] = "ready, Animationsfehler: {error}",
    ["debug.puppet_weapon_error"] = "ready, Waffenfehler: {error}",
    ["debug.puppet_animated"] = "ready, animiert ({changes} Wechsel, {respawns} x neu erzeugt)",
    ["debug.puppet_no_anim"] = "ready, keine Animationsdaten",
    ["debug.partner_ready"] = "ready, Abweichung {drift} m, {jumps} Spruenge",
    ["debug.console_off"] = "aus",
    ["debug.console_on"] = "an, {count} Befehl(e) ausgefuehrt",
    ["debug.console_task"] = ", Aufgabe laeuft",
    ["debug.console_camera"] = ", eigene Kamera an",

    -- Markierung des Mitspielers
    ["ghost.stale"] = "  (keine Daten)",
    ["ghost.other_area"] = "  (anderer Bereich: {area})",
}
