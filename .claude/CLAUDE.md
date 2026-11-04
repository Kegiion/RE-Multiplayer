# RE:Multiplayer – Projektregeln für Claude

Koop-Multiplayer-Mods für Resident-Evil-Spiele. Einstieg für neue Sessions: `HANDOVER.md`, danach `docs/ARCHITEKTUR.md`.

## Zusammenarbeit

- Der User spricht Deutsch und testet im Spiel. Claude schreibt den Code. Antworten auf Deutsch.
- Commit-Nachrichten und Doku auf Deutsch (mit Umlauten). Code-Kommentare auf Deutsch **ohne** Umlaute.
- Nicht im Spiel bestätigte Fakten (Adressen, Klassennamen) im Code und in der Doku als **unbestätigt** markieren. Nichts raten, sondern Diagnose bzw. Cheat Engine nutzen.
- **Lesen mit Maß:** zuerst `docs/cheatsheet.md`, dann nur die im Auftrag genannten Dateien (`HANDOVER.md` nur bei Bedarf).
- Begriffe erst per grep suchen, Dateien nicht ganz lesen. Konsolen-Ausgaben klein halten, große Dumps in eine Datei und dann grep.
- Neue Erkenntnisse in die passende Doku-Datei eintragen (`games/<spiel>/research/README.md`, `docs/`, Spickzettel), nicht nur in den Chat.
- Niemals Spieldateien committen (`*.exe`, `*.pak`, `nativePC/` usw.).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `shared/netcore` | Netzwerk-Kern (C++17, ENet, eigener Thread), stellt die Lua-Tabelle `coopnet` bereit |
| `shared/re-engine/coopnet-plugin` | REFramework-Plugin für RE-Engine-Spiele (x64) |
| `shared/re-engine/lua/remultiplayer_coop` | Gemeinsame Lua-Bibliothek (Protokoll, Session). Wird auch von RE0 genutzt |
| `games/re2r` | RE2 Remake (RE Engine, REFramework, x64) |
| `games/re0hd` | RE0 HD Remaster (MT Framework, **32-Bit**, D3D9). Eigener Loader (`dinput8.dll`) + Runtime `remultiplayer_re0.dll` mit eingebautem Lua und ImGui |
| `third_party` | Fremdbibliotheken als Quellcode (ENet, Lua 5.4.3, REFramework-Header, Dear ImGui) |
| `tools` | `luarun` (Lua-Testläufer), Testbot |
| `tools/modmanager` | Mod-Manager `RE-Multiplayer.exe` (C#, .NET 10, WPF): Spiele finden, Mods aus GitHub-Releases installieren/aktualisieren/deinstallieren, Fehler melden, Selbst-Update. Spiele-Liste `games.json` |
| `tools/release` | `release-meta.ps1` für den Release-Workflow |
| `tests` | ctest: C++- und Lua-Tests (laufen auch unter Linux) |

## Bauen

Auf dem PC des Users gibt es **keinen Compiler**. Gebaut wird über GitHub Actions (`.github/workflows/build.yml`):

- Job `windows` (x64): RE2-Paket `RE2R-Coop` und `RE-Multiplayer-Tools`
- Job `windows-x86`: RE0-Paket `RE0HD-Coop` (nur mit `-A Win32` baubar)
- Job `linux`: Tests

Artifacts holen: `gh run download <run-id> -n RE0HD-Coop -D <ziel>`.

Weitere Workflows:

- `modmanager.yml`: Mod-Manager testen (Linux + Windows) und bauen, Artifact `RE-Multiplayer` (exe) und `RE-Multiplayer-Bilder` (Bildschirmfotos). Läuft nur bei Änderungen unter `tools/modmanager/**` bzw. `tools/release/**`.
- `release.yml` (nur von Hand): `gh workflow run release.yml -f mod=re0hd|re2r|manager [-f prerelease=true]`. Version aus `MOD_VERSION` bzw. `tools/modmanager/Directory.Build.props`, Patch Notes aus dem Abschnitt `## <Version>` in `games/<spiel>/CHANGELOG.md` bzw. `tools/modmanager/CHANGELOG.md`. Der Mod-Manager holt sich darüber Updates.

Lokal (falls Visual Studio vorhanden):

```bat
cmake -S . -B build32 -A Win32
cmake --build build32 --config Release
cmake --install build32 --config Release --prefix dist/RE0HD-Coop --component re0hd-coop
```

## Spielordner (Steam)

- RE2: `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\`
- RE0: `C:\Program Files (x86)\Steam\steamapps\common\Resident Evil 0\` (`re0hd.exe`, App-ID 339340)

## Wichtige Regeln

- `third_party/lua` ist exakt REFrameworks Lua 5.4.3: **nicht aktualisieren** (RE2-Plugin arbeitet auf REFrameworks `lua_State`).
- Bei Änderungen an bestehenden Netzwerk-Nachrichten `protocol.VERSION` erhöhen.
- Vor einem Release den Abschnitt `## <Version>` im passenden `CHANGELOG.md` schreiben (wird zu den Patch Notes im Mod-Manager).
- Mod-Manager: bei jeder Änderung `<Version>` in `tools/modmanager/Directory.Build.props` erhöhen.
- Versionen bei jeder Änderung erhöhen: RE0-Runtime `kRuntimeVersion` (`games/re0hd/runtime/src/runtime.hpp`), Lua-Mods ihr `MOD_VERSION`. Der Git-Commit wird zusätzlich als Build-ID angezeigt.
- Vor jedem Push sollte die CI grün sein. Ohne lokalen Compiler: pushen und den Actions-Lauf prüfen.
