# Patch Notes: Resident Evil 2 Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.4.2

- **Neuer Name: RE:Multiplayer.** Das Plugin heißt jetzt `reframework/plugins/remultiplayer_coopnet.dll`, die Lua-Bibliothek `reframework/autorun/remultiplayer_coop/`. Die alten Dateien entfernt der Mod-Manager beim Aktualisieren.
- **Mitspieler als Spielfigur** (Meilenstein 2): Der Mitspieler ist als Puppe in der Welt zu sehen (seit 0.4.0).
- Der Haken für die Entwickler-Konsole bleibt nach „Reset Scripts“ erhalten (0.4.1).
- Zonenwechsel bis zur Polizeistation geprüft (0.3.2).

## 0.3.1

- **Geister-Spieler:** Der Mitspieler erscheint als Markierung im Spiel, seine Position wird übertragen.
- Figur (Leon) und Bereich werden erkannt und angezeigt.
- Entwickler-Konsole für die Fehlersuche.
