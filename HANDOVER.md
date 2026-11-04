# Handover: RE:Multiplayer (für eine neue Claude-Session)

> Einstieg: erst [docs/cheatsheet.md](docs/cheatsheet.md) (Befehle, Pfade, Ports, Versionen, Fallen), dann diese Datei nur bei Bedarf, dann [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md).

## Wer und was

- **User:** spricht Deutsch, mittlere Programmiererfahrung, besitzt alle RE-Teile (Steam, Windows-PC). Duo: Claude schreibt Code, der User testet im Spiel.
- **Ziel:** Koop-Multiplayer **durch die Story**. Fokus jetzt: alle RE-Engine-Spiele, **RE2 Remake zuerst**. RE0 HD ruht (darf brechen, CI bleibt grün). Umfang: nur Remakes und Teile ohne Remake (siehe [docs/ROADMAP.md](docs/ROADMAP.md)).
- **Repo:** `Kegiion/RE-Multiplayer`, Branch `main`. Keine Spieldateien committen.
- RE2 wird von einem Projektleiter-Chat geführt, der Unterchats startet. Aktueller Stand und Aufträge: siehe private Notizen (nicht im Repo).

## Stand (4. November 2026)

| Bereich | Status |
|---|---|
| Netzwerk-Kern `shared/netcore`, Plugin `remultiplayer_coopnet.dll`, Lua-Bibliothek `remultiplayer_coop` | ✅ fertig, getestet |
| **RE2 Koop 0.11.x** (`games/re2r/coop`) | ✅ im Spiel: Menü, Positionssync, sichtbare Puppe mit Animationen, **Join auf den Stand des Hosts** (`savejoin.lua`), Menüeintrag **„Multiplayer“** im Titelmenü, **Deutsch/Englisch** (`re2r_coop/lang/`). Erster Test mit Freund über zwei PCs lief, Release `re2r-v0.9.0` ist draußen, 0.10.x/0.11.x noch nicht veröffentlicht |
| **Mod-Manager 1.2.0** (`tools/modmanager`, .NET 10 WPF) | ✅ Deutsch/Englisch, zweisprachige Patch Notes, auf `main`, CI grün, noch nicht veröffentlicht. Doku: `tools/modmanager/README.md` |
| RE0 HD (Loader `dinput8.dll` + Runtime, Lua-Skript, Geister-Koop) | ✅ lief im Spiel (Mod 0.5.0), **ruht** |
| Testbot, CI (`RE2R-Coop`, `RE-Multiplayer-Tools`, `RE0HD-Coop`, Mod-Manager) | ✅ |

## Sofort als Nächstes (RE2)

Details und Reihenfolge stehen in der Übergabe-Datei und in [docs/ROADMAP.md](docs/ROADMAP.md).

1. Ende-zu-Ende-Test „Multiplayer“ im Titelmenü mit gültigem Stand, danach Release für den Test mit dem Freund (nur mit dem User).
2. Beim Beitreten: Inventar und Kiste vom Host, andere Hauptfigur als der Host (eigener Skin darf bleiben).
3. Englisch-Gegenprobe L1 (`GUISystem.get_MessageLanguage`: Deutsch = 4 bestätigt, Englisch = 1 erwartet).
4. Danach: Schießen/Nachladen/Treffer der Puppe, Claire, Gegner, Tod und Items (Konzept: `docs/re2r-konzept-gegner-tod-items.md`).

Design-Entscheidungen RE2 (ROADMAP, „Design-Entscheidungen“): Mitspieler = andere Hauptfigur, freie Bewegung mit Host-Welt, eigenes Inventar mit geteilten Schlüssel-Items, Mr. X jagt den Näheren, Wiederbeleben mit Frist, Schwierigkeit später einstellbar.

## Technische Fakten (nicht neu herausfinden)

- **Architektur:** Die C++-DLL macht nur das Netzwerk und stellt die Lua-Tabelle `coopnet` bereit (`find_types`, `list_singletons` nur im Spiel). Die Spiellogik liegt in Lua unter `reframework/autorun/`. Die Session lebt im Plugin, deshalb übersteht die Verbindung „Reset Scripts“.
- `third_party/lua` ist exakt REFrameworks Lua 5.4.3: **nicht aktualisieren**. Plugin-API 1.0 (nur Major muss passen), `param->sdk` für TDB und Singletons.
- Story-Koop für 2 Spieler (`max_peers = 1`), der Host besitzt die Welt. Protokoll: `shared/re-engine/lua/remultiplayer_coop/protocol.lua`.
- Weitere REFramework-Fallen (os.clock, Kamera, ABGR, json-Pfade, autorun): siehe [Spickzettel](docs/cheatsheet.md).
- **RE0 HD:** `re0hd.exe` ist 32-Bit, MT Framework, D3D9, importiert `dinput8.dll` (darüber läuft der Loader). Kein REFramework; die Runtime bildet dessen Lua-API teilweise nach (`re`, `imgui`, `log`, `json`) plus `mem.*` und `remultiplayer.*`. Adressen hängen vom PE-Zeitstempel ab (steht im Log). Fakten: `games/re0hd/research/README.md`.

## Bauen und testen

Auf dem PC des Users gibt es **keinen Compiler**: pushen, CI abwarten, Artifact holen (Befehle im Spickzettel). Lokal mit Visual Studio 2022:

```bat
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --install build --config Release --prefix dist/RE2R-Coop --component re2r-coop
:: RE0 (32-Bit): cmake -S . -B build32 -A Win32, --component re0hd-coop
```

Tests laufen auch unter Linux (`tools/luarun`, `tests/lua/re2r_mock_test.lua` simuliert die REFramework-API).

## Arbeitsweise

- Commits und Doku auf Deutsch (mit Umlauten), Code-Kommentare auf Deutsch ohne Umlaute.
- Vor jedem Push bauen/`ctest` bzw. CI prüfen. Nicht bestätigte Fakten als **unbestätigt** markieren, nichts raten (Diagnose, Konsole).
