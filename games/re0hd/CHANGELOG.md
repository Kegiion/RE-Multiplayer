# Patch Notes: Resident Evil 0 HD Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.6.0

- **Join auf den Spielstand des Hosts:** Dein Mitspieler klickt im Menü auf „Spielstand vom Host holen“ und bekommt deinen zuletzt geladenen bzw. gespeicherten Platz. Er landet bei ihm in Platz 20 und lässt sich im Titelbildschirm ganz normal laden.
- **Wichtig:** Diese Version ist nicht mit älteren Versionen verbindbar (neues Netzwerk-Protokoll). Beide Spieler müssen über den Mod-Manager aktualisieren.
- Runtime 0.4.0: schnelleres Lesen und Schreiben großer Speicherbereiche.

## 0.5.0

- **Raumwechsel:** Die Mod erkennt jetzt den aktuellen Raum und schickt ihn mit. Seid ihr in verschiedenen Räumen, übernimmt die Spiel-KI deinen Partner, bis ihr wieder zusammen seid. Im Menü steht bei beiden Spielern der Raum (z. B. `Tr04`).

## 0.4.1

- **Neuer Name: RE:Multiplayer.** Die Dateien im Spielordner heißen jetzt `remultiplayer/` statt `remods/` (Runtime `remultiplayer_re0.dll`, Log `remultiplayer/remultiplayer_re0.log`).
- Bestehende Einstellungen zieht der Mod-Manager beim Aktualisieren automatisch nach `remultiplayer/data/` um.

## 0.4.0

- **Geister-Koop:** Der Partner folgt der Position des Mitspielers.
- Spielerobjekte gefunden: aktive Figur, Partner, Position und Drehung.
- Das Menü sperrt Tastatur und Maus für das Spiel, solange es offen ist.
- Entwickler-Konsole und Speicher-Werkzeug für die Fehlersuche.
