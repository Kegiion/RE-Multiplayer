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
| Zonenwechsel | Beobachtet: `st1_411_0` (Tankstelle) → `Invalid` (Zwischensequenz) → `st8_410_0` (Ort `Opening3`, Straßen) → `st4_201_0` → `st4_101_0` (Eingangshalle Polizeistation, ID 112). Scene, Space und `UIMapManager.get_SceneMapId()` wechseln gemeinsam | ✅ 2. November 2026 |
| Zwischensequenzen | Zone kurz `Invalid`, Position springt auf (0, 0, 0) oder weit weg (z. B. x = −197) | ✅ 2. November 2026 |
| Koordinaten | Tankstelle und Eingangshalle liegen beide nahe (0, 0, 0). Möglicherweise sind die Koordinaten pro Zone lokal. Für den Koop egal, solange beide in derselben Zone sind | ❓ |
| Ort | `MainFlowManager.get_LoadLocation()` / `StayAreaController.get_StayLocationID()` → `Location.ID`, z. B. `GasStation2` (23) | ✅ 2. November 2026 |
| Figur Leon | `PlayerCondition.get_SurvivorType()` = 0 (`PL0000`), auch `PlayerManager.get_CurrentPlayerType()` = `PL0000` | ✅ 2. November 2026 |
| Weitere Figuren | `SurvivorType` hat 56 Werte (`PL0000`, `PL1000`, `PL2000`, … bis `PL9900`), keine Klarnamen. `PL1000` ist vermutlich Claire | ❓ |

Der Spieler hat außerdem die Komponente `app.ropeway.StayAreaController`. Sie bestimmt die Zone per Bodenstrahl und hat die Ereignisse `OnChangedSceneID` / `OnChangedSpaceID` (`Action<Map.ID, Map.ID>`) sowie `OnChangedMapIdentifier` (`MansionManager.MapIdentifier`, eventuell feiner als `Map.ID`, ungeprüft).

## Meilenstein 2: Zweite Spielfigur („Puppe“)

Am 2. November 2026 per Entwickler-Konsole im Spiel geprüft (Leon, Eingangshalle):

| Was | Befund | Status |
|---|---|---|
| Figuren-Prefabs | `SurvivorManager.<PrefabInfoList>k__BackingField`: 40 Einträge `SurvivorPrefabInfo` (SurvivorType, RoleType `PLAYER`/`NPC`/`ACTOR`, Prefab, GameObject) | ✅ |
| Pfade | `ObjectRoot/Prefab/Character/Player/pl0000.pfb`, `…/Npc/pl2000.pfb`, `…/Survivor/Actor/pl0000.pfb`. Actor gibt es für Leon (`pl0000`), Claire (`pl1000`), `pl2000`, `pl3000` und viele mehr | ✅ |
| Prefab laden | `sdk.create_instance("via.Prefab", true):add_ref()`, `set_Path`, `set_Standby(true)`, dann `get_Ready()`. `Prefab:duplicate()` liefert keinen verwalteten Zeiger | ✅ |
| Erzeugen | `instantiate(via.vec3, via.Quaternion, via.Folder)` mit `SurvivorManager.get_ActorFolder()` → GameObject `pl0000` | ✅ |
| Komponenten des Actors | Motion, MotionFsm2, IK, `SurvivorCostumeChanger`, `ActorCondition`, `StayAreaController`. **Kein** `PlayerController`, `CharacterController` oder Inventar | ✅ |
| Modell | Zuerst unsichtbar (keine Unterobjekte). `SurvivorCostumeChanger.change(SurvivorType, Costume)` mit (0, 0) lädt `Hair`, `Face`, `Body` → Leon steht sichtbar im Spiel | ✅ |
| Bewegen | `Transform.set_Position` / `set_Rotation`. `Quaternion.new` nimmt (w, x, y, z) | ✅ |
| Löschen | `go:call("destroy", go)`, ab dem nächsten Frame `get_Valid() == false` | ✅ |
| Mod 0.4.1 mit Testbot | Puppe `ready`, sichtbar, folgt der Position des Testbots (Eingangshalle) | ✅ 2. November 2026 |
| Animation | Puppe steht still, keine Animation | ❓ nächster Schritt |
| Szenenwechsel | Ob das Spiel die Puppe beim Laden löscht | ❓ (Mod 0.4.0 erzeugt sie dann neu) |

## Weitere Kandidaten aus der Diagnose

- `PlayerManager.get_CurrentPlayerType()` → `PlayerDefine.PlayerType`
- `gamemastering.MainFlowManager.get_LoadArea()` → `Map.ID`, `get_LoadLocation()` → `Location.ID`, `get_LoadSurvivorType()`
- `gamemastering.UIMapManager.get_SceneMapId()` → `Map.ID`, `get_DispLocationId()` → `Location.ID`
- `EnemyManager.get_onFixedAreaChange()`: Ereignis `Action<Map.ID, Map.ID>` beim Bereichswechsel (für später: Mr. X, Gegner-Sync)
- Für Meilenstein 2: `SurvivorManager`, `SurvivorAssignManager`, `level.SurvivorStandbyManger`, `NPCAccessManager`
