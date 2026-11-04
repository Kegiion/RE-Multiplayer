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
    ["debug.state_loading"] = "laedt",
    ["debug.state_deleted"] = "vom Spiel geloescht, wird neu erzeugt",
    ["debug.err_no_actor"] = "keine Actor-Figur fuer ID {id}",
    ["debug.err_no_character"] = "keine Spielfigur fuer ID {id}",
    ["debug.err_no_prefab"] = "via.Prefab nicht erzeugt",
    ["debug.err_instantiate"] = "instantiate lieferte nil",
    ["debug.err_costume"] = "SurvivorCostumeChanger fehlt",
    ["debug.err_prefab_timeout"] = "Prefab laedt nicht: {path}",
    ["debug.err_no_player_folder"] = "Ordner des Spielers nicht gefunden",
    ["debug.err_menu_methods"] = "Menue-Methoden nicht gefunden",

    -- Markierung des Mitspielers
    ["ghost.stale"] = "  (keine Daten)",
    ["ghost.other_area"] = "  (anderer Bereich: {area})",
    ["ghost.peer"] = "Spieler {id}",

    -- Schluessel-Items (items_net, noch nicht geladen)
    ["items.in_box"] = "Schluessel-Item liegt in der Itemkiste (Inventar voll)",
    ["items.failed"] = "Schluessel-Item konnte nicht uebernommen werden: {error}",

    -- Titelmenue "Multiplayer" (Spielschrift, Umlaute erlaubt)
    ["tm.label"] = "Multiplayer",
    ["tm.label_help"] = "Gemeinsam mit einem Freund spielen (RE:Multiplayer).",
    ["tm.partner"] = "Mitspieler",
    ["tm.host"] = "Spiel hosten",
    ["tm.host_help"] = "Du startest das Spiel, dein Freund tritt dir bei (UDP-Port {port}).",
    ["tm.join"] = "Beitreten",
    ["tm.join_help"] = "Verbindet dich mit dem Spiel deines Freundes und lädt seinen Spielstand.",
    ["tm.address"] = "IP des Hosts: {value}",
    ["tm.address_help"] = "Die IP-Adresse deines Freundes (z. B. aus Radmin VPN oder ZeroTier).",
    ["tm.name"] = "Dein Name: {value}",
    ["tm.name_help"] = "So sieht dich dein Mitspieler.",
    ["tm.language"] = "Sprache: {value}",
    ["tm.language_auto"] = "Automatisch",
    ["tm.language_help"] = "Sprache der Mod. Automatisch = Sprache des Spiels.",
    ["tm.friend_connected"] = "{name} ist verbunden",
    ["tm.waiting"] = "Warte auf Mitspieler ...",
    ["tm.load_now_help"] = "Lade jetzt über Kampagne deinen Spielstand. Dein Freund kommt automatisch nach.",
    ["tm.give_ip_help"] = "Gib deinem Freund deine IP-Adresse. Port {port} (UDP).",
    ["tm.stop_hosting"] = "Hosten beenden",
    ["tm.stop_hosting_help"] = "Beendet das Spiel für deinen Freund.",
    ["tm.connecting"] = "Verbinde mit {address} ...",
    ["tm.moment"] = "Einen Moment ...",
    ["tm.cancel"] = "Abbrechen",
    ["tm.fetching"] = "Hole den Spielstand ...",
    ["tm.receiving"] = "Empfange Spielstand ... {percent} %",
    ["tm.connected_with"] = "Verbunden mit {name}",
    ["tm.connected"] = "Verbunden",
    ["tm.disconnect"] = "Trennen",
    ["tm.back"] = "Zurück",
    ["tm.back_help"] = "Zurück zum Hauptmenü.",
    ["tm.edit_help"] = "Eintippen, Enter = übernehmen, Esc = abbrechen.",
    ["tm.ip_incomplete"] = "Bitte eine vollständige IP eingeben, z. B. 192.168.0.10.",
    ["tm.ip_too_big"] = "Jede Zahl der IP darf höchstens 255 sein.",
    ["tm.name_missing"] = "Bitte einen Namen eingeben.",

    -- Debug: Titelmenue
    ["debug.titlemenu"] = "Titelmenue-Eintrag: {state}",
    ["debug.active"] = "aktiv",
}
