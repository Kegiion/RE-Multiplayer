# RE2 Koop (Resident Evil 2, 2019)

Koop-Multiplayer für die Story von Resident Evil 2 Remake.

**Aktueller Stand, Meilenstein 1:** Beide Spieler sehen die Position des anderen als Markierung mit Name und Entfernung. Es gibt noch keine sichtbare zweite Spielfigur und keine synchronisierten Gegner. Beides folgt in den nächsten Meilensteinen, siehe [Roadmap](../../docs/ROADMAP.md).

## Installation

### 1. REFramework installieren (einmalig)
1. Neueste Version von REFramework für RE2 herunterladen: <https://github.com/praydog/REFramework-nightly/releases> (die Datei für RE2, z. B. `RE2.zip`). Wenn du die ältere DX11-Version des Spiels nutzt (Steam-Beta „dx11_non-rt“), nimm die passende TDB-Variante aus den Release-Notizen.
2. Die `dinput8.dll` aus dem Zip in den Spielordner kopieren, also neben `re2.exe`. Den Spielordner findest du über Steam: Rechtsklick auf das Spiel → Verwalten → Lokale Dateien durchsuchen.
3. Spiel starten. Oben links sollte das REFramework-Menü erscheinen. Mit **Einfg** (Insert) klappst du es auf und zu.

### 2. RE2 Koop installieren
1. Auf GitHub im Repo: **Actions** → oberster grüner Lauf → unten bei *Artifacts* **RE2R-Coop** herunterladen.
2. Den Inhalt des Zips **in den Spielordner** entpacken. Danach muss es so aussehen:
   ```
   Resident Evil 2 Biohazard/
   ├── re2.exe
   ├── dinput8.dll
   └── reframework/
       ├── plugins/remods_coopnet.dll
       └── autorun/
           ├── re2r_coop.lua
           ├── re2r_coop/ ...
           └── remods_coop/ ...
   ```
3. Spiel neu starten.

## Erster Test (allein, ca. 10 Minuten)

Bitte gehe diese Liste durch und schreib mir zu jedem Punkt, was passiert ist:

1. **Menü:** REFramework-Menü öffnen (Einfg) → *Script Generated UI* → **RE2 Koop**.
   - Siehst du das Menü? Oder die rote Meldung „Plugin nicht gefunden“?
2. **Spieler finden:** Spielstand laden oder neues Spiel starten. Im Menü **Debug-Infos** anhaken.
   - Steht dort „Spieler: pl…“ mit einer Position?
   - Ändern sich die Zahlen, wenn du herumläufst?
3. **Diagnose:** Einmal im Hauptmenü und einmal im Spiel auf **Diagnose speichern** klicken.
   - Die Datei `reframework/data/re2r_coop_diag.json` an mich weitergeben (siehe [Zusammenarbeit](../../docs/ZUSAMMENARBEIT.md)).
4. **Testbot** (Paket *REMods-Tools* aus denselben Artifacts, irgendwo außerhalb des Spielordners entpacken):
   - Im Spiel auf **Hosten** klicken, dann `testbot.bat` starten.
   - Erscheint im Spiel die Markierung „Testbot“? Läuft sie dir hinterher?
   - Schreib im Menü eine Nachricht. Kommt „Echo: …“ im Log zurück?

Wenn etwas nicht klappt: Datei `re2_framework_log.txt` aus dem Spielordner und den Inhalt des „Log“-Bereichs im Menü schicken.

## Mit einem Mitspieler

- Beide installieren REFramework und RE2 Koop in **derselben Version**.
- Einer klickt **Hosten**, der andere trägt die IP des Hosts ein und klickt **Beitreten**.
- Verbindungsmöglichkeiten (VPN, Portfreigabe): siehe [Zusammenarbeit](../../docs/ZUSAMMENARBEIT.md#mit-einem-echten-mitspieler). Standard-Port: **UDP 27350**.

## Deinstallieren

`reframework/plugins/remods_coopnet.dll`, `reframework/autorun/re2r_coop.lua` sowie die Ordner `re2r_coop/` und `remods_coop/` löschen. Zum Entfernen von REFramework zusätzlich `dinput8.dll` löschen.

## Bekannte offene Punkte

- Klassen- und Methodennamen in `coop/autorun/re2r_coop/game.lua` sind noch nicht im Spiel bestätigt. Genau dafür ist der erste Test da.
- Die Bereichs-ID ist noch leer, deshalb wird der Mitspieler auch angezeigt, wenn er in einem anderen Bereich ist.
