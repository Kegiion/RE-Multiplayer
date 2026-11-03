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
| Ordner | Im ActorFolder (`get_Folder` = nil) löscht das Spiel die Puppe beim Nachladen von Bereichen, ca. 0,8 s lang auch jede neu erzeugte (Unsichtbarwerden, Zittern). Mit `set_FolderSelf(<Ordner des Spielers>)` (`RopewayManagers/TemporaryObjects/Survivor/Player`) bleibt sie erhalten | ✅ |
| Mod 0.5.0 mit Testbot | Puppe geht, joggt, zielt und dreht sich passend zur Bewegung, ohne Springen und Verschwinden (Animation übers Netzwerk) | ✅ 2. November 2026 |
| Szenenwechsel (Tür, Ladebildschirm) | Ob die Puppe im Spieler-Ordner erhalten bleibt | ❓ (Mod 0.5.0 erzeugt sie nach 1 s neu) |

## Animation der Puppe

Am 2. November 2026 per Entwickler-Konsole geprüft (Leon, Polizeistation). Code: `games/re2r/coop/autorun/re2r_coop/anim.lua`.

| Was | Befund | Status |
|---|---|---|
| Ebenen | `via.motion.Motion` hat 6 Ebenen (`TreeLayer`). Genutzt: 0 = Körper, 1 = Dummy, 2 = Waffenhaltung, 3 = Zielen beginnen | ✅ |
| Animations-Bäume | `getLayer(i).get_MotionBankID/get_MotionID` zeigt auf einen Baum: Bank 1 = `LCM_TREE` (160 Idle, 190/196 Gehen, 192 Gehen-Stopp, 200/220 Joggen-Start, 230 Joggen, 224 Joggen-Stopp), Bank 2 = `HLD_TREE` (120 Zielen gehen, 140 Zielen beginnen, 160/165 Zielen). Die Knoten (`getMotionNode`) spielen Leons Bewegungen aus den dynamischen Bänken (1000 = `BareHand`, 2000 = Pistole) | ✅ |
| Animationsdateien | Das Actor-Prefab hat keine. Nötig: `set_MotionBankAsset` (`SectionRoot/Animation/Player/common/pl_common.motbank`), dynamische Bänke `pl00/bank/BareHand.motbank` und `wp0000.motbank`, `set_TargetBankType(1)`, `setupMotionBank()`. Laden per Pfad: `sdk.create_resource("via.motion.MotionBankResource", pfad):create_holder("via.motion.MotionBankResourceHolder")` | ✅ |
| Wechsel | `changeMotion(bank, motion, frame, interpFrame, InterpolationMode, InterpolationCurve)` nur beim Wechsel. Bild nicht jeden Frame setzen, sonst bleibt die Überblendung hängen (nur Idle). Leere Ebene: `changeMotion(0, 0xFFFFFFFF, …)` | ✅ |
| Überblendung | je Übergang 6 bis 36 Bilder, Modus 1 FrontFade / 2 CrossFade / 3 SyncCrossFade, Kurve 0 bis 3. Ohne sie zuckt die Puppe | ✅ |
| Tempo | `get_Speed` der Ebene war beim Gehen, Joggen und Zielen immer 1 | ✅ |
| Steuer-Variablen | `Motion.get_VariablesHub()`, 47 Variablen (`getVariableFromIndex`, `get_Name`, `get_TypeKind`: 2 = Boolean, 11 = Single, 16 = Trigger). Sie bestimmen die Mischung im Baum. Ohne sie spielt die Puppe im Geh-Baum immer Knoten 240 (Rutschen). Laufend ändern sich `MoveDir`, `TargetMoveDir`, `WatchDir`, `TargetWatchDir`, `CameraDir`, `SlopeAngle`, `Pitch` (−58 bis 16), `WatchStickPowerH`. An der Puppe mit `set_F32`/`set_Bool` setzbar, die eigene Steuerung der Puppe überschreibt sie nicht | ✅ |
| `trySetNodeParameter` | wird vom Spiel nicht aufgerufen (Hook ohne Treffer) | ✅ |
| Root-Motion | Bei der Puppe auf `Continuance` (2), auf `None` (0) stellen. Position und Drehung kommen aus dem Netzwerk, die Drehung geglättet (`ghost.lua`) | ✅ |
| Schießen | Ebene 4: `2/1100 HG_Hold_Shoot`, ohne Munition `2/1120 HG_Hold_Shoot_NoAmmo`. Bei schnellen Schüssen je Schuss 1 Bild `2/1120`, dann `2/1100` (darum der Start-Zähler `restartN`). `Fire` ist nur 1 Bild an. Mit Testbot: 7 schnelle Schüsse → 7 bei der Puppe | ✅ 3. November 2026 |
| Nachladen | Ebene 3: `2000/1200 HG_Hold_Reload`, Zielen beginnen `2/140` | ✅ |
| Waffe | Echte Waffe = Kind-Objekt `wp0000` am Gelenk `r_weapon` (Mesh `SectionRoot/Character/Weapon/wp0000/wp0000_VP70.mesh` + `.mdf2`, dazu `implement.Gun`, Hülsen, Sound). Puppe bekommt nur ein Modell: `via.GameObject.create` + `via.render.Mesh`, `set_Parent` + `set_ParentJoint("r_weapon")`, lokale Drehung wie beim Spieler (0.5, 0.5, −0.5, −0.5) | ✅ |
| Treffer, Tod | `Damage`, `Dead` werden noch nicht übertragen | ❓ |
| Claire, andere Waffen | Bank-Pfade werden übertragen, sollte also gehen | ❓ |

## Zweite echte Spielfigur (Claire, wie der Partner in RE0)

Am 3. November 2026 per Entwickler-Konsole geprüft (Leon-Spielstand, Polizeistation):

| Was | Befund | Status |
|---|---|---|
| Prefab | `SurvivorManager.<PrefabInfoList>` enthält `ObjectRoot/Prefab/Character/Player/pl1000.pfb` (Claire, nicht geladen). Eigenes `via.Prefab` mit `set_Path` + `set_Standby(true)` → nach 0,06 s `get_Ready` | ✅ |
| Erzeugen | `instantiate(pos, rot, <Ordner des Spielers>)` → GameObject `pl1000` mit 90 Komponenten (`PlayerController`, `PlayerCondition`, `PlayerActionOrderer`, `via.physics.CharacterController`, `SurvivorCharacterController`, `app.Collision.HitController` …). Kein Absturz, `PlayerManager.get_CurrentPlayer` bleibt Leon | ✅ |
| Modell | zuerst unsichtbar, `SurvivorCostumeChanger.change(1, 0)` lädt Hair/Face/Body → Claire sichtbar mit Idle-Animation | ✅ |
| Eingaben | Claire läuft mit dem Controller des Users mit (Gehen-Animationen, bis 2,1 m bewegt). Es gibt nur ein globales `app.ropeway.InputSystem` (`isOn/isDown/isUp(Kind)`, `getStick`, `getAnalogTrigger`, `InputUnitList`, `getInputUnit(PadKind)`). Für den Koop müssten diese Abfragen abgefangen werden, während Claire aktualisiert wird | ✅ |
| Eingabegeräte | `InputDefine.PadKind`: `INVALID`, `USER_0` … `USER_3`. 5 `InputUnit`s. Leon und Claire haben beide `USER_0` (1), nur dort hängt ein Gerät | ✅ 3. November 2026 |
| `PlayerCondition.get_PadKind()` | Kein Feld, wird berechnet (ca. 500 Aufrufe/s für Claire). Per Hook auf `USER_1` umgebogen: **wirkungslos**, Claire läuft weiter mit | ✅ (Sackgasse) |
| `InputSystem.ActiveUserPadKind` umschalten | Während Claires Updates auf `USER_1`: **wirkungslos**, und Leon zittert. Ursache: Die Engine aktualisiert die Figuren **parallel in mehreren Threads** (Claire auf 9 Threads), eine globale Umschaltung trifft auch Leon (276 von 1.424 Leon-Updates im Fenster) | ✅ (Sackgasse) |
| **Lösung: Abfragen pro Thread überschreiben** | Pre-/Post-Hooks auf `update`/`lateUpdate` von Claires Komponenten (`app.ropeway.survivor.*`, 20 Methoden) merken pro `thread.get_id()`, ob der Thread gerade Claire aktualisiert. Post-Hooks auf 45 Abfrage-Methoden von `InputSystem` (`is*On/Down/Up/Front/Back/Left/Right`, `checkCommand` → `false`; `getStick`/`get_LStick`/… → `DummyStick`) geben nur in diesem Fall „keine Eingabe“ zurück. **Claire steht still, Leon lässt sich normal steuern** (im Spiel bestätigt). Etwa 950 Knopf- und 250 Stick-Abfragen pro Sekunde für Claire | ✅ 3. November 2026 |
| **Eingaben einspeisen** | Eigener Speicher für Claire: Knopfmaske `on` (UInt64, Bits = `InputDefine.Kind`, z. B. `HOLD` 64, `ATTACK` 256, `RELOAD` 512, `JOG0` 8), `down`/`up` werden pro Frame aus `on` berechnet (in `re.on_pre_application_entry("UpdateBehavior")`). Zwei eigene `InputSystem.AnalogStick`-Instanzen (`sdk.create_instance` + Setter `Axis`, `RawAxis`, `Direction`, `Angle`, `Magnitude`, `Power*`, `…Old`). Antworten in Claires Threads: `isOn/isDown/isUp` mit Kind oder Maske (bei `(UInt64, Boolean all)` alle bzw. ein Bit), `getStick(Kind)` mit `MOVE`→links und `WATCH`→rechts, `getStick(AnalogStick.Kind)` 1/2, `get_LStick`/`get_RStick`. Andere Richtungsabfragen und `checkCommand` → false. **Schleifen-Test: Claire läuft, zielt und schießt mit, wenn Leons Eingaben eingespeist werden** | ✅ 3. November 2026 |
| Analoge Trigger | `getAnalogTrigger` per `sdk.float_to_ptr` eingehängt, im Test aber nie aufgerufen (Controller läuft über Knopf-Bits) | ❓ |
| Einspeise-Skript | `games/re2r/research/claire_einspeisen_test.lua` (so im Spiel ausgeführt) | ✅ |
| **Mod 0.7.x mit Testbot** | Zweiter Leon als echte Spielfigur, gesteuert über `INPUT_STATE` (1 s verzögert): Er läuft aus eigener Kraft mit Gehanimationen. `Transform.set_Position` wirkt trotz CharacterController | ✅ 3. November 2026 |
| Positionskorrektur | Hart ab 1,5 m: 7 Sprünge in 16 s, sah aus wie ständiges Teleportieren. Jetzt sanft (3 × Abweichung pro Sekunde, Sprung erst ab 3 m) | ✅ |
| Kamera-Umrechnung der Sticks | Sticks sind kamerarelativ. Drehung um `cam_yaw_sender − cam_yaw_empfänger` (`YAW_SIGN = −1`): mittlere Abweichung beim Laufen mit Kameradrehung **0,25 m** (höchstens 1,0 m), mit dem anderen Vorzeichen etwa 0,9 m (höchstens 2,5 m) und Laufen in falsche Richtungen | ✅ 3. November 2026 |
| Versuchsskript | `games/re2r/research/claire_eingaben_test.lua` (über die Konsole ausführen). Fasst die bestätigten Konsolen-Versuche zusammen, als Datei noch nicht im Spiel ausgeführt | ❓ |
| Kollision | Der User fühlte sich „hin und her geschoben“, wahrscheinlich von Claire | ❓ |
| Kamera, HUD, Inventar, Gegner mit zwei Spielern | | ❓ |

## Spielstände (für den Join auf den Stand des Hosts)

Am 3. November 2026 untersucht:

| Was | Befund | Status |
|---|---|---|
| Dateien | `<Steam>\userdata\<Konto>\883710\remote\win64_save\`: `data000.bin` (System, 730 KB), `data001Slot.bin`, `data002Slot.bin` (je ca. 1,7 MB, Speicherplätze), `data021Slot.bin` (1 KB, Platz 21 = Checkpoint, `SaveDataManager.RogueCheckPointDataNumber`), `data00-1.bin` (5 KB) | ✅ |
| Format | Alle beginnen mit `DSSS` + Version 2, danach vollständig verschlüsselt (Entropie 8,0). Steam-ID nicht im Klartext | ✅ |
| Kontobindung | Ob ein fremdes Konto die Datei lesen kann | ❓ |
| Im Speicher | `gamemastering.SaveDataManager`: `GameSaveDataValue` (`SaveDataManager.GameSaveData`) ist der Spielstand als Objekt. `GameSaveManagerDic` (`UInt32` → `IGameSaveData`) sind alle beteiligten Manager (z. B. `PlayerManager.saveGameSaveData()` / `loadGameSaveData(SaveDataBase)`). `saveGameSaveData()` sammelt, `loadGameSaveData()` verteilt. Laden über `requestLoadGameData(SaveMode, Index)`, aktueller Platz `LoadGameDataIndex` (2) | ✅ (nur gelesen) |
| `GameSaveDataList` | 32 Teile (`SaveDataBase`), u. a. `PlayerManager`, `InventoryManager`, `ItemManager`, `ItemLockerManager`, `EquipmentManager`, `GimmickSetManager` (12.700 Objekte, Türen/Rätsel), `EnemyManager`, `ScenarioSequenceManager`, `MainFlowManager.GameHeaderSaveData`, `GameClock`. Insgesamt ca. 25.000 Objekte, 83.000 Felder (Zahlen, bool, Text, Objekte, Arrays, `via.vec3`, `via.Quaternion`, Werttypen). Durchlaufen per Reflection: 0,2 s | ✅ |
| `via.Serializer` | `serializeJson`/`deserializeJson`, `serializeMessagePack`/`deserializeMessagePack(Type, Objekt, Options)` gibt es, über REFramework `method:call` kommt aber Müll (JSON 3 Zeichen) bzw. „not a managed object“ (MessagePack) | ❓ (Sackgasse vorerst) |
| `SaveService.exportToMemory`/`importFromMemory` | Statisch, mit `ExportToMemoryParam` (`TargetSlotTbl`, `MemoryArray`) bzw. `ImportFromMemoryParam`. Ob verschlüsselt, ist unbekannt | ❓ |
| Ladeablauf | `requestLoadGameData(SaveMode, Index)` → ca. 1 s später `SaveDataManager.loadGameSaveData()` (Datei eingelesen, Liste mit 32 Teilen, kein Spieler) → sofort `PlayerManager.loadGameSaveData` usw. Danach ist `GameSaveDataList` **leer** | ✅ |
| **Einspielen beim Laden** | Pre-Hook auf `SaveDataManager.loadGameSaveData`: Die 32 Listeneinträge durch die eines vorher aufgenommenen Ladevorgangs ersetzen (es sind jedes Mal neue Objekte). Ergebnis: Die Daten wirken (Spieler steht an der Startposition des anderen Stands, `LoadLocation` = dessen Ort), **aber das Laden der Umgebung hängt** (`IsFinishedLoadScene` bleibt false, MainState 4), wenn der Ort des eingespielten Stands nicht zum geladenen Platz passt (Straße eingespielt beim Laden der Eingangshalle). Ein `requestLoadGameData` von der Konsole holt das Spiel nicht heraus, Neustart nötig | ✅ 3. November 2026 (teilweise) |

## Werkzeuge zum Selbst-Ansehen

- `powershell -File tools/spielfoto.ps1 -Prozess re2 -Datei <pfad.jpg>`: Foto des RE2-Fensters (Fenstermodus nötig).
- Entwickler-Konsole `camera(function() return pos, ziel end)`: setzt die Spielkamera vor `LockScene` (in `BeginRendering` wirkungslos), `camera(nil)` gibt sie zurück. Ziel z. B. ein Gelenk: `transform:call("getJointByName", "r_weapon"):call("get_Position")`.
- Achtung: `Motion:getWorldPosition(j)` liefert keine Weltkoordinaten, `os.clock()` ist keine Wanduhr (`coopnet.time()` nehmen).

## Weitere Kandidaten aus der Diagnose

- `PlayerManager.get_CurrentPlayerType()` → `PlayerDefine.PlayerType`
- `gamemastering.MainFlowManager.get_LoadArea()` → `Map.ID`, `get_LoadLocation()` → `Location.ID`, `get_LoadSurvivorType()`
- `gamemastering.UIMapManager.get_SceneMapId()` → `Map.ID`, `get_DispLocationId()` → `Location.ID`
- `EnemyManager.get_onFixedAreaChange()`: Ereignis `Action<Map.ID, Map.ID>` beim Bereichswechsel (für später: Mr. X, Gegner-Sync)
- Für Meilenstein 2: `SurvivorManager`, `SurvivorAssignManager`, `level.SurvivorStandbyManger`, `NPCAccessManager`
