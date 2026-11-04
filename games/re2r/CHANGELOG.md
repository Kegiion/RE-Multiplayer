# Patch Notes: Resident Evil 2 Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.11.3

### Deutsch

- Titelmenü „Multiplayer“: Die oberste Zeile zeigte manchmal „Kampagne“ statt des Verbindungsstatus. Behoben.
- Die Zeile „Sprache“ im Titelmenü ist weg. Die Mod nimmt immer die Sprache des Spiels (Deutsch, sonst Englisch).
- Esc beendet die Eingabe von Name oder IP jetzt zuverlässig.
- Nach „Reset Scripts“ reagiert das Titelmenü wieder auf Tasten (die Sperre aus der Texteingabe blieb vorher stehen).
- Kein Skriptfehler „invalid REManagedObject field mVersion“ mehr beim Einspielen des Host-Stands.

### English

- Title menu "Multiplayer": the top row sometimes showed "Campaign" instead of the connection status. Fixed.
- The "Language" row in the title menu is gone. The mod always uses the game's language (German, otherwise English).
- Esc now reliably ends typing a name or IP.
- After "Reset Scripts" the title menu reacts to keys again (the lock from text input used to stay).
- No more script error "invalid REManagedObject field mVersion" when applying the host's save.

## 0.11.2

### Deutsch

- Die Meldungen beim Beitreten (Spielstand des Hosts holen, empfangen, einspielen, automatisch laden) sind jetzt auch auf Englisch da und wechseln beim Umschalten der Sprache sofort mit.

### English

- The messages while joining (getting, receiving, applying and automatically loading the host's save) are now available in English too and follow a language switch right away.

## 0.11.1

### Deutsch

- Auch die letzten Texte der Debug-Infos sind jetzt übersetzt: Zustand und Fehler der Mitspieler-Figur, Fehler des Titelmenüs und der Ersatzname über der Markierung des Mitspielers („Spieler 2“).
- Ein neuer Test prüft, dass jeder Text, den die Mod anzeigt, in beiden Sprachen vorhanden ist.

### English

- The last remaining texts in the debug info are now translated as well: state and errors of the partner character, title menu errors and the fallback name above the partner marker ("Player 2").
- A new test checks that every text the mod shows exists in both languages.

## 0.11.0

### Deutsch

- **Die Mod spricht jetzt Deutsch und Englisch.** Alle Texte im Einfg-Menü, im Multiplayer-Menü des Titelbildschirms, im Titel-Fenster und im Log gibt es in beiden Sprachen.
- **Sprache umschalten:** im Einfg-Menü unter „Sprache / Language“ oder im Titelmenü unter Multiplayer → „Sprache“. Zur Wahl stehen Automatisch, English und Deutsch. Die Wahl wird gespeichert.
- „Automatisch“ nimmt die Textsprache des Spiels. Bisher ist nur Deutsch sicher erkannt, alle anderen Spielsprachen zeigen vorerst Englisch.

### English

- **The mod now speaks English and German.** All texts in the Insert menu, in the Multiplayer menu on the title screen, in the title window and in the log are available in both languages.
- **Switch language:** in the Insert menu under "Language / Sprache" or on the title screen under Multiplayer → "Language". Choose Automatic, English or Deutsch. Your choice is saved.
- "Automatic" uses the game's text language. So far only German is detected for sure, all other game languages show English for now.

## 0.10.0

### Deutsch

- **Beitreten geht jetzt auch aus dem Titelmenü**, auch aus „Kampagne → Spiel laden“. Vorher lud das Spiel zwar, aber die Menüs blieben über dem Spiel stehen, und man kam scheinbar nicht weiter. Jetzt werden sie nach dem Laden ausgeblendet. Danach funktioniert auch der Weg zurück in den Titel wieder normal.
- Wer noch keinen Spielstand geladen hat, bekommt den Stand des Hosts über seinen neuesten Speicherplatz.
- **Neuer Eintrag „Multiplayer“ im Hauptmenü** (unter „Kampagne“), im Stil des Spiels und mit Tastatur oder Controller bedienbar: Spiel hosten, Beitreten, IP des Hosts und deinen Namen direkt in der Menüzeile eintippen (Enter übernimmt, Esc bricht ab). Die IP wird geprüft (vier Zahlen bis 255). Danach zeigt das Menü, mit wem du verbunden bist und wie weit der Spielstand übertragen ist.
- Falls der Menüeintrag einmal nicht eingebaut werden kann, erscheint stattdessen unten rechts ein kleines Multiplayer-Fenster.

### English

- **Joining now also works from the title menu**, including "Campaign → Load Game". Before, the game loaded but the menus stayed on top of the game and it seemed stuck. Now they are hidden after loading, and going back to the title works normally again.
- If you have not loaded a save yet, the host's state is applied via your most recent save slot.
- **New "Multiplayer" entry in the main menu** (below "Campaign"), in the game's style and usable with keyboard or controller: host a game, join, type the host IP and your name directly in the menu line (Enter confirms, Esc cancels). The IP is checked (four numbers up to 255). Afterwards the menu shows who you are connected to and how far the save transfer is.
- If the menu entry cannot be added, a small Multiplayer window appears in the bottom right corner instead.

## 0.9.1

- Wer im Titelmenü beitritt, wird nicht mehr automatisch geladen (dabei kam man nicht ins Spiel). Stattdessen steht im Menü „Lade zuerst einen eigenen Spielstand“, danach geht es von selbst weiter.

## 0.9.0

- **Beitreten geht jetzt von selbst:** Wer beitritt, bekommt automatisch den Spielstand des Hosts. Das Spiel geht kurz über den Titelbildschirm, lädt und setzt dich beim Host ab. Abschaltbar mit dem Haken „Beim Beitreten automatisch laden“. Voraussetzung: Du hast in dieser Sitzung schon einmal einen eigenen Spielstand geladen.

## 0.8.0

- **Dem Spielstand des Hosts beitreten:** Wer beitritt, findet im Menü „Spielstand des Hosts holen“. Der Host schickt seinen aktuellen Stand (ohne zu speichern, ca. 1 MB). Danach lädt der Mitspieler im Pausenmenü einen beliebigen eigenen Spielstand und landet beim Host: gleicher Ort, Inventar, Kiste, Gegner, Story-Fortschritt.
- Noch offen: Rätsel- und Schalterzustände, die es im geladenen Stand des Mitspielers noch gar nicht gibt, bleiben im Grundzustand. Getestet ist der Ablauf mit dem Testbot auf einem PC, noch nicht zwischen zwei PCs.
- Für Tests: Der Testbot kann mit `--host` selbst hosten und spiegelt den Spielstand des Spiels zurück.

## 0.7.1

- Die echte Spielfigur des Mitspielers wird sanft auf seine Position nachgezogen, statt ständig zu springen.
- Die Laufrichtung stimmt jetzt auch, wenn einer von euch beim Laufen die Kamera dreht.

## 0.7.0

- **Versuch: Mitspieler als echte Spielfigur.** Neuer Haken im Menü (standardmäßig aus, vorher speichern). Statt der Puppe wird die echte, spielbare Figur des Mitspielers erzeugt, und das Spiel steuert sie mit seinen eigenen Abläufen. Die Tasten und Sticks kommen vom Mitspieler. Noch ungetestet im Spiel: Kamera-Umrechnung der Sticks, Positionskorrektur, Kamera, HUD, Inventar und Gegner.
- Die eigenen Eingaben werden bis 60× pro Sekunde mitgeschickt (neue Nachricht `INPUT_STATE`). Die Protokollversion bleibt 3.
- Der Testbot schickt auch die Eingaben verzögert zurück.

## 0.6.0

- **Schießen und Nachladen:** Die Puppe zielt, schießt und lädt nach wie ihr Spieler. Übertragen werden jetzt alle 6 Animations-Ebenen, schnelle Schüsse hintereinander kommen einzeln an.
- **Waffe in der Hand:** Die Puppe hält das Modell der Waffe, die ihr Spieler gerade trägt. Es ist nur das Modell, Schussgeräusch, Mündungsfeuer und Treffer fehlen noch.
- **Neue Protokollversion 3:** Beide Spieler brauchen RE2 Koop 0.6.0.
- Für die Entwicklung: Die Entwickler-Konsole kann die Kamera steuern, `tools/spielfoto.ps1` macht Bildschirmfotos des Spielfensters.

## 0.5.0

- **Animationen:** Die Puppe des Mitspielers geht, joggt, zielt und dreht sich jetzt mit, statt zu gleiten. Übertragen werden die Animationsdateien der Figur, die laufenden Animationen samt Überblendung und die Steuer-Variablen (Laufrichtung, Blickrichtung, Treppe, Zielhöhe).
- Die Puppe springt und verschwindet nicht mehr: Sie liegt jetzt im Ordner des Spielers, den das Spiel beim Nachladen nicht aufräumt. Ihre Drehung wird geglättet.
- Schießen, Nachladen und Treffer werden noch nicht übertragen.
- **Neue Protokollversion 2:** Beide Spieler brauchen RE2 Koop 0.5.0.
- Der Testbot spielt auch die Animationen nach.

## 0.4.2

- **Neuer Name: RE:Multiplayer.** Das Plugin heißt jetzt `reframework/plugins/remultiplayer_coopnet.dll`, die Lua-Bibliothek `reframework/autorun/remultiplayer_coop/`. Die alten Dateien entfernt der Mod-Manager beim Aktualisieren.
- **Mitspieler als Spielfigur** (Meilenstein 2): Der Mitspieler ist als Puppe in der Welt zu sehen (seit 0.4.0).
- Der Haken für die Entwickler-Konsole bleibt nach „Reset Scripts“ erhalten (0.4.1).
- Zonenwechsel bis zur Polizeistation geprüft (0.3.2).

## 0.3.1

- **Geister-Spieler:** Der Mitspieler erscheint als Markierung im Spiel, seine Position wird übertragen.
- Figur (Leon) und Bereich werden erkannt und angezeigt.
- Entwickler-Konsole für die Fehlersuche.
