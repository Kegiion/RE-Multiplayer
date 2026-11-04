-- Gemeinsame Texte aller RE-Engine-Mods: Deutsch
return {
    -- Sitzung (Log)
    ["session.host_started"] = "Host gestartet auf Port {port}",
    ["session.host_failed"] = "Host fehlgeschlagen: {error}",
    ["session.connecting"] = "Verbinde zu {address}:{port} ...",
    ["session.connect_failed"] = "Verbinden fehlgeschlagen: {error}",
    ["session.left"] = "Verbindung beendet",
    ["session.protocol_mismatch"] = "Spieler {peer} hat Protokoll v{theirs}, wir v{ours} - bitte gleiche Mod-Version nutzen!",
    ["session.game_mismatch"] = "Spieler {peer} spielt '{theirs}', wir '{ours}' - falsches Spiel!",
    ["session.version_note"] = "Hinweis: {name} nutzt Mod-Version {theirs}, wir {ours}",
    ["session.peer_joined"] = "{name} ist beigetreten",
    ["session.peer_connected"] = "Verbunden mit Peer {peer}",
    ["session.peer_disconnected"] = "{name} hat die Verbindung getrennt",
    ["session.peer_fallback_name"] = "Peer {peer}",
    ["session.disconnected"] = "Verbindung getrennt",
    ["session.disconnected_error"] = "Verbindung getrennt: {error}",
    ["session.bad_message"] = "Ungueltige Nachricht von Peer {peer}: {error}",
    ["session.handler_error"] = "Fehler im Handler {type}: {error}",
    ["session.listener_error"] = "Fehler in Listener {event}: {error}",

    -- Verbindung (Menue)
    ["conn.name"] = "Dein Name",
    ["conn.address"] = "IP des Hosts",
    ["conn.port"] = "Port",
    ["conn.host"] = "Hosten",
    ["conn.join"] = "Beitreten",
    ["conn.disconnect"] = "Trennen",
    ["conn.default_name"] = "Spieler",

    -- Status
    ["status.idle"] = "Nicht verbunden",
    ["status.hosting"] = "Host - warte auf Mitspieler",
    ["status.connecting"] = "Verbinde ...",
    ["status.connected"] = "Verbunden",
    ["status.port_suffix"] = " (Port {port})",
    ["status.line"] = "Status: {text}",
    ["status.last_error"] = "Letzter Fehler: {error}",
    ["status.error"] = "Fehler: {error}",
    ["status.handshake"] = "(Handshake ...)",
    ["status.incompatible"] = "{name} - INKOMPATIBEL, siehe Log",
    ["status.peer_line"] = "  Mitspieler: {name}  [{address}]  Ping {ms} ms",
    ["status.peer_short"] = "Mitspieler: {name}  (Ping {ms} ms)",
    ["status.ping"] = "Ping {ms} ms",

    -- Chat
    ["chat.input"] = "Nachricht",
    ["chat.send"] = "Senden",
    ["chat.you"] = "Du: {text}",
    ["chat.line"] = "{name}: {text}",

    -- Sprache
    ["lang.label"] = "Sprache / Language",
    ["lang.auto"] = "Automatisch (Spielsprache)",

    -- Allgemein
    ["ui.log"] = "Log",
    ["ui.error"] = "UI-Fehler: {error}",
    ["ui.cancel"] = "Abbrechen",
}
