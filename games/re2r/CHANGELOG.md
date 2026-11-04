# Patch Notes: Resident Evil 2 Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.10.0

- **Beitreten geht jetzt auch aus dem Titelmenü**, auch aus „Kampagne → Spiel laden“. Vorher lud das Spiel zwar, aber die Menüs blieben über dem Spiel stehen, und man kam scheinbar nicht weiter. Jetzt werden sie nach dem Laden ausgeblendet. Danach funktioniert auch der Weg zurück in den Titel wieder normal.
- Wer noch keinen Spielstand geladen hat, bekommt den Stand des Hosts über seinen neuesten Speicherplatz.
- **Neuer Eintrag „Multiplayer“ im Hauptmenü** (unter „Kampagne“), im Stil des Spiels und mit Tastatur oder Controller bedienbar: Spiel hosten, Beitreten, IP des Hosts und deinen Namen direkt in der Menüzeile eintippen (Enter übernimmt, Esc bricht ab). Die IP wird geprüft (vier Zahlen bis 255). Danach zeigt das Menü, mit wem du verbunden bist und wie weit der Spielstand übertragen ist.
- Falls der Menüeintrag einmal nicht eingebaut werden kann, erscheint stattdessen unten rechts ein kleines Multiplayer-Fenster.

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
