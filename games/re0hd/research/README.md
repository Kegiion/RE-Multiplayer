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
