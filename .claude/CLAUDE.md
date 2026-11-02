# REMods – Projektregeln für Claude

Koop-Multiplayer-Mods für Resident-Evil-Spiele. Einstieg für neue Sessions: `HANDOVER.md`, danach `docs/ARCHITEKTUR.md`.

## Zusammenarbeit

- Der User spricht Deutsch und testet im Spiel. Claude schreibt den Code. Antworten auf Deutsch.
- Commit-Nachrichten und Doku auf Deutsch (mit Umlauten). Code-Kommentare auf Deutsch **ohne** Umlaute.
- Nicht im Spiel bestätigte Fakten (Adressen, Klassennamen) im Code und in der Doku als **unbestätigt** markieren. Nichts raten, sondern Diagnose bzw. Cheat Engine nutzen.
- Niemals Spieldateien committen (`*.exe`, `*.pak`, `nativePC/` usw.).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `shared/netcore` | Netzwerk-Kern (C++17, ENet, eigener Thread), stellt die Lua-Tabelle `coopnet` bereit |
| `shared/re-engine/coopnet-plugin` | REFramework-Plugin für RE-Engine-Spiele (x64) |
| `shared/re-engine/lua/remods_coop` | Gemeinsame Lua-Bibliothek (Protokoll, Session). Wird auch von RE0 genutzt |
| `games/re2r` | RE2 Remake (RE Engine, REFramework, x64) |
| `games/re0hd` | RE0 HD Remaster (MT Framework, **32-Bit**, D3D9). Eigener Loader (`dinput8.dll`) + Runtime `remods_re0.dll` mit eingebautem Lua und ImGui |
| `third_party` | Fremdbibliotheken als Quellcode (ENet, Lua 5.4.3, REFramework-Header, Dear ImGui) |
| `tools` | `luarun` (Lua-Testläufer), Testbot |
| `tests` | ctest: C++- und Lua-Tests (laufen auch unter Linux) |

## Bauen

Auf dem PC des Users gibt es **keinen Compiler**. Gebaut wird über GitHub Actions (`.github/workflows/build.yml`):

- Job `windows` (x64): RE2-Paket `RE2R-Coop` und `REMods-Tools`
- Job `windows-x86`: RE0-Paket `RE0HD-Coop` (nur mit `-A Win32` baubar)
- Job `linux`: Tests

Artifacts holen: `gh run download <run-id> -n RE0HD-Coop -D <ziel>`.

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
- Vor jedem Push sollte die CI grün sein. Ohne lokalen Compiler: pushen und den Actions-Lauf prüfen.
