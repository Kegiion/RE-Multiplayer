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
