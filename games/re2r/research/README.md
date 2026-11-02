# RE2 Remake: Forschungsnotizen

Hier sammeln wir alles, was wir über das Innenleben von RE2 herausfinden:
Diagnose-Dateien, Klassen- und Methodennamen, Beobachtungen.

## Dateien

- `re2r_coop_diag_<situation>.json`: Diagnose-Dateien aus dem Spiel (Feld „Situation“ ausfüllen, dann Button „Diagnose speichern“).
  Sie enthalten den Spieler und seine Komponenten, alle geladenen Manager, Details zu interessanten Managern und eine Klassensuche nach Stichworten (Area, Map, Spawn, Door, Item, Enemy, …).

## Bestätigte Fakten

_Noch leer. Wird nach dem ersten Test im Spiel gefüllt._

| Was | Klasse / Methode | Bestätigt am |
|---|---|---|
| Namespace | `app.ropeway.` | (aus REFramework-Quellcode) |
| Lokaler Spieler | `app.ropeway.PlayerManager` → `get_CurrentPlayer()` | ❓ |
| Position/Rotation | `via.GameObject` → `get_Transform()` → `get_Position()` / `get_Rotation()` | ❓ (Engine-Standard) |
| Bereich/Karte | ? | ❓ |
| Figur (Leon/Claire) | ? | ❓ |
