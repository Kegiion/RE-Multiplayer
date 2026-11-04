# Spickzettel (die meistgebrauchten Fakten)

Erst das hier lesen, dann nur die im Auftrag genannten Dateien. Begriffe zuerst per grep suchen.

## Befehle und Pfade

- **Konsole im Spiel (RE2):** Haken „Entwickler-Konsole“ im Mod-Menü, dann `python tools/re2r_console.py "out(game.get_local_state())"` oder `-f befehl.lua`. Ausgabe klein halten, große Dumps in Datei + grep. → [tools/re2r_console.py](../tools/re2r_console.py), [games/re2r/research/README.md](../games/re2r/research/README.md)
- **Testbot (simulierter Mitspieler):** `REMODS_LUA_PATH=<repo>/shared/re-engine/lua/?.lua dist/REMods-Tools/remods_luarun.exe tools/testbot/testbot.lua --host 27352 re2r`. Nach Protokolländerungen Bot neu starten. → [HANDOVER.md](../HANDOVER.md)
- **Ports:** UDP 27350 = Standard (Mod), 27352 = Host-Port des Testbots/Tests mit dem Freund. → [protocol.lua](../shared/re-engine/lua/remultiplayer_coop/protocol.lua)
- **Spielordner:** RE2 `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\`, RE0 `...\common\Resident Evil 0\` (App-ID 339340). → [.claude/CLAUDE.md](../.claude/CLAUDE.md)
- **Im Spiel (RE2):** Lua in `reframework/autorun/`, Daten/JSON in `reframework/data/`, Log `re2_framework_log.txt`. Lua-Änderung: REFramework-Menü → Script Runner → **Reset Scripts**. Menü öffnet mit Einfg.
- **Im Spiel (RE0):** `remultiplayer/autorun/`, `remultiplayer/data/`, Log `remultiplayer/remultiplayer_re0.log`.
- **Lua-Dateien kopieren (ohne Neubau):** `games/re2r/coop/autorun/*` und `shared/re-engine/lua/*` nach `<Spiel>/reframework/autorun/` (inkl. `re2r_coop/lang/`, `remultiplayer_coop/lang/`).

## Bauen und Release

- **Kein Compiler lokal.** CI: `.github/workflows/build.yml`. Artifacts: `gh run download <run-id> -n RE2R-Coop -D <ziel>` (auch `RE0HD-Coop`, `RE-Multiplayer-Tools`). Stand prüfen: `gh run list -L 4`.
- **Release (nur von Hand, nur mit dem User):** `gh workflow run release.yml -f mod=re0hd|re2r|manager [-f prerelease=true]`. Patch Notes aus `## <Version>` in `games/<spiel>/CHANGELOG.md` bzw. `tools/modmanager/CHANGELOG.md` (zweisprachig `### Deutsch` / `### English`). → [.github/workflows/release.yml](../.github/workflows/release.yml)
- **Discord-Patch-Notes:** Nach jedem stabilen Release postet `release.yml` die Notes per Webhook (Secret `DISCORD_PATCHNOTES_WEBHOOK`) in den Patch-Notes-Channel: ein Embed pro Sprache, über ~2700 Zeichen gekürzt mit Link zum Release. Vorabversionen (`prerelease=true`) werden **nicht** gepostet. Fehlt das Secret oder scheitert der Post, läuft das Release trotzdem durch. Vorschau ohne Posten: `gh workflow run discord-preview.yml -f mod=re2r`. → [discord-notes.ps1](../tools/release/discord-notes.ps1)
- **Versionsstellen:** RE2-Mod `MOD_VERSION` in `games/re2r/coop/autorun/re2r_coop.lua`; RE0-Runtime `kRuntimeVersion` in `games/re0hd/runtime/src/runtime.hpp`; Mod-Manager `<Version>` in `tools/modmanager/Directory.Build.props`. Bei jeder Änderung erhöhen.
- **Protokoll:** bestehende Netzwerk-Nachrichten geändert → `protocol.VERSION` erhöhen. → [protocol.lua](../shared/re-engine/lua/remultiplayer_coop/protocol.lua)
- **Tests:** `ctest --test-dir build -C Release --output-on-failure`; Lua-Tests mit `tools/luarun`, Mock `tests/lua/re2r_mock_test.lua`.
- **Nicht aktualisieren:** `third_party/lua` (= REFrameworks Lua 5.4.3).

## REFramework-Fallen

- `os.clock()` ist keine Wanduhr → `coopnet.time()`. Bildzähler taugen nicht (>60 fps).
- Kamera nur vor `LockScene` setzen (`re.on_pre_application_entry`), nicht in `BeginRendering`.
- `draw.*` nur in `re.on_frame`; Farben **ABGR** (`0xAABBGGRR`).
- `json.dump_file`/`load_file`: Pfade relativ zu `reframework/data/`, keine absoluten Pfade, kein `..`.
- Nur `autorun/*.lua` oberster Ebene wird geladen, Unterordner per `require("ordner.modul")`.
- Namespace RE2: `app.ropeway.` (RE3R gleich) → immer `sdk.game_namespace(...)`.
- Gelenke über `Transform:getJointByName(...)`, nicht `Motion:getWorldPosition`.
- Konsole: nur ein `task()` gleichzeitig. Mehrfach Menüs ausblenden + `goResetGameToStoryContinue` hängt das Titelmenü.

Quellen für die Fallen: [HANDOVER.md](../HANDOVER.md), [docs/ARCHITEKTUR.md](ARCHITEKTUR.md).
