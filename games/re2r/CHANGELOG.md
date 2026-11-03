# Patch Notes: Resident Evil 2 Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.6.0

- **Schießen und Nachladen:** Die Puppe zielt, schießt und lädt nach wie ihr Spieler. Übertragen werden jetzt alle 6 Animations-Ebenen, schnelle Schüsse hintereinander werden einzeln gezählt (im Spiel noch unbestätigt).
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
