# Roadmap

## RE2 Remake: Story-Koop

### Design-Entscheidungen (User, 4. November 2026)

| Thema | Entscheidung |
|---|---|
| Figuren | Der Mitspieler spielt die andere Hauptfigur: Host Leon → Mitspieler Claire, Host Claire → Mitspieler Leon. |
| Bereiche | Beide dürfen sich frei bewegen und trennen. Die Welt des Hosts ist maßgeblich (Gegner, Türen, Story). |
| Inventar | Jeder hat sein eigenes Inventar und eigene Munition. Schlüssel- und Story-Items bekommen beide, damit niemand festhängt. |
| Mr. X | Verfolgt den näheren Spieler (bzw. den, den er hört). Das Ziel wechselt dynamisch. |
| Tod | Wer stirbt, liegt am Boden und kann vom anderen innerhalb einer Frist wiederbelebt werden. Sterben beide oder läuft die Frist ab: Game Over für beide, weiter am letzten Speicherpunkt des Hosts. |
| Schwierigkeit | Standard wie Solo. Der Host kann später mehr Gegner-Leben bzw. weniger Munition einschalten (Meilenstein 5). |

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
- [x] Eine zweite Spielfigur (Leon/Claire-Modell) erzeugen und an die empfangene Position setzen (Mod 0.4.1)
- [x] Animationen übertragen: Gehen, Joggen, Zielen, Drehen (Mod 0.5.0, mit Testbot im Spiel bestätigt, Leon)
- [ ] Test mit echtem Mitspieler und mit Claire
- [ ] Schießen, Nachladen, Treffer-Reaktionen prüfen (einmalige Animationen, die sich wiederholen)
- Forschungsthemen: Wie spawnt RE2 Charaktere (Prefabs)? Wie kann man eine Figur ohne Steuerung betreiben?

### Meilenstein 3: Gegner
- Host steuert alle Gegner, der Client bekommt Positionen und Zustände
- Treffer des Clients gehen an den Host, der verteilt Schaden und Tod
- Mr. X: zentrale Herausforderung, weil er beide Spieler verfolgen muss
- Konzept für Gegner, Tod und Items mit Forschungsliste: `docs/re2r-konzept-gegner-tod-items.md`

### Meilenstein 4: Welt und Story
- Türen, Schlösser, Rätsel, aufgehobene Items, Story-Flags synchronisieren
- Raum-/Bereichswechsel: Was passiert, wenn die Spieler in verschiedenen Bereichen sind?
- Cutscenes: beide Spieler gleichzeitig hineinholen
- Speichern/Laden: Der Spielstand des Hosts ist maßgeblich

### Meilenstein 5: Komfort
- Verbindung ohne Portfreigabe (z. B. Steam-Netzwerk oder Relay)
- Wiederverbinden nach Absturz
- Einstellungen: Friendly Fire, Schwierigkeit, Item-Teilung

## RE0 HD: Koop mit eigenem Bild für jeden (Weg B)

Entscheidung des Users (2. November 2026): **Weg B**. Jeder spielt in seinem eigenen Spiel mit eigener Kamera. Der Host bestimmt die Welt (Gegner, Items, Story).

**Grundidee:** In RE0 sind Rebecca und Billy immer beide in der Welt. In jedem der beiden Spiele ist der **Partner** der andere Spieler:

| | Spiel des Hosts | Spiel des Mitspielers |
|---|---|---|
| Gesteuert (lokal) | Rebecca | Billy (per Figurwechsel aktiv) |
| Partner | Billy = Puppe des Mitspielers | Rebecca = Puppe des Hosts |

Der Partner wird nicht von der KI gesteuert, sondern von den Netzwerkdaten des anderen Spielers. Er wird über seine eigenen Eingaben bewegt (Partner-Steuerung des Spiels, siehe `KC_partner*`) und regelmäßig auf die echte Position korrigiert. So laufen Animationen von selbst richtig. RE0 erlaubt außerdem schon getrennte Partner in verschiedenen Räumen.

### Schritt 1: Runtime im Spiel ✅
- [x] Loader `dinput8.dll`, Runtime mit D3D9-Hook, ImGui-Menü, Lua und `coopnet`
- [x] Speicher-Werkzeug und Diagnose-Datei für die Forschung
- [x] Erster Test im Spiel (Menü, Maus/Tastatur, Alt+Tab, Testbot) ✅ 2. November 2026

### Schritt 2: Forschungswerkzeug „MT-Explorer“ ✅
- [x] DTI-Typinfos der Engine im laufenden Spiel finden (Klassennamen, Größen, Vererbung)
- [x] Lebende Objekte einer Klasse finden (z. B. `uPlayerRebecca`) und ihre Daten live anzeigen
- [x] Zeiger folgen, geänderte Werte hervorheben, Schnappschüsse für die Auswertung speichern
- [x] Entwickler-Konsole: Claude führt im laufenden Spiel Lua-Befehle aus (`remultiplayer/data/claude_cmd.lua`)

### Schritt 3: Spieldaten (aktuell)
- [x] Position und Drehung von Rebecca und Billy, aktive Figur und Partner (`sPlayer`)
- [x] Kamera (`sGameCamera` → `uGameFreeCamera`)
- [x] Partner-Eingaben einspeisen (DirectInput-Hook) und Partner-KI per Festhalten übersteuern
- [ ] Lebenspunkte
- [ ] Aktueller Raum (`sGameArea`, `aRoom…`)

### Schritt 4: Spielstand übertragen
- [ ] Spielstand `data0.bin` (Steam-Cloud-Ordner, verschlüsselt, alle Slots in einer Datei) vom Host zum Mitspieler schicken. Vorher eine Sicherung anlegen
- [ ] Herausfinden, wann das Spiel die Datei neu einliest (Ladebildschirm oder nur beim Start). Steam Cloud beachten

### Schritt 5: Geister-Koop (in Arbeit)
- [x] Beide Figuren gegenseitig als Partner-Puppe darstellen (Position, Drehung, Laufen), Lua 0.4.0
- [ ] Test mit zwei PCs
- [ ] Raumwechsel: Die Puppe verschwindet bzw. erscheint im richtigen Raum

### Schritt 6: Welt abgleichen
- [ ] Gegner: Der Host steuert, der Mitspieler sieht Puppen. Schaden und Tod abgleichen
- [ ] Items, Inventar und Türen
- [ ] Story-Flags (`sFlagManager`) und Zwischensequenzen

### Schritt 7: Komfort
- [ ] Wiederverbinden, Verbindung ohne Portfreigabe

### Nebenbei: Ultrawide (Wunsch des Users, Monitor 32:9)
- [ ] Gestrecktes Bild bei 5120x1440 beheben (mindestens korrekt 16:9 mit Rändern, besser echtes Ultrawide). Achtung: RE0 nutzt vorgerenderte Hintergründe, mehr Sichtfeld zeigt evtl. deren Ränder

## Weitere Teile (danach)

**Entscheidung des Users (3. November 2026):** Wir machen nur die **Remakes** und die Teile, **von denen es kein Remake gibt**. Originale, die durch ein Remake ersetzt wurden, lassen wir außen vor.

| Engine | Spiele | Aufwand |
|---|---|---|
| RE Engine | RE3 Remake, RE4 Remake, RE7, Village, RE9 | Gleiches Plugin, neue Lua-Adapter. RE3R nutzt sogar denselben Namespace `app.ropeway` wie RE2R. |
| MT Framework | RE1 HD (Remake), RE5, RE6, Revelations 1/2 | Loader und Runtime aus RE0 HD als Grundlage, Adressen pro Spiel neu suchen. RE5/6/Rev haben bereits Koop. Vor RE1 HD die RE0-Runtime nach `shared/` verschieben. |

**Nicht geplant:**

| Spiel | Grund |
|---|---|
| RE4 (2005) / RE4 UHD | Es gibt das RE4 Remake |
| RE1/2/3 Original | Es gibt Remakes (RE1 HD, RE2R, RE3R) |
| Code Veronica | Kein Remake, aber auch keine offizielle PC-Version. Erst wieder prüfen, falls sich das ändert |
