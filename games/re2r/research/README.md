# RE2 Remake: Forschungsnotizen

Hier sammeln wir alles, was wir über das Innenleben von RE2 herausfinden:
Diagnose-Dateien, Klassen- und Methodennamen, Beobachtungen.

## Dateien

- `diag-*.json`: Diagnose-Dateien aus dem Spiel (Button „Diagnose speichern“).
  Bitte mit Situation im Namen ablegen, z. B. `diag-hauptmenue.json` oder `diag-rpd-eingangshalle.json`.

## Bestätigte Fakten

_Noch leer. Wird nach dem ersten Test im Spiel gefüllt._

| Was | Klasse / Methode | Bestätigt am |
|---|---|---|
| Namespace | `app.ropeway.` | (aus REFramework-Quellcode) |
| Lokaler Spieler | `app.ropeway.PlayerManager` → `get_CurrentPlayer()` | ❓ |
| Position/Rotation | `via.GameObject` → `get_Transform()` → `get_Position()` / `get_Rotation()` | ❓ (Engine-Standard) |
| Bereich/Karte | ? | ❓ |
| Figur (Leon/Claire) | ? | ❓ |
