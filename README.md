# RE:Multiplayer

Koop-Multiplayer-Mods für die Resident-Evil-Reihe. Das Ziel: gemeinsam zu zweit durch die Story. Zuerst für **Resident Evil 2 Remake**, später für weitere Teile.

> **Stand:** Der RE2-Koop läuft im Spiel, ist aber noch in Arbeit (Menü, Positionssync, sichtbarer Mitspieler, Beitreten auf den Stand des Hosts). Ein erster Test mit einem Freund über zwei PCs hat funktioniert. Vieles fehlt noch (Gegner, Items, Kämpfe), siehe [Roadmap](docs/ROADMAP.md).

## Was gibt es?

| Mod | Spiel | Status |
|---|---|---|
| [RE2 Koop](games/re2r/README.md) | Resident Evil 2 (2019) | In Arbeit, spielbar im Test. Mitspieler als sichtbare Figur, Beitreten auf den Stand des Hosts, Menüeintrag „Multiplayer“ im Titelmenü, Deutsch und Englisch |
| [Mod-Manager](tools/modmanager/README.md) | alle | Eine exe zum Installieren, Aktualisieren und Deinstallieren der Mods, Deutsch und Englisch (Version 1.2.0 ist auf `main`, veröffentlicht ist 1.1.1) |
| [RE0 Koop](games/re0hd/README.md) | Resident Evil 0 HD Remaster | Lief im Spiel (Geister-Koop, Stand 0.5.0), **ruht** gerade |

## Installieren

Lade den **Mod-Manager** (`RE-Multiplayer.exe`) unter [Releases](../../releases) herunter. Er findet deine Spiele, installiert die Mods und hält sie aktuell. Die Mods brauchen eine eigene Kopie des Spiels (Steam) und sind nur für den Koop mit Freunden gedacht.

## Projektaufbau

```
RE-Multiplayer/
├── games/                    Spielspezifisches (eine Mod pro Ordner)
│   ├── re2r/
│   │   ├── coop/autorun/     Lua-Skripte der RE2-Koop-Mod
│   │   └── research/         Diagnose-Dateien und Notizen aus dem Spiel
│   └── re0hd/                RE0 HD (32-Bit): Loader, Runtime (C++), Lua-Skripte, Forschung
├── shared/                   Wiederverwendbar für alle Spiele
│   ├── netcore/              C++-Netzwerk-Kern (ENet) + Lua-Anbindung
│   └── re-engine/
│       ├── coopnet-plugin/   REFramework-Plugin (DLL) für alle RE-Engine-Spiele
│       └── lua/remultiplayer_coop/  Gemeinsame Lua-Bibliothek: Protokoll, Sitzung
├── tools/                    remultiplayer_luarun, Testbot (simulierter Mitspieler), modmanager/ (Mod-Manager)
├── tests/                    Automatische Tests (laufen ohne Spiel)
├── third_party/              Fremdbibliotheken (ENet, Lua 5.4.3, REFramework-API, Dear ImGui)
└── docs/                     Architektur, Roadmap, Zusammenarbeit
```

## Dokumentation

- [Handover](HANDOVER.md): Einstieg für eine neue Claude-Session (Stand, nächste Schritte, wichtige Fakten)
- [Architektur](docs/ARCHITEKTUR.md): wie die Teile zusammenspielen und warum
- [Roadmap](docs/ROADMAP.md): Meilensteine für RE2 und Plan für weitere Teile
- [Zusammenarbeit](docs/ZUSAMMENARBEIT.md): wie wir im Duo arbeiten (testen, Diagnose, Rückmeldung)
- [coopnet-Lua-API](docs/coopnet-lua-api.md): Referenz der Plugin-Funktionen

## Bauen

Du musst normalerweise **nichts selbst bauen**: Bei jedem Push baut GitHub Actions automatisch die fertigen Pakete (Reiter **Actions** → letzter Lauf → **Artifacts**).

Selbst bauen (Windows, Visual Studio 2022 mit „Desktopentwicklung mit C++“):

```bat
cmake -S . -B build -A x64
cmake --build build --config Release
ctest --test-dir build -C Release
cmake --install build --config Release --prefix dist/RE2R-Coop --component re2r-coop
```

RE0 HD ist ein 32-Bit-Spiel und braucht einen eigenen Build:

```bat
cmake -S . -B build32 -A Win32
cmake --build build32 --config Release
cmake --install build32 --config Release --prefix dist/RE0HD-Coop --component re0hd-coop
```

Unter Linux laufen die Tests ebenfalls (`cmake -S . -B build && cmake --build build && ctest --test-dir build`). Das Plugin selbst wird nur unter Windows gebaut.

## Regeln

- **Keine Spieldateien ins Repo** (Modelle, Texturen, `.pak`, Exe): nur unser eigener Code und unsere Notizen.
- Mods sind für Einzelspieler-Spiele gedacht, die wir besitzen. Nichts davon zielt auf Online-Modi oder Anti-Cheat.
