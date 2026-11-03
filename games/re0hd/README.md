# RE0 HD Koop

Koop-Mod für **Resident Evil 0 HD Remaster** (Steam, `re0hd.exe`).

> **Stand:** Schritt 1 (Runtime mit Menü im Spiel, Lua, Netzwerk) **läuft im Spiel** (getestet am 2. November 2026). Spieldaten (Position, Lebenspunkte von Rebecca und Billy) kennen wir noch nicht.

## Idee

RE0 hat schon zwei Figuren gleichzeitig in der Welt: Rebecca und Billy. Im Koop soll der zweite Spieler einfach den **Partner** steuern. Wir müssen also keine neue Figur erzeugen (wie bei RE2), sondern die Partner-Steuerung übernehmen.

## Technik in Kürze

RE0 HD läuft auf der **MT Framework** (nicht RE Engine), ist ein **32-Bit-Programm** und nutzt **DirectX 9**. REFramework gibt es dafür nicht. Deshalb haben wir einen eigenen kleinen Unterbau:

| Datei im Spielordner | Aufgabe |
|---|---|
| `dinput8.dll` | Loader. Windows lädt sie statt der echten `dinput8.dll`. Sie reicht alles an die echte DLL weiter und lädt `remultiplayer\remultiplayer_re0.dll` |
| `remultiplayer\remultiplayer_re0.dll` | Runtime: Menü im Spiel (Dear ImGui), Lua, Netzwerk (`coopnet`), Speicherzugriff (`mem.*`) |
| `remultiplayer\autorun\*.lua` | Lua-Skripte, werden beim Start automatisch geladen |
| `remultiplayer\lib\json.lua` | JSON-Bibliothek für Konfiguration und Diagnose |
| `remultiplayer\data\` | Konfiguration und Diagnose-Dateien (wird automatisch angelegt) |
| `remultiplayer\remultiplayer_re0.log` | Log der Runtime. **Bei Problemen immer zuerst hier nachsehen** |

Die Lua-API ist der von REFramework nachgebaut (`re.on_frame`, `re.on_draw_ui`, `imgui.*`, `log.*`, `json.*`). Deshalb nutzt RE0 dieselbe Session- und Protokoll-Bibliothek wie RE2 (`remultiplayer_coop`). Die vollständige Liste steht in [runtime/src/lua_host.hpp](runtime/src/lua_host.hpp).

## Installation

1. Neuesten grünen Lauf unter GitHub → Actions öffnen und das Artifact **`RE0HD-Coop`** herunterladen. Alternativ mit der GitHub-CLI:
   ```bash
   gh run download -n RE0HD-Coop -D "C:/Program Files (x86)/Steam/steamapps/common/Resident Evil 0"
   ```
2. Den Inhalt **direkt in den Spielordner** entpacken, sodass `dinput8.dll` neben `re0hd.exe` liegt.
3. Deinstallieren: `dinput8.dll` und den Ordner `remultiplayer` löschen.

## Erster Test (Checkliste)

1. Spiel starten. In den ersten 20 Sekunden erscheint oben links: „RE:Multiplayer RE0 <Version> (Build <Commit>) geladen …“. Der Build ist der Git-Commit, aus dem das Paket gebaut wurde.
   - Erscheint nichts: Gibt es `remultiplayer\remultiplayer_re0.log`?
     - **Nein:** Der Loader wurde nicht geladen. Liegt `dinput8.dll` neben `re0hd.exe`?
     - **Ja:** Die Log-Datei an Claude geben.
2. **Einfg** oder **F8** drücken. Das Menü „RE:Multiplayer – Resident Evil 0 HD“ öffnet sich.
   - Funktioniert die Maus im Menü? Lässt sich in „Dein Name“ tippen?
   - Läuft das Spiel noch flüssig?
3. Im Menü auf **„Skripte neu laden“** klicken. Es sollten keine roten Fehler erscheinen.
4. Vollbild/Fenster umschalten oder Alt+Tab. Stürzt das Spiel ab, ist das Menü danach noch da?
5. Netzwerk-Test mit dem Testbot (aus dem Artifact `RE-Multiplayer-Tools`):
   - Im Menü unter „RE0 Koop“ auf **Hosten** klicken.
   - In einer Eingabeaufforderung im Tools-Ordner `testbot.bat 127.0.0.1 27350 re0hd` starten.
   - Im Menü sollte „Mitspieler: …“ erscheinen. Ohne den Parameter `re0hd` meldet sich der Bot als RE2-Spieler, dann ist „falsches Spiel“ im Log richtig.
6. Spiel beenden und `remultiplayer\remultiplayer_re0.log` an Claude geben (bzw. nach `games/re0hd/research/` kopieren).

## Koop spielen (Stand Mod 0.6.0)

Beide brauchen RE0 HD in derselben Version mit derselben Mod (Mod-Manager). Jeder spielt in seinem eigenen Spiel, aber vom **selben Spielstand** aus.

1. Der Host speichert an einer Schreibmaschine oder lädt einen Spielstand. Diesen Platz bekommt der Mitspieler.
2. Der Host klickt im Menü unter „RE0 Koop“ auf **Hosten**. Der Mitspieler trägt die IP des Hosts ein und klickt auf **Beitreten**. Außerhalb des eigenen Netzes: virtuelles LAN (z. B. Tailscale) oder UDP-Port 27350 im Router freigeben.
3. **Join auf den Spielstand des Hosts:** Der Mitspieler klickt auf **„Spielstand vom Host holen“**. Die Mod legt ihn in Platz 20 (einstellbar) und hält ihn dort. Danach im Titelbildschirm **Spiel laden → Platz 20**. Der Platz wird nur im Arbeitsspeicher ersetzt; speichert der Mitspieler danach, landet er auch in seiner Spielstand-Datei.
4. Jeder steuert eine **andere** Figur: Einer wechselt mit **V** auf Billy. Das Menü warnt, wenn ihr beide dieselbe Figur steuert.
5. In jedem Spiel läuft jetzt der Partner dem Weg des Mitspielers nach. Seid ihr in verschiedenen Räumen, übernimmt die Spiel-KI den Partner.

**Einschränkungen:** Gegner, Items und Türen werden noch nicht abgeglichen. Der Mitspieler bekommt den letzten gespeicherten Stand, nicht den Fortschritt seit dem Speichern.

**Allein testen:** Haken bei **„Spur-Test allein“** setzen. Dann läuft dir der Partner mit 2 Sekunden Abstand auf deinem eigenen Weg nach, genau wie später beim Mitspieler.

## Forschung: MT-Explorer (ab Runtime 0.2.0)

MT Framework hat ein eigenes Typsystem (DTI): Jede Klasse hat einen Namen wie `uPlayerRebecca`, und jedes Objekt verrät seine Klasse. Der Explorer nutzt das. Er steht im Menü unter **RE0 Koop → MT-Explorer (Forschung)**:

1. Im Spiel an die gewünschte Stelle gehen, dann **Speicher durchsuchen** klicken. Das Spiel stockt dabei kurz.
2. Klasse suchen (oder Schnellwahl, z. B. `uPlayerRebecca`) und ein Objekt anklicken.
3. Die Objekt-Ansicht zeigt die Daten live an. Gelb markiert sind Werte, die sich gerade geändert haben. Mit **>** folgst du einem Zeiger auf ein anderes Objekt.
4. **Schnappschuss speichern** mit einer kurzen Beschreibung („rebecca_steht“, „rebecca_laeuft_vor“). Claude wertet die Dateien in `remultiplayer/data/` direkt aus.
5. **Klassenliste speichern** schreibt alle gefundenen Klassen mit Anzahl der Objekte nach `remultiplayer/data/re0hd_classes.json`.

## Forschung: Spieldaten finden

Die Adressen für Position und Lebenspunkte suchen wir mit **Cheat Engine**. Danach prüfen wir sie im Menü unter **RE0 Koop → Speicher-Werkzeug**:

- **Adresse:** `re0hd.exe+1A2B` (Modul + Offset) oder als Zeiger-Kette `re0hd.exe+1A2B, 10, 4`. Das entspricht einem Cheat-Engine-Pointer mit Basis `re0hd.exe+1A2B` und den Offsets 10 und 4. Alle Zahlen sind hexadezimal.
- **Typ** auswählen (`f32` für Positionen, meist `i32`/`u16` für Lebenspunkte).
- **Merken** setzt den Wert auf die Merkliste. Er wird live angezeigt und bleibt gespeichert.
- **Diagnose speichern** schreibt alle Werte der Merkliste mit Spielversion nach `remultiplayer/data/re0hd_diag_<situation>.json`.

Bestätigte Fakten kommen nach [research/README.md](research/README.md).
