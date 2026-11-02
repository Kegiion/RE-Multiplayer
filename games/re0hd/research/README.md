# RE0 HD: Forschung

Hier landen Diagnose-Dateien (`re0hd_diag_*.json`), Logs und bestätigte Fakten über `re0hd.exe`.

## Bestätigt

| Fakt | Quelle |
|---|---|
| `re0hd.exe` ist 32-Bit (PE-Machine `0x14C`), importiert `d3d9.dll` (`Direct3DCreate9`, kein `Ex`) und `dinput8.dll` (`DirectInput8Create`) | Analyse der exe-Datei, 2. November 2026 |

## Spielversion

Adressen gelten nur für eine bestimmte Version der exe. Die Version erkennen wir am **PE-Zeitstempel**. Er steht im Runtime-Log und in jeder Diagnose-Datei.

| Zeitstempel | Steam-Build | Hinweis |
|---|---|---|
| (noch offen) | 17178773 | Stand 2. November 2026 |

## Gesucht (unbestätigt)

- Position von Rebecca und Billy (x, y, z, Blickrichtung)
- Lebenspunkte beider Figuren
- Welche Figur gerade gesteuert wird (Partnerwechsel)
- Aktueller Raum bzw. Bereich
- Steuerung der Partner-KI (Bewegungsbefehle bzw. Eingaben für den Partner)
