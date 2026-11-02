# RE2 Remake: Forschungsnotizen

Hier sammeln wir alles, was wir über das Innenleben von RE2 herausfinden:
Diagnose-Dateien, Klassen- und Methodennamen, Beobachtungen.

## Dateien

- `re2r_coop_diag_<situation>.json`: Diagnose-Dateien aus dem Spiel (Feld „Situation“ ausfüllen, dann Button „Diagnose speichern“).
  Sie enthalten den Spieler und seine Komponenten, alle geladenen Manager, Details zu interessanten Managern und eine Klassensuche nach Stichworten (Area, Map, Spawn, Door, Item, Enemy, …).

## Bestätigte Fakten

Erster Test im Spiel am 2. November 2026 (REFramework-nightly 01436, Monolith-DLL, RT-Version des Spiels). Menü, Spielersuche, Diagnose und Testbot funktionieren.

| Was | Klasse / Methode | Bestätigt am |
|---|---|---|
| Namespace | `app.ropeway.` | ✅ 2. November 2026 (Diagnose) |
| Lokaler Spieler | `app.ropeway.PlayerManager` → `get_CurrentPlayer()` liefert GameObject `pl0000` | ✅ 2. November 2026 |
| Im Hauptmenü kein Spieler | `get_CurrentPlayer()` liefert `nil` | ✅ 2. November 2026 |
| Position/Rotation | `via.GameObject` → `get_Transform()` → `get_Position()` / `get_Rotation()` | ✅ 2. November 2026 (Testbot läuft hinterher) |
| Spieler-Komponente mit Zustand | `app.ropeway.survivor.player.PlayerCondition` (erbt von `survivor.SurvivorCondition`) hängt am Spieler | ✅ 2. November 2026 (Komponentenliste) |
| Bereich/Karte | `PlayerCondition.get_StaySceneAreaID()` bzw. `get_StaySpaceAreaID()` → `gamemastering.Map.ID` | ❓ Methoden existieren, Werte ungeprüft (Mod 0.2.0 zeigt beide an) |
| Figur (Leon/Claire) | `PlayerCondition.get_SurvivorType()` → `SurvivorDefine.SurvivorType` | ❓ Methode existiert, Wert ungeprüft |

## Weitere Kandidaten aus der Diagnose

- `PlayerManager.get_CurrentPlayerType()` → `PlayerDefine.PlayerType`
- `gamemastering.MainFlowManager.get_LoadArea()` → `Map.ID`, `get_LoadLocation()` → `Location.ID`, `get_LoadSurvivorType()`
- `gamemastering.UIMapManager.get_SceneMapId()` → `Map.ID`, `get_DispLocationId()` → `Location.ID`
- `EnemyManager.get_onFixedAreaChange()`: Ereignis `Action<Map.ID, Map.ID>` beim Bereichswechsel (für später: Mr. X, Gegner-Sync)
- Für Meilenstein 2: `SurvivorManager`, `SurvivorAssignManager`, `level.SurvivorStandbyManger`, `NPCAccessManager`
