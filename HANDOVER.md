# Handover: REMods (für eine neue Claude-Session)

> Diese Datei ist der Einstieg für eine neue Claude-Session, z. B. lokal auf dem Windows-PC des Users.
> Erst diese Datei lesen, dann `README.md`, `docs/ARCHITEKTUR.md` und `games/re2r/README.md`.

## Wer und was

- **User:** spricht Deutsch, mittlere Programmiererfahrung, besitzt alle RE-Teile (Steam, Windows-PC). Wir arbeiten **im Duo**: Claude schreibt Code, der User testet im Spiel und gibt Rückmeldung.
- **Ziel:** Koop-Multiplayer **durch die Story**. Parallel in Arbeit: **Resident Evil 2 Remake (2019)** und **Resident Evil 0 HD Remaster** (Partner-Koop). Später weitere Teile.
- **Repo:** `Kegiion/REMods`, Branch `main`. Hier liegen alle Mods. Keine Spieldateien committen.

## Stand (2. November 2026)

| Bereich | Status |
|---|---|
| Netzwerk-Kern `shared/netcore` (C++, ENet, eigener Thread) | ✅ fertig, getestet (inkl. Thread- und Address-Sanitizer) |
| REFramework-Plugin `remods_coopnet.dll` (spielunabhängig) | ✅ baut (MSVC in CI, MinGW lokal geprüft) |
| Gemeinsame Lua-Bibliothek `remods_coop` (Protokoll, Session) | ✅ getestet |
| RE2-Mod `games/re2r/coop` (Menü, Positionssync, Markierung, Diagnose) | ✅ **läuft im Spiel** (erster Test am 2. November 2026: Menü, Spieler `pl0000`, Diagnose, Testbot läuft hinterher). Mod 0.2.0: Figur und Bereich, im Spiel noch ungeprüft |
| Testbot (simulierter Mitspieler) | ✅ getestet |
| CI (GitHub Actions) | baut die Artifacts `RE2R-Coop`, `REMods-Tools` und `RE0HD-Coop` (eigener Win32-Job) |
| RE0-Loader `dinput8.dll` + Runtime `remods_re0.dll` (32-Bit, D3D9-Hook, ImGui-Menü, Lua, `coopnet`, `mem.*`) | ✅ **läuft im Spiel** (erster Test am 2. November 2026: Menü, Eingabe, Neu laden, Alt+Tab, Testbot ok) |
| RE0-Skript `games/re0hd/lua` (Verbindung, Chat, Speicher-Werkzeug, Diagnose) | ✅ gegen Mock getestet (`tests/lua/re0hd_mock_test.lua`) |

**Meilenstein 1 („Geister-Spieler“)** läuft in RE2 im Spiel. Offen sind die Prüfung von Figur und Bereich (Mod 0.2.0) und ein Test mit einem echten Mitspieler.

## Sofort als Nächstes

**RE0 HD:** Schritt 1 läuft im Spiel. Als Nächstes Schritt 2: mit Cheat Engine Position, Lebenspunkte und die aktive Figur suchen und im Menü mit dem Speicher-Werkzeug prüfen (Fakten in `games/re0hd/research/README.md`). Wunsch des Users: Ultrawide-Fix für seinen 32:9-Monitor (siehe `docs/ROADMAP.md`).

**RE2:**

1. ✅ Erster Test im Spiel (2. November 2026). Die Diagnose-Dateien liegen in `games/re2r/research/`, die Auswertung steht in `games/re2r/research/README.md`.
2. ✅ Figur und Bereich (Mod 0.3.1): Leon = `SurvivorType` 0 (`PL0000`), Bereich = `Map.ID`-Zone (z. B. `st1_411_0`). Offen: einen Zonenwechsel beobachten und Claire bestätigen.
   Seit Mod 0.3.0 gibt es dafür die **Entwickler-Konsole**: Ist sie im Menü angehakt, führt `python tools/re2r_console.py "<lua>"` Code im laufenden Spiel aus (Details in `games/re2r/research/README.md`).
3. Danach kommt **Meilenstein 2**, die sichtbare zweite Spielfigur (siehe `docs/ROADMAP.md`). Ausgangspunkt ist `player.components` aus der Diagnose sowie die Kandidaten in `games/re2r/research/README.md`.

## Wichtige technische Fakten (nicht neu herausfinden)

- **Architektur:** Die C++-DLL macht nur das Netzwerk und stellt die globale Lua-Tabelle `coopnet` bereit. Die gesamte Spiellogik liegt in Lua unter `reframework/autorun/`. Lua-Änderungen testet der User per REFramework-Menü → Script Runner → **Reset Scripts**. Die Verbindung bleibt dabei erhalten, weil die Session im Plugin lebt und HELLO mit `want_reply` neu synchronisiert.
- **Lua 5.4.3 in `third_party/lua` ist exakt REFrameworks Kopie.** Das Plugin arbeitet auf REFrameworks `lua_State`, deshalb **nicht aktualisieren**. Das offizielle REFramework-Beispiel-Plugin macht es genauso.
- Plugin-API: Das Plugin fordert Version 1.0 an (nur Major muss passen) und nutzt `param->sdk` (TDB, Singletons). Beides gibt es seit API 1.0.
- `coopnet.find_types(text)` und `coopnet.list_singletons()` gibt es nur im Spiel. In REFramework-Lua kann man nicht alle Klassen auflisten, deshalb liefert das Plugin diese Funktionen über die C-API.
- REFramework-Lua lädt nur `autorun/*.lua` auf oberster Ebene. Unterordner werden per `require("ordner.modul")` geladen.
- RE2R-Namespace: `app.ropeway.` (RE3R nutzt denselben!). Im Code immer `sdk.game_namespace(...)` verwenden.
- `draw.*` funktioniert nur in `re.on_frame`. Farben sind ABGR (`0xAABBGGRR`).
- `json.dump_file` und `json.load_file` arbeiten relativ zu `reframework/data/`. Absolute Pfade und `..` sind nicht erlaubt.
- Standard-Port: **UDP 27350**. Story-Koop ist für 2 Spieler ausgelegt (`max_peers = 1`). Der Host besitzt die Welt.
- Protokoll: `shared/re-engine/lua/remods_coop/protocol.lua`. Bei Änderungen an bestehenden Nachrichten `protocol.VERSION` erhöhen.

## Wichtige Fakten zu RE0 HD

- `re0hd.exe` ist **32-Bit**, MT Framework, D3D9 (`Direct3DCreate9`, kein Ex). Sie importiert `dinput8.dll`. Darüber läuft unser Loader.
- Kein REFramework. Unsere Runtime bildet dessen Lua-API teilweise nach (`re`, `imgui`, `log`, `json`), damit `remods_coop` unverändert läuft. Dazu kommen `mem.*` (lesen, schreiben, `scan` für Byte-Muster) und `remods.*`.
- Lua-Skripte liegen im Spiel unter `remods/autorun/`, Daten unter `remods/data/`, das Log unter `remods/remods_re0.log`. Der Button „Skripte neu laden“ im Menü entspricht „Reset Scripts“ in REFramework.
- Adressen hängen von der exe-Version ab. Der PE-Zeitstempel steht im Log und in jeder Diagnose-Datei.

## Bauen und testen

**Auf dem PC des Users gibt es keinen Compiler.** Pushen, dann das Artifact holen: `gh run download <run-id> -n RE0HD-Coop -D <ziel>`. Die GitHub-CLI ist installiert.

```bat
:: Windows (Visual Studio 2022 mit "Desktopentwicklung mit C++")
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --install build --config Release --prefix dist/RE2R-Coop --component re2r-coop
cmake --install build --config Release --prefix dist/REMods-Tools --component tools

:: RE0 HD (32-Bit)
cmake -S . -B build32 -A Win32
cmake --build build32 --config Release
cmake --install build32 --config Release --prefix dist/RE0HD-Coop --component re0hd-coop
```

- `dist/RE2R-Coop/` wird 1:1 in den RE2-Spielordner kopiert. Für reine Lua-Änderungen reicht es, `games/re2r/coop/autorun/*` und `shared/re-engine/lua/*` nach `<Spiel>/reframework/autorun/` zu kopieren.
- Ohne Visual Studio: die Artifacts aus GitHub Actions verwenden (`gh run download -n RE2R-Coop`, falls die GitHub-CLI installiert ist).
- Tests laufen auch unter Linux. Die Lua-Tests nutzen `tools/luarun`, `tests/lua/re2r_mock_test.lua` simuliert die REFramework-API.
- Spielordner (Steam-Standard): `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\`, RE0: `...\common\Resident Evil 0\`. Im Zweifel den User fragen oder in Steam → Verwalten → Lokale Dateien nachsehen.
- REFramework-Log: `<Spiel>/re2_framework_log.txt`

## Offene Design-Fragen an den User (noch unbeantwortet)

1. Figuren: Spielt der Zweite Leon, wenn der Host Claire spielt? Dieselbe Figur doppelt? Ada oder Sherry?
2. Dürfen sich die Spieler in verschiedene Bereiche bewegen, oder wird der Zweite beim Bereichswechsel mitgezogen?
3. Items: geteiltes oder eigenes Inventar? Was passiert mit Schlüssel-Items?
4. Mr. X: Wen verfolgt er?
5. Tod: Game Over für beide oder Wiederbeleben?
6. Schwierigkeit im Koop erhöhen?

Antworten in `docs/ROADMAP.md` eintragen.

## Arbeitsweise

- Commit-Nachrichten auf Deutsch, Code-Kommentare auf Deutsch (ohne Umlaute im Code), Doku mit Umlauten.
- Vor jedem Push: bauen und `ctest` laufen lassen.
- Dinge, die im Spiel noch nicht bestätigt sind, im Code und in der Doku als unbestätigt markieren. Keine Namen raten, ohne die Diagnose zu nutzen.
