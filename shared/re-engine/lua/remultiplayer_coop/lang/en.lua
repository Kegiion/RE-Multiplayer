-- Gemeinsame Texte aller RE-Engine-Mods: Englisch (Rueckfallsprache)
return {
    -- Sitzung (Log)
    ["session.host_started"] = "Hosting on port {port}",
    ["session.host_failed"] = "Hosting failed: {error}",
    ["session.connecting"] = "Connecting to {address}:{port} ...",
    ["session.connect_failed"] = "Connection failed: {error}",
    ["session.left"] = "Disconnected",
    ["session.protocol_mismatch"] = "Player {peer} uses protocol v{theirs}, we use v{ours} - please use the same mod version!",
    ["session.game_mismatch"] = "Player {peer} is playing '{theirs}', we are playing '{ours}' - wrong game!",
    ["session.version_note"] = "Note: {name} uses mod version {theirs}, we use {ours}",
    ["session.peer_joined"] = "{name} joined",
    ["session.peer_connected"] = "Connected to peer {peer}",
    ["session.peer_disconnected"] = "{name} disconnected",
    ["session.peer_fallback_name"] = "Peer {peer}",
    ["session.disconnected"] = "Connection lost",
    ["session.disconnected_error"] = "Connection lost: {error}",
    ["session.bad_message"] = "Invalid message from peer {peer}: {error}",
    ["session.handler_error"] = "Error in handler {type}: {error}",
    ["session.listener_error"] = "Error in listener {event}: {error}",

    -- Verbindung (Menue)
    ["conn.name"] = "Your name",
    ["conn.address"] = "Host IP",
    ["conn.port"] = "Port",
    ["conn.host"] = "Host",
    ["conn.join"] = "Join",
    ["conn.disconnect"] = "Disconnect",
    ["conn.default_name"] = "Player",

    -- Status
    ["status.idle"] = "Not connected",
    ["status.hosting"] = "Hosting - waiting for a partner",
    ["status.connecting"] = "Connecting ...",
    ["status.connected"] = "Connected",
    ["status.port_suffix"] = " (port {port})",
    ["status.line"] = "Status: {text}",
    ["status.last_error"] = "Last error: {error}",
    ["status.error"] = "Error: {error}",
    ["status.handshake"] = "(handshake ...)",
    ["status.incompatible"] = "{name} - INCOMPATIBLE, see log",
    ["status.peer_line"] = "  Partner: {name}  [{address}]  ping {ms} ms",
    ["status.peer_short"] = "Partner: {name}  (ping {ms} ms)",
    ["status.ping"] = "Ping {ms} ms",

    -- Chat
    ["chat.input"] = "Message",
    ["chat.send"] = "Send",
    ["chat.you"] = "You: {text}",
    ["chat.line"] = "{name}: {text}",

    -- Sprache
    ["lang.label"] = "Language / Sprache",
    ["lang.auto"] = "Automatic (game language)",

    -- Allgemein
    ["ui.log"] = "Log",
    ["ui.error"] = "UI error: {error}",
    ["ui.cancel"] = "Cancel",
}
