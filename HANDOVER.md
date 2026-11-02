# Handover: REMods (für eine neue Claude-Session)

> Diese Datei ist der Einstieg für eine neue Claude-Session, z. B. lokal auf dem Windows-PC des Users.
> Erst diese Datei lesen, dann `README.md`, `docs/ARCHITEKTUR.md` und `games/re2r/README.md`.

## Wer und was

- **User:** spricht Deutsch, mittlere Programmiererfahrung, besitzt alle RE-Teile (Steam, Windows-PC). Wir arbeiten **im Duo**: Claude schreibt Code, der User testet im Spiel und gibt Rückmeldung.
- **Ziel:** Koop-Multiplayer **durch die Story**, zuerst **Resident Evil 2 Remake (2019)**, später weitere Teile.
- **Repo:** `Kegiion/REMods`, Branch `main`. Hier liegen alle Mods. Keine Spieldateien committen.

## Stand (2. November 2026)

| Bereich | Status |
|---|---|
| Netzwerk-Kern `shared/netcore` (C++, ENet, eigener Thread) | ✅ fertig, getestet (inkl. Thread- und Address-Sanitizer) |
| REFramework-Plugin `remods_coopnet.dll` (spielunabhängig) | ✅ baut (MSVC in CI, MinGW lokal geprüft) |
| Gemeinsame Lua-Bibliothek `remods_coop` (Protokoll, Session) | ✅ getestet |
| RE2-Mod `games/re2r/coop` (Menü, Positionssync, Markierung, Diagnose) | ✅ gegen REFramework-Mock getestet, ❌ **noch nie im echten Spiel gelaufen** |
| Testbot (simulierter Mitspieler) | ✅ getestet |
| CI (GitHub Actions) | ✅ grün, baut die Artifacts `RE2R-Coop` und `REMods-Tools` |

**Meilenstein 1 („Geister-Spieler“)** ist programmiert. Was fehlt, ist der **erste Test im Spiel**.

## Sofort als Nächstes

1. **Erster Test im Spiel.** Die Checkliste steht in `games/re2r/README.md` unter „Erster Test“.
   - REFramework installieren: <https://github.com/praydog/REFramework-nightly/releases>, `dinput8.dll` neben `re2.exe` legen.
   - Paket installieren: Artifact `RE2R-Coop` des neuesten grünen Actions-Laufs in den Spielordner entpacken. Alternativ lokal bauen, siehe unten.
   - Prüfen, ob das Menü „RE2 Koop“ erscheint und ob der Spieler gefunden wird („Debug-Infos“).
   - Diagnose mit Situationen `hauptmenue`, `start` und `anderer_raum` speichern. Die Dateien liegen unter `<Spiel>/reframework/data/re2r_coop_diag_*.json`.
   - Testbot: im Spiel „Hosten“ klicken, dann `testbot.bat` aus `REMods-Tools` starten.
2. **Diagnose-Dateien nach `games/re2r/research/` kopieren und committen**, dann auswerten:
   - Stimmt `PlayerManager.get_CurrentPlayer`? Siehe `player.found` und `player.source`.
   - **Bereichs-ID finden**: In `type_search.Area`, `type_search.Map`, `type_search.Location` und in den beschriebenen Managern unter `types` nach etwas wie „aktuelle Map/Area/Stage“ suchen. Dann `game.get_area()` in `games/re2r/coop/autorun/re2r_coop/game.lua` implementieren.
   - Figur erkennen (Leon/Claire) über `player.object_name` und `game.CHARACTERS` füllen.
   - Bestätigte Fakten in `games/re2r/research/README.md` eintragen.
3. Danach kommt **Meilenstein 2**, die sichtbare zweite Spielfigur (siehe `docs/ROADMAP.md`). Ausgangspunkt ist `player.components` aus der Diagnose sowie die Suchtreffer für `Prefab`, `Spawn` und `Survivor`.

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

## Bauen und testen

```bat
:: Windows (Visual Studio 2022 mit "Desktopentwicklung mit C++")
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --install build --config Release --prefix dist/RE2R-Coop --component re2r-coop
cmake --install build --config Release --prefix dist/REMods-Tools --component tools
```

- `dist/RE2R-Coop/` wird 1:1 in den RE2-Spielordner kopiert. Für reine Lua-Änderungen reicht es, `games/re2r/coop/autorun/*` und `shared/re-engine/lua/*` nach `<Spiel>/reframework/autorun/` zu kopieren.
- Ohne Visual Studio: die Artifacts aus GitHub Actions verwenden (`gh run download -n RE2R-Coop`, falls die GitHub-CLI installiert ist).
- Tests laufen auch unter Linux. Die Lua-Tests nutzen `tools/luarun`, `tests/lua/re2r_mock_test.lua` simuliert die REFramework-API.
- Spielordner (Steam-Standard): `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2\`. Im Zweifel den User fragen oder in Steam → Verwalten → Lokale Dateien nachsehen.
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
