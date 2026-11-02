# RE0 HD: Forschung

Hier landen Diagnose-Dateien (`re0hd_diag_*.json`), Logs und bestätigte Fakten über `re0hd.exe`.

## Bestätigt

| Fakt | Quelle |
|---|---|
| `re0hd.exe` ist 32-Bit (PE-Machine `0x14C`), importiert `d3d9.dll` (`Direct3DCreate9`, kein `Ex`) und `dinput8.dll` (`DirectInput8Create`) | Analyse der exe-Datei, 2. November 2026 |
| Loader über `dinput8.dll` funktioniert, Runtime 0.1.0 läuft (Menü, Maus/Tastatur, Skripte neu laden, Alt+Tab, Testbot-Verbindung) | Erster Test im Spiel, 2. November 2026 |
| Basisadresse `0x00400000` (kein ASLR), SizeOfImage `0xA66000` | Runtime-Log |
| Das Spiel erstellt sein Device mit Flags `0x46` (`HARDWARE_VERTEXPROCESSING`, `MULTITHREADED`, `FPU_PRESERVE`), zuerst im Fenster mit 1280x720, danach per `Reset` auf die eingestellte Auflösung | Runtime-Log |
| Die vtable des Spiel-Devices ist **eine andere** als die unseres NULLREF-Dummy-Devices. Der Hook auf `IDirect3D9::CreateDevice` ist deshalb nötig | Runtime-Log |
| Fenster-Nachrichten und `Present` laufen in **verschiedenen Threads** | Runtime-Log |
| Bei 32:9 (Samsung Odyssey G9, 5120x1440) wird das Bild gestreckt | Test durch den User |
| Die Pfeiltasten (`KC_partner*`) steuern den Partner unabhängig von der eigenen Figur | Test durch den User, 2. November 2026 |
| MT-DTI: In `.data` liegen 2540 Kandidaten (vtable + Zeiger auf Klassennamen). Das Feld `+10` zeigt bei 1377 auf ein anderes DTI-Objekt, ist also wahrscheinlich der Eltern-Zeiger | Runtime 0.2.0, Log |

## Spielerobjekte (bestätigt am 2. November 2026, exe `0x6799D40F`)

**Fester Weg:** In `re0hd.exe` (.data) steht bei `0x00DCBF3C` (= `re0hd.exe+9CBF3C`) der Zeiger auf die Spieler-Verwaltung `sPlayer` (statischer Instanz-Zeiger). Gefunden mit dem MT-Explorer über `mt.refs`.

| `sPlayer` + | Inhalt |
|---|---|
| `+2C` | **gesteuerte Figur** (nach Figurwechsel mit V steht hier die andere) |
| `+3C` | **Partner** |
| `+20` bis `+28`, `+30` bis `+38` | Verwaltungsdaten der beiden Einträge (Listen-Zeiger, noch unklar) |
| `+40` | `1` (Bedeutung unklar, ändert sich beim Figurwechsel nicht) |

Klassen: `uPlayerRebecca` bzw. `uPlayerBilly`, beide erben von `uPlayerBase` → `uCharaBase`.

**Im Spielerobjekt** (`uPlayerRebecca`/`uPlayerBilly`):

| Offset | Typ | Inhalt |
|---|---|---|
| `+040`, `+044`, `+048` | float | **Position** x, y (Höhe, im Raum 0), z. Einheiten: etwa Zentimeter |
| `+050` bis `+05C` | float ×4 | **Drehung** als Quaternion (x, y, z, w). Nur y und w ändern sich (Drehung um die Hochachse) |
| `+060` bis `+06C` | float ×4 | Skalierung (1, 1, 1) |
| `+070` bis `+0AC` | float 4×4 | Weltmatrix (Drehung plus Position bei `+0A0`) |
| `+0E0` | float ×3 | weitere Kopie der Position (vermutlich vorheriger Frame) |
| `+180`, `+1C0`, `+1E0` | float ×4 | Kollisions- bzw. Körpermittelpunkt (Position plus Höhe ca. 79 bzw. 103) |
| `+4E0` | int/float | Animationszustand (wechselt zwischen Stehen und Laufen) |
| `+4EC`, `+4F0`, `+504`, `+508` | float | Bildzähler der laufenden Animation, `+4F4` vermutlich deren Länge |

**Puppen-Test:** Wird die Position des Partners jeden Frame geschrieben, bleibt sie stehen. Die KI schiebt nur minimal (unter 1 Einheit pro Frame) nach. Der Partner lässt sich also von außen positionieren.

**Kamera:** Bei `0x00E2D6BC` (= `re0hd.exe+A2D6BC`) steht der Zeiger auf `sGameCamera`. Dort bei `+34` steht die aktive Kamera (`uGameFreeCamera`):

| Kamera + | Inhalt |
|---|---|
| `+30` | Fernebene (100000) |
| `+34` | Nahebene (10) |
| `+38` | Seitenverhältnis (1,334 = 4:3, auch bei 16:9-Ausgabe) |
| `+3C` | Bildwinkel (FOV) in Grad, ca. 40 bis 50 |
| `+40` | Kameraposition (x, y, z) |
| `+50` | Oben-Vektor (0, 1, 0) |
| `+60` | Blickpunkt (x, y, z) |

**Partner-Tasten** (`KC_partner*`, Standard: Pfeiltasten) wirken **relativ zur Kamera**: hoch = vom Betrachter weg, rechts = nach rechts im Bild. Die Weltrichtung von „hoch“ entspricht der Richtung Kameraposition → Blickpunkt (gemessen: 108° Laufrichtung bei 106° Kamerarichtung). Rechts = hoch − 90°, links = hoch + 90°.

**Puppen-Steuerung (erprobt):**
- Nur die Position zu schreiben lässt den Partner ohne Laufanimation „schweben“.
- Die Blickrichtung zu erzwingen, während die Taste in eine andere Richtung zeigt, lässt den Partner stehen bleiben.
- **Was funktioniert:** passende Partner-Taste zur Kamera drücken (8 Richtungen), bei Abweichung sanft nachziehen, im Stand Position und Drehung festhalten. Der Partner läuft dann einer Spur flüssig nach, auch über Kamerawechsel (Test des Users, 2. November 2026). Umgesetzt in `lua/autorun/re0hd_coop/puppet.lua`.
- Wird der Partner in eine Wand oder an eine unerreichbare Stelle gesetzt, bleibt er dort hängen und die KI folgt nicht mehr.

**Hinweis:** Der MT-Explorer findet pro Klasse zusätzlich Objekte mit einer vtable 8 Bytes vor der echten (z. B. `0x00CCFD08` statt `0x00CCFD10`). Das sind keine Spielerobjekte. Das echte Objekt erkennt man an der Position bei `+040`.

## Aus der exe und der Konfiguration (statisch, noch nicht im Speicher geprüft)

- **Einstellungen:** `%LOCALAPPDATA%\CAPCOM\RESIDENT EVIL 0 HD REMASTER\config.ini`. Unter `[DISPLAY]` stehen `Resolution`, `Aspect` (Werte laut exe: `4:3`, `16:9`, `16:10`) und `FullScreen`.
- **Partner direkt steuerbar:** Die Tastenbelegung enthält `KC_partnerFront/Back/Left/Right` (Standard: Pfeiltasten) und `KC_change` (V, Figur wechseln). Das Spiel hat also schon einen Eingabeweg für den Partner. **Das ist wahrscheinlich der Schlüssel für den Koop:** Die Eingaben des zweiten Spielers könnten wir als Partner-Eingaben einspeisen.
- **MT-Framework-Eigenschaften** (Namen aus dem Reflexionssystem der Engine, in der exe als Text):
  - `uCamera`: `mCameraPos`, `mCameraUp`, `mNearPlane`, `mFarPlane`, `mFov`, `mAspect`
  - `uGameFreeCamera`: `mIsOriginalAspect`, `mOriginalAspect`, `mIsOriginalProjMat`, `mOriginalProjMat`
  - `sGameConfig`: `mAspectRatio`
  - `uLightShaft`: `mLSFov`, `mLSAspect`
- **Ultrawide:** Die Hintergründe sind vorgerenderte Bilder. Für 16:9 schneidet das Spiel das ursprünglich 4:3 große Bild oben und unten ab und schwenkt mit. Links und rechts gibt es also **keine** zusätzlichen Bilddaten. Ein breiteres Bild ohne Ränder geht deshalb nur über stärkeres Zuschneiden oben und unten (Zoom), nicht über mehr Sichtfeld zur Seite. (Annahme aus Community-Berichten, noch nicht selbst geprüft.)

## Spielversion

Adressen gelten nur für eine bestimmte Version der exe. Die Version erkennen wir am **PE-Zeitstempel**. Er steht im Runtime-Log und in jeder Diagnose-Datei.

| Zeitstempel | Steam-Build | Hinweis |
|---|---|---|
| `0x6799D40F` (29. Januar 2025) | 17178773 | Stand 2. November 2026 |

## Gesucht (unbestätigt)

- Position von Rebecca und Billy (x, y, z, Blickrichtung)
- Lebenspunkte beider Figuren
- Welche Figur gerade gesteuert wird (Partnerwechsel)
- Aktueller Raum bzw. Bereich
- Steuerung der Partner-KI (Bewegungsbefehle bzw. Eingaben für den Partner)
