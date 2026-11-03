# RE:Multiplayer Mod-Manager

Eine einzige Windows-exe (`RE-Multiplayer.exe`), mit der Spieler alle RE:Multiplayer-Koop-Mods verwalten: Spiele finden, Mods installieren, aktualisieren und deinstallieren, Patch Notes lesen, Fehler melden. Der Manager aktualisiert sich selbst, man muss ihn also nur einmal weitergeben.

**Download:** <https://github.com/Kegiion/RE-Multiplayer/releases/latest/download/RE-Multiplayer.exe>, sobald das Repo öffentlich ist und es ein Manager-Release gibt. Zum Testen liegt die exe als Artifact `RE-Multiplayer` am Lauf des Workflows „Mod-Manager“.

## Für Spieler

1. `RE-Multiplayer.exe` irgendwo hinlegen, z. B. auf den Desktop. Nicht nach *Programme*, dort kann sie sich nicht selbst aktualisieren.
2. Starten. Der Manager findet Steam-Spiele automatisch, auch in weiteren Steam-Bibliotheken. Sonst über **Ordner wählen …** den Spielordner angeben.
3. **Installieren** bzw. **Aktualisieren** klicken. Fehlen Rechte im Spielordner, fragt der Manager, ob er sich als Administrator neu starten soll.
4. Bei Problemen: **Fehler melden**. Die Logs landen als ZIP auf dem Desktop (Benutzername und IP-Adressen entfernt), und GitHub öffnet sich mit einem vorausgefüllten Fehlerbericht. Dafür braucht man ein GitHub-Konto.

Der Manager braucht keine Installation und kein .NET, alles steckt in der exe (ca. 50–70 MB). Er funktioniert auf Windows 10 und 11 (x64).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `games.json` | Liste der unterstützten Spiele (Steam-App-ID, exe, Tag-Präfix, Dateien, Logs). Wird in die exe eingebaut. Zusätzlich lädt der Manager beim Start die aktuelle Fassung aus `main`, neue Spiele brauchen also keine neue exe (solange `schema` gleich bleibt). |
| `src/ModManager.Core` | Logik ohne Oberfläche (.NET 10, läuft auch unter Linux): Steam-Suche (Registry, `libraryfolders.vdf`, `appmanifest_*.acf`), Versionen, GitHub-Releases, Installieren/Deinstallieren, Fehlerbericht, Selbst-Update |
| `src/ModManager.App` | WPF-Oberfläche (`net10.0-windows`), Befehlszeile, Neustart als Administrator |
| `tests/ModManager.Tests` | xUnit-Tests für den Kern |
| `ci/e2e.ps1` | Test der fertigen exe ohne Fenster (Fake-RE0-Ordner) |

### Was beim Installieren passiert

- Das Release-Asset (ZIP, Inhalt = Spielordner) wird von GitHub geladen und mit der SHA-256-Prüfsumme verglichen, die GitHub zu jedem Asset liefert. Erlaubt sind nur HTTPS-Downloads von `github.com`.
- Kein Eintrag im ZIP darf aus dem Spielordner herausführen.
- Eine fremde Loader-DLL (`dinput8.dll` einer anderen Mod) wird als `dinput8.dll.vor-remultiplayer` gesichert und beim Deinstallieren zurückgelegt. Unseren Loader erkennt der Manager am UTF-16-Text `remultiplayer\remultiplayer_re0.dll`, so wie der alte RE0-Installer.
- `KeepPaths` (z. B. `remultiplayer/data`) werden nie gelöscht oder überschrieben.
- Das Protokoll `remultiplayer/remultiplayer-install.json` bzw. `reframework/remultiplayer-install.json` hält Version und Dateiliste fest. Beim Update verschwinden Dateien, die es nicht mehr gibt. Ohne Protokoll (alter Installer, per Hand) deinstalliert der Manager über `legacyFiles`/`legacyDirs`.
- RE2: Fehlt REFramework, lädt der Manager `REFramework.zip` aus dem neuesten Release von `praydog/REFramework-nightly` und kopiert nur `dinput8.dll`. Seit Nightly 01436 gibt es dort keine Pakete pro Spiel mehr (früher `RE2.zip`), `REFramework.zip` enthält einen Build für alle Spiele. Fehlt es, nimmt der Manager die Namen aus `assetFallbacks`. **Unbestätigt:** dass der universelle Build mit RE2 im Spiel läuft. Beim Deinstallieren entfernt er REFramework nur, wenn er es selbst installiert hat. **Unbestätigt:** Für die DX11-Beta des Spiels (`dx11_non-rt`) braucht es eine andere REFramework-Variante, das erkennt der Manager noch nicht.
- RE0: Weicht der PE-Zeitstempel von `re0hd.exe` von den Werten in `supportedExeTimestamps` ab, warnt der Manager vor dem Installieren.

### Befehlszeile

```text
RE-Multiplayer.exe --install re0hd --path "<Spielordner>" --package <zip> [--version x.y.z]
RE-Multiplayer.exe --uninstall re0hd --path "<Spielordner>"
RE-Multiplayer.exe --screenshot bild.png [--demo] [--size 920x660]
```

Exit-Codes ohne Fenster: 0 ok, 1 Fehler, 2 Administratorrechte nötig, 3 falscher Aufruf. Das Log liegt unter `%LOCALAPPDATA%\RE-Multiplayer\manager.log`, die Einstellungen in `settings.json` daneben.

## Releases (für Entwickler)

Der Manager liest die GitHub-Releases dieses Repos. Pro Mod gibt es ein eigenes Tag-Präfix:

| Was | Tag | Asset | Version kommt aus | Patch Notes aus |
|---|---|---|---|---|
| RE0 HD | `re0hd-v0.4.0` | `RE0HD-Coop-0.4.0.zip` | `MOD_VERSION` in `games/re0hd/lua/autorun/re0hd_coop.lua` | `games/re0hd/CHANGELOG.md` |
| RE2 | `re2r-v0.3.1` | `RE2R-Coop-0.3.1.zip` | `MOD_VERSION` in `games/re2r/coop/autorun/re2r_coop.lua` | `games/re2r/CHANGELOG.md` |
| Manager | `manager-v1.0.0` | `RE-Multiplayer.exe` | `<Version>` in `tools/modmanager/Directory.Build.props` | `tools/modmanager/CHANGELOG.md` |

Ablauf: Version erhöhen, im CHANGELOG einen Abschnitt `## <Version>` schreiben, pushen, dann

```bash
gh workflow run release.yml -f mod=re0hd
```

Mit `-f prerelease=true` entsteht eine Beta, die der Manager nur anzeigt, wenn „Beta-Versionen“ angehakt ist. Gibt es das Release schon, bricht der Workflow ab. „Latest“ zeigt immer auf das neueste Manager-Release, damit der Download-Link oben stabil bleibt.

## Bauen

Gebaut wird in GitHub Actions (`.github/workflows/modmanager.yml`), lokal mit .NET-10-SDK:

```bash
dotnet test tools/modmanager/tests/ModManager.Tests
dotnet publish tools/modmanager/src/ModManager.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o dist/RE-Multiplayer
```

Bei jeder Änderung `<Version>` erhöhen und `CHANGELOG.md` ergänzen.
