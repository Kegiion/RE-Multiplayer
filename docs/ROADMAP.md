# Roadmap

## RE2 Remake: Story-Koop

### Meilenstein 0: Grundgerüst ✅
- Netzwerk-Kern, REFramework-Plugin, gemeinsame Lua-Bibliothek
- Automatischer Build und Tests über GitHub Actions
- Testbot als simulierter Mitspieler

### Meilenstein 1: Geister-Spieler (aktuell)
- [x] Verbindungsmenü (Host/Beitreten, Name, Chat)
- [x] Eigene Position und Rotation auslesen und 20× pro Sekunde senden
- [x] Mitspieler als Markierung mit Name und Entfernung anzeigen
- [x] Diagnose-Datei
- [ ] **Im Spiel bestätigen:** Wird der Spieler gefunden? Stimmen die Positionen?
- [ ] Bereichs-ID finden (`game.get_area()`), damit wir nur anzeigen, wer im selben Bereich ist
- [ ] Figur erkennen (Leon/Claire)

### Meilenstein 2: Sichtbarer Mitspieler
- Eine zweite Spielfigur (Leon/Claire-Modell) erzeugen und an die empfangene Position setzen
- Animationen übertragen (Laufen, Zielen, Schießen)
- Forschungsthemen: Wie spawnt RE2 Charaktere (Prefabs)? Wie kann man eine Figur ohne Steuerung betreiben?

### Meilenstein 3: Gegner
- Host steuert alle Gegner, der Client bekommt Positionen und Zustände
- Treffer des Clients gehen an den Host, der verteilt Schaden und Tod
- Mr. X: zentrale Herausforderung, weil er beide Spieler verfolgen muss

### Meilenstein 4: Welt und Story
- Türen, Schlösser, Rätsel, aufgehobene Items, Story-Flags synchronisieren
- Raum-/Bereichswechsel: Was passiert, wenn die Spieler in verschiedenen Bereichen sind?
- Cutscenes: beide Spieler gleichzeitig hineinholen
- Speichern/Laden: Der Spielstand des Hosts ist maßgeblich

### Meilenstein 5: Komfort
- Verbindung ohne Portfreigabe (z. B. Steam-Netzwerk oder Relay)
- Wiederverbinden nach Absturz
- Einstellungen: Friendly Fire, Schwierigkeit, Item-Teilung

## RE0 HD: Partner-Koop (parallel zu RE2)

Idee: Der zweite Spieler steuert den Partner (Rebecca bzw. Billy). Details: [games/re0hd/README.md](../games/re0hd/README.md).

### Schritt 1: Runtime im Spiel (aktuell)
- [x] Loader `dinput8.dll`, Runtime mit D3D9-Hook, ImGui-Menü, Lua und `coopnet`
- [x] Speicher-Werkzeug und Diagnose-Datei für die Forschung
- [ ] Erster Test im Spiel (Menü, Maus/Tastatur, Alt+Tab, Testbot)

### Schritt 2: Spieldaten finden
- [ ] Mit Cheat Engine: Position, Lebenspunkte, aktive Figur, Raum
- [ ] Adressen über Byte-Muster (`mem.scan`) robust gegen Spiel-Updates machen
- [ ] `game.get_local_state()` implementieren

### Schritt 3: Geister-Spieler
- [ ] Position beider Spieler austauschen und im Menü bzw. als Markierung anzeigen

### Schritt 4: Partner übernehmen
- [ ] Partner-KI abschalten und den Partner über Netzwerk-Eingaben steuern

## Weitere Teile (danach)

| Engine | Spiele | Aufwand |
|---|---|---|
| RE Engine | RE3 Remake, RE4 Remake, RE7, Village, RE9 | Gleiches Plugin, neue Lua-Adapter. RE3R nutzt sogar denselben Namespace `app.ropeway` wie RE2R. |
| MT Framework | RE5, RE6, Revelations 1/2, RE0/RE1 HD | Eigener Weg ins Spiel nötig, `netcore` wiederverwendbar. RE5/6/Rev haben bereits Koop. |
| RE4 (2005) | RE4 UHD | Eigener Weg ins Spiel, z. B. aufbauend auf RE4 Tweaks |
| Klassisch | RE1/2/3 Original | Sehr aufwendig, eigener Weg ins Spiel |
