# Patch Notes: Resident Evil 0 HD Koop

Neueste Version oben. Der Release-Workflow (`.github/workflows/release.yml`) übernimmt den Abschnitt `## <MOD_VERSION>` als Patch Notes, der Mod-Manager zeigt ihn an. Vor jedem Release hier einen Abschnitt für die neue Version anlegen.

## 0.9.2

- **Beitreten repariert:** Dein Freund landete nach dem automatischen Laden in einem neuen Spiel. Jetzt übernimmt die Mod den Spielstand genau wie das Spielmenü (Spielzeit, Story-Fortschritt, Inventar) und prüft das, bevor sie startet.
- **Nicht mehr zu früh:** Der Host schickt seinen Spielstand erst, wenn er wirklich im Spiel steht, nicht schon beim Auswählen des Platzes.
- Benötigt Runtime 0.6.0 (kommt mit dem Update).

## 0.9.1

- **Schneller beitreten:** Wartet dein Freund schon, schickt die Mod deinen Spielstand sofort, wenn du im Spiel ankommst. Vorher dauerte es bis zu 3 Sekunden.
- **Neues Spiel erkannt:** Startest du als Host ein neues Spiel statt eines Spielstands, bekommt dein Freund keinen alten Stand mehr, sondern den Hinweis, dass du einmal an einer Schreibmaschine speichern musst. Danach geht es automatisch weiter.

## 0.9.0

- **Multiplayer im Titelbildschirm:** Unten rechts gibt es jetzt den Bereich „RE:Multiplayer“ mit „Spiel hosten“ und „Freund beitreten“. Das Einfg-Menü braucht man dafür nicht mehr.
- **Beitreten mit einem Klick:** Nach „Verbinden“ holt die Mod den Spielstand des Hosts, wartet notfalls, bis er geladen hat, und **startet das Spiel automatisch**. Den Platz muss man nicht mehr selbst laden (im Menü abschaltbar).
- Beim Hosten stehen deine Adressen im Heimnetz direkt im Fenster.
- Im Spiel zeigt oben rechts eine kleine Anzeige, mit wem du verbunden bist, samt Ping.
- Tippen in Textfelder bewegt die Figur nicht mehr. Klicks auf die Fenster gehen nicht mehr an das Spiel.
- Benötigt Runtime 0.5.0 (kommt mit dem Update).

## 0.8.0

- **Partner durch Türen:** Geht dein Mitspieler durch eine Tür, läuft dein Partner zu dieser Tür und verschwindet. Gehst du hinterher, taucht er im neuen Raum bei deinem Mitspieler wieder auf, ebenso wenn dein Mitspieler zu dir zurückkommt. Bricht die Verbindung ab, steht der Partner wieder neben dir.
- **Automatischer Figurwechsel:** Nach dem Join steuert ihr nicht mehr beide dieselbe Figur. Beim Mitspieler wechselt die Mod automatisch mit V (im Menü abschaltbar).
- **Flüssigere Bewegung übers Internet:** Der Puffer für die Bewegungen des Mitspielers passt sich an eure Verbindung an, kurze Aussetzer werden überbrückt. Positionen werden jetzt 30-mal pro Sekunde geschickt.
- Im Menü stehen Paketabstand, Schwankung und Puffer der Verbindung.

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
