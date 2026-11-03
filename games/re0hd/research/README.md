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

**Aktueller Raum** (bestätigt am 2. November 2026): Bei `0x00E2D8C0` (= `re0hd.exe+A2D8C0`) steht der Zeiger auf `sGameArea`. Dort bei `+3834` steht das aktuelle Raum-Objekt, bei `+3830` die Stufe (`aStageTr`), bei `+382C` ein weiteres Objekt (unklar). Die **Klasse des Raum-Objekts ist die Raum-Kennung**: `aRoomTr02` = Flur im Zug, `aRoomTr04` = Raum 201 (Test des Users). Das Objekt bleibt beim Raumwechsel an derselben Adresse, nur seine Klasse (vtable) wechselt. Stufen laut Klassenliste: `Bt`, `Ch`, `Dm`, `Pl`, `Sh`, `Tr` (Tr = Zug, die übrigen unbestätigt). Weitere Klassen rund um Räume: `sRoomControl` (Zeiger bei `0x00DCBEB4`), `sDoorLoad` (`0x00DCBEB8`), `cRoomScheduler`, `cRoomPhase*`.

## Spielstände (bestätigt am 3. November 2026)

- Datei: `<Steam>\userdata\<Konto>\339340\remote\data0.bin` (Steam Cloud, 2.337.008 Bytes). Verschlüsselt mit einer 8-Byte-Blockchiffre (vermutlich Blowfish ECB, die Konstanten stehen in der exe). Der Schlüssel ist nicht gefunden, der Text `mc=#sA0)Mhs9#>/4iiXbMPxW` neben `data0.bin` ist es allein nicht. Für den Join nicht nötig.
- Die `.text`-Section der exe ist auf der Festplatte verschlüsselt (SteamStub, Section `.bind`). Für die Analyse wurde sie aus dem laufenden Spiel ausgelesen.
- `sSaveManager` (Zeiger bei `0x00DCC018`): `+20` = `cSaveManager`, `+24` = zuletzt geladener bzw. gespeicherter Platz (0..19).
- `cSaveManager`: `+4` Befehl, `+8` Schritt, `+C` Ergebnis, `+10` Parameter (Platz). Die Befehle laufen pro Frame über `0x6133D0`. Beim Laden im Titelbildschirm: Befehl 6 (Parameter 24), danach Befehl 5 mit dem Platz (liest die Datei neu ein).
- Zwei unverschlüsselte Abbilder der Datei: `+23A718` (Datei-Abbild) und `+18` (zuletzt übernommen). Aufbau: `+0` VERSION (4 Bytes), `+8` SYSTEMDATA (`0xA8`), ab `+B0` 20 Plätze zu je `0x1C850` Bytes (`GAMEDATA0` bis `GAMEDATA19`, im Menü 1 bis 20). Die Einträge von `sSavedata` (`0x00E2ED20`, Tabelle ab `+78`, sortiert nach CRC des Namens) zeigen in das Datei-Abbild.
- Platz: `+4` Byte 1 = belegt, `+18` Anzahl Speicherungen (im Menü „Rebecca/02/…“), `+1C` Spielzeit als float in Bildern (60 pro Sekunde), ab `+38` Flags (wie `sFlagManager+24`).
- `0x6127D0(Platz)` übernimmt einen Platz: Es kopiert ihn vom Datei-Abbild ins zweite Abbild und verteilt ihn an `sGameInfo`, `sFlagManager`, `sPlayer` usw. Aufgerufen beim Spielstart über `0x405460`.
- **Join-Test:** Wird der Platz im Datei-Abbild nach jedem Neu-Einlesen wieder überschrieben, lädt das Spiel den fremden Stand (Platz 3 mit dem Stand von Platz 1 geladen: Spielzeit 7,1 statt 19,5 Minuten).

## Titelbildschirm und Laden (bestätigt am 3. November 2026)

- **Titelbildschirm erkennen:** `sGameArea + 382C` zeigt auf ein Objekt der Klasse `aTitle`. Im Spiel steht dort dasselbe Objekt, aber mit der Klasse `aGame`. `+3830` ist dann die Stufe (`aStageTr`, beim Start kurz `aInGameStart`), `+3834` der Raum.
- **Ablauf beim Laden über das Menü** (Aufnahme): „Spiel laden“ öffnen → `cSaveManager` Befehl 6 (Parameter 24). Platz wählen → Befehl 5 mit dem Platz (0-basiert). Etwa 8 Sekunden später (Bestätigung, Ausblenden) schreibt der Titel `sGameArea + 3828` = DTI von `aInGameStart` (`0x00DCBFE4`). Einen Frame später springt `sGameArea + 3824` von 1 auf 2, das Bereichs-Objekt wird zu `aGame`, und das Spiel startet.
- **Auto-Laden (im Spiel bestätigt):** Im Titelbildschirm `cSaveManager + 10` = Platz, `+4` = 5 schreiben. Der Befehl ist nach einem Frame fertig (`+4` wieder 0). Danach `sGameArea + 3828` = DTI von `aInGameStart`. Das Spiel lädt den Platz ohne Menü.
- Im Titelbildschirm liefert der DirectInput-Hook keine gedrückten Tasten über `input.key_down` (Ursache unklar, `GetDeviceState` wird aufgerufen).

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
- Steuerung der Partner-KI (Bewegungsbefehle bzw. Eingaben für den Partner)
