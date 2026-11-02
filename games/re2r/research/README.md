# RE2 Remake: Forschungsnotizen

Hier sammeln wir alles, was wir über das Innenleben von RE2 herausfinden:
Diagnose-Dateien, Klassen- und Methodennamen, Beobachtungen.

## Dateien

- `re2r_coop_diag_<situation>.json`: Diagnose-Dateien aus dem Spiel (Feld „Situation“ ausfüllen, dann Button „Diagnose speichern“).
  Sie enthalten den Spieler und seine Komponenten, alle geladenen Manager, Details zu interessanten Managern und eine Klassensuche nach Stichworten (Area, Map, Spawn, Door, Item, Enemy, …).

## Entwickler-Konsole (ab Mod 0.3.0)

Im Menü „RE2 Koop“ → **Entwickler-Konsole für Claude** anhaken (bleibt gespeichert). Dann kann Claude im laufenden Spiel Lua ausführen:

```bash
python tools/re2r_console.py "out(game.get_local_state())"
```

Der Austausch läuft über `reframework/data/claude_cmd.json` (`id`, `code`) und `claude_out.json`. Im Befehl gibt es `out(...)`, `task(fn)`, `console.store` und `game`.

## Bestätigte Fakten

Erster Test im Spiel am 2. November 2026 (REFramework-nightly 01436, Monolith-DLL, RT-Version des Spiels). Menü, Spielersuche, Diagnose und Testbot funktionieren.

| Was | Klasse / Methode | Bestätigt am |
|---|---|---|
| Namespace | `app.ropeway.` | ✅ 2. November 2026 (Diagnose) |
| Lokaler Spieler | `app.ropeway.PlayerManager` → `get_CurrentPlayer()` liefert GameObject `pl0000` | ✅ 2. November 2026 |
| Im Hauptmenü kein Spieler | `get_CurrentPlayer()` liefert `nil` | ✅ 2. November 2026 |
| Position/Rotation | `via.GameObject` → `get_Transform()` → `get_Position()` / `get_Rotation()` | ✅ 2. November 2026 (Testbot läuft hinterher) |
| Spieler-Komponente mit Zustand | `app.ropeway.survivor.player.PlayerCondition` (erbt von `survivor.SurvivorCondition`) hängt am Spieler | ✅ 2. November 2026 (Komponentenliste) |
| Bereich (Zone) | `PlayerCondition.get_StaySceneAreaID()` → `gamemastering.Map.ID`, z. B. `st1_411_0` (347) an der Tankstelle. Scene, Space, `MainFlowManager.get_LoadArea()` und `UIMapManager.get_SceneMapId()` stimmen überein | ✅ 2. November 2026 (Konsole) |
| `Map.ID` ist eine Zone, kein Raum | 436 Einträge. Die Tür in der Tankstelle (Laden ↔ Hinterraum) wechselt die ID nicht | ✅ 2. November 2026 |
| Zonenwechsel | Wechsel der `Map.ID` beim Übergang in eine neue Zone | ❓ noch nicht beobachtet |
| Ort | `MainFlowManager.get_LoadLocation()` / `StayAreaController.get_StayLocationID()` → `Location.ID`, z. B. `GasStation2` (23) | ✅ 2. November 2026 |
| Figur Leon | `PlayerCondition.get_SurvivorType()` = 0 (`PL0000`), auch `PlayerManager.get_CurrentPlayerType()` = `PL0000` | ✅ 2. November 2026 |
| Weitere Figuren | `SurvivorType` hat 56 Werte (`PL0000`, `PL1000`, `PL2000`, … bis `PL9900`), keine Klarnamen. `PL1000` ist vermutlich Claire | ❓ |

Der Spieler hat außerdem die Komponente `app.ropeway.StayAreaController`. Sie bestimmt die Zone per Bodenstrahl und hat die Ereignisse `OnChangedSceneID` / `OnChangedSpaceID` (`Action<Map.ID, Map.ID>`) sowie `OnChangedMapIdentifier` (`MansionManager.MapIdentifier`, eventuell feiner als `Map.ID`, ungeprüft).

## Weitere Kandidaten aus der Diagnose

- `PlayerManager.get_CurrentPlayerType()` → `PlayerDefine.PlayerType`
- `gamemastering.MainFlowManager.get_LoadArea()` → `Map.ID`, `get_LoadLocation()` → `Location.ID`, `get_LoadSurvivorType()`
- `gamemastering.UIMapManager.get_SceneMapId()` → `Map.ID`, `get_DispLocationId()` → `Location.ID`
- `EnemyManager.get_onFixedAreaChange()`: Ereignis `Action<Map.ID, Map.ID>` beim Bereichswechsel (für später: Mr. X, Gegner-Sync)
- Für Meilenstein 2: `SurvivorManager`, `SurvivorAssignManager`, `level.SurvivorStandbyManger`, `NPCAccessManager`
