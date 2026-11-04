-- RE2-Mod: Englisch (Rueckfallsprache)
return {
    -- Plugin fehlt
    ["re2r.plugin_missing"] = "Plugin remultiplayer_coopnet.dll not found!",
    ["re2r.plugin_where"] = "It belongs in: <RE2 folder>/reframework/plugins/",
    ["re2r.plugin_restart"] = "Then restart the game.",

    -- Menue
    ["re2r.menu_title"] = "RE2 Co-op",
    ["re2r.loaded"] = "RE2 Co-op {version} loaded (coopnet {coopnet})",
    ["re2r.error_log"] = "ERROR {text}",

    -- Spielstand des Hosts (Join)
    ["join.title"] = "Use the host's save",
    ["join.auto"] = "Load automatically when joining",
    ["join.fetch"] = "Get the host's save",
    ["join.receiving"] = "Receiving ... {percent} %",
    ["join.manual_hint"] = "Pause -> Load game -> any save. You will end up with the host.",

    -- Titel-Fenster
    ["title.window"] = "RE:Multiplayer - Co-op for Resident Evil 2",
    ["title.host_hint"] = "Load your save now. Your friend will follow automatically.",
    ["title.more_settings"] = "More settings: Insert key -> RE2 Co-op",

    -- Einstellungen
    ["opt.show_ghosts"] = "Show partner marker",
    ["opt.show_puppets"] = "Show partner as a character",
    ["opt.real_partner"] = "EXPERIMENT: partner as a real character (save first!)",
    ["opt.title_window"] = "Multiplayer window on the title screen",
    ["opt.show_debug"] = "Debug info",
    ["opt.devconsole"] = "Developer console for Claude",

    -- Diagnose
    ["diag.label"] = "Situation (e.g. main menu)",
    ["diag.save"] = "Save diagnostics",
    ["diag.saved"] = "Saved: {file}",
    ["diag.no_find_types"] = "(Extended class search not available - old plugin?)",

    -- Debug-Infos
    ["debug.none"] = "none",
    ["debug.player"] = "Player: {name}  via {source}",
    ["debug.position"] = "Position: {x}  {y}  {z}",
    ["debug.rotation"] = "Rotation: {x}  {y}  {z}  {w}",
    ["debug.character"] = "Character: {name} ({survivor}, {type})",
    ["debug.area_scene"] = "Area (scene): {name} ({id})",
    ["debug.area_space"] = "Area (space): {name} ({id})",
    ["debug.map_area"] = "Map area: {name} ({id})",
    ["debug.no_condition"] = "PlayerCondition: not found",
    ["debug.no_player"] = "Player: not found (menu/loading screen?)",
    ["debug.remote"] = "Remote {id} ({name}): {x} {y} {z}  seq {seq}  character {character}  area {area}",
    ["debug.remote_puppet"] = "  In-game character: {text}",
    ["debug.remote_partner"] = "  Real character: {text}",
    ["debug.stats"] = "Sent: {sent} msgs / {sent_bytes} B   Received: {received} msgs / {received_bytes} B",
    ["debug.versions"] = "coopnet {coopnet}   mod {mod}",
    ["debug.puppet_anim_error"] = "ready, animation error: {error}",
    ["debug.puppet_weapon_error"] = "ready, weapon error: {error}",
    ["debug.puppet_animated"] = "ready, animated ({changes} changes, respawned {respawns} x)",
    ["debug.puppet_no_anim"] = "ready, no animation data",
    ["debug.partner_ready"] = "ready, drift {drift} m, {jumps} jumps",
    ["debug.console_off"] = "off",
    ["debug.console_on"] = "on, {count} command(s) run",
    ["debug.console_task"] = ", task running",
    ["debug.console_camera"] = ", own camera on",

    -- Markierung des Mitspielers
    ["ghost.stale"] = "  (no data)",
    ["ghost.other_area"] = "  (other area: {area})",
}
