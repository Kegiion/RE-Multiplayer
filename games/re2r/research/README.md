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
| Weitere Figuren | `SurvivorType` hat 56 Werte (`PL0000`, `PL1000`, `PL2000`, … bis `PL9900`), keine Klarnamen. `PL1000` = Claire (Wert 1, Modell `pl1000`, bestätigt 5. November 2026) | ✅ |

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
| Einspielen am selben Ort | Auch Platz 1 → Platz 2 (beide Eingangshalle) hängt. `LoadGameDataFlow.StateValue = LOAD_LEVEL_FOLDER_WAIT`. Die gemerkten Objekte sind vollständig (z. B. `GimmickSetManager` 14.260 Objekte), wurden aber vermutlich beim ersten Laden **verändert** (Laufzeit-Zustand). **Folgerung: beim Einlesen eine echte Kopie (Serialisierung) anlegen**, nicht die Objekte selbst merken | ✅ 3. November 2026 |
| Tiefe Kopie, alles geklont | `MemberwiseClone` je Objekt, `Clone` je Array, Verweise umgebogen (19.445 Objekte, 1.039 Arrays, 0,36 s). Beim Einspielen: **Absturz „Fatal D3D error (25)“**, weil auch Engine-Objekte geklont wurden | ✅ (Sackgasse) |
| Engine-Typen im Spielstand | Nur `via.userdata.Variable[]` (125×, aus `GlobalUserDataManager`) und `via.wwise.WwiseSavableSetStateParam[]` (1×). Sonst `app.ropeway.*` (ca. 16.000), `System.Collections.*` (505), Zahlen-/bool-/Guid-Arrays | ✅ |
| **Tiefe Kopie, Engine-Objekte geteilt** | `re2r_coop/savestate.lua` `deep_clone`: Spieldaten, Listen und Arrays geklont, `via.*`, Delegates und Typobjekte geteilt (15.841 Objekte, 913 Arrays, 126 geteilt, 0,32 s). Kopie von Platz 1 beim Laden von Platz 2 eingespielt: **lädt durch, und es ist Platz 1** (Spielzeit 8.468.177.972 ≈ Platz 1 + 21 s, Inventar- und Pausenzeit exakt wie Platz 1) | ✅ 3. November 2026 |
| **Anderer Ort** | Saubere Kopie von Platz 0 (Straße, 2.893 Objekte, 0,08 s) beim Laden von Platz 1 (Eingangshalle) eingespielt: **lädt durch, Spieler auf der Straße** (`Opening3`, `st8_410_0`). Der frühere Hänger lag nur an den veränderten Originalobjekten. Der Freund kann also einen beliebigen eigenen Platz laden | ✅ 3. November 2026 |
| Bausteine in REFramework | `td:create_instance()` geht für normale Klassen, **nicht** für generische Listen (nil). `MemberwiseClone` geht für alles. Arrays: `sdk.create_managed_array("System.Int32", n)` und `System.Array.CreateInstance(typeof(System-Typ), n)` gehen, für Spieltypen werfen beide. Zahlen in Arrays kommen verpackt (`mValue`, oder `array:Get(i)`), Schreiben mit `arr[i] = v`. `ValueType.new(td)`, `sdk.create_managed_string`, `Vector3f` gehen | ✅ |
| **Live-Stand des Hosts** | Die Manager in `SaveDataManager.GameSaveManagerDic` liefern mit `saveGameSaveData()` jederzeit ihren Teil (32 Teile), ohne zu speichern. `SaveDataManager.saveGameSaveData()` selbst füllt die Liste **nicht**. Polizeistation: ca. 20.000 Objekte, 0,1 s, als Bytes (`remultiplayer_coop/serial.lua`) 940 KB | ✅ 3. November 2026 |
| Live gegen Datei | Unterschiede: Feld `Hash` ist live bei 7 Teilen `0` (in der Datei = Schlüssel des Managers), Spielzeit, Positionen, Reihenfolge der Inventarlisten, leere Texte `""` live `nil`. **Mit `Hash = 0` hängt das Laden in `LOAD_SCENE_FOLDER_WAIT`.** `capture_live` setzt `Hash` deshalb auf den Schlüssel | ✅ 3. November 2026 |
| **Join ohne Netzwerk** | `capture_live` → Bytes → zurück → beim Laden eines anderen Platzes (Straße) per `apply_to_list` auf die frisch eingelesenen Objekte gespielt: **lädt durch, Spieler exakt an der aufgenommenen Stelle in der Eingangshalle** (32 Teile, 3.490 Spielvariablen, 1.214 neue Objekte, 0,2 s) | ✅ 3. November 2026 |
| **Join übers Netzwerk (Mod 0.8.0)** | Spiel tritt dem Testbot im Host-Modus bei, der Bot holt per `SAVE_REQUEST` den Stand (904 KB), „Spielstand des Hosts holen“ schickt ihn zurück, danach Laden eines anderen Platzes: eingespielt mit 32 Teilen, 3.490 Variablen, 15.425 Objekten, **0 Fehlern**, Spieler in der Eingangshalle | ✅ 3. November 2026 |
| **Automatisch laden (Mod 0.9.0)** | Direkt `MainFlowManager.goLoadGameData()` aus dem Spiel: hängt in `LOAD_SCENE_FOLDER` (Hauptablauf noch `IN_GAME`). Funktioniert: `goResetGameToStoryContinue()` (zurück zum Titel, `_CurrentMainState` 3), dann `SaveDataManager.requestLoadGameData(Modus, Platz)`, warten bis `get_saveLoadStep` wieder 1, dann `goLoadGameData()` → nach 2,4 s `IN_GAME` (6). `GUI_TitleMenu` bleibt sichtbar und wird per `set_DrawSelf/set_UpdateSelf(false)` ausgeblendet, Steuerung danach normal. Das Pausenmenü macht `requestLoadGameData(1, 1)`, ca. 1 s später ruft der Ablauf selbst `goLoadGameData` | ✅ 3. November 2026 |
| **Laden aus dem Titelmenü (Mod 0.10.0)** | Im Titel (MainState 3) geht `requestLoadGameData` + `goLoadGameData` ohne Zurücksetzen, aus dem Hauptmenü und aus „Kampagne → Spiel laden“. Ist „Spiel laden“ offen, lädt das Spiel nach `requestLoadGameData` selbst weiter (`TitleFlow` → `FINALIZE` 29, MainState 4), ein zweites `goLoadGameData` ist dann unnötig. Die offenen Menüs (`GUI_MenuMain`, `GUI_MenuStory`, `GUI_Load`, `GUI_TitleMenu`, `GUI_GeneralGuide`) bleiben über dem Spiel stehen und werden per `Behavior.enableObject(false)` ausgeblendet (so macht es das Spiel, DrawSelf/UpdateSelf gehen mit aus). Steuerung danach normal, Pause → Titel → Kampagne funktioniert. `TitleFlow.StateValue = 27` (`TITLE_SAVEDATA_LOAD_END`) bewirkt nichts. Achtung: Mehrfaches Ausblenden und `goResetGameToStoryContinue` von der Konsole hintereinander ließ das Titelmenü in `WAIT_GUI_ANIMATION` (100) hängen, Neustart nötig | ✅ 4. November 2026 |
| Titelmenü-Aufbau | Hauptmenü dieser Version: `GUI_MenuMain` (`gui.MenuMainBehavior`: `Selector` = `via.gui.ScrollList`, `CallbackOnDecide` mit `MenuMainBehavior.DecidedResult`, `initList`). Ablauf: `MainFlowManager.<Title>` = `gamemastering.TitleFlow`, `StateValue` (Enum `TitleFlow.State`: TITLE_PRESS_START 6, TITLE_MENU_MAIN 10, TITLE_MENU_STORY 11, TITLE_MAIN_SCENARIO_LOAD 16, FINALIZE 29, WAIT_GUI_ANIMATION 100), `LoadDataIndex` | ✅ 4. November 2026 (nur gelesen) |
| Speicherplätze | `SaveDataManager.getSaveFileDetailList(1)` → Liste `via.storage.saveService.SaveFileDetail` (21 Einträge, leere sind nil), `get_Slot` = Platz für `requestLoadGameData`, `get_LastUpdateTimeStamp`, `get_SubTitle` z. B. „Speicherdaten – Platz 2 Leon“. Platz 0 ist der Auto-Speicherstand. Außerdem gibt es `requestLoadLatestGameData(Modus)` (ungetestet) | ✅ 4. November 2026 |
| **Eigener Menüeintrag (Mod 0.10.0)** | Post-Hook auf `MenuMainBehavior.initList`: Wert 7 (`DecidedResult.MAX`) in `DecidedList` einfügen, `Selector.set_ItemMax/ItemCount` erhöhen, die ScrollList legt die Zeile selbst an. Texte: vorher `MessageId` je Zeile merken und zurückschreiben, eigene Zeilen `set_MessageId(leere Guid)` + `set_Message` (die ID hat Vorrang). Kinder der ScrollList stehen umgekehrt. Auswahl: Pre-Hook auf `TitleFlow.<update>b__39_19(DecidedResult)`, eigene Werte mit `SKIP_ORIGINAL` überspringen. Danach blendet das Spiel das Menü aus und wartet (`WAIT_GUI_ANIMATION`), `TitleFlow.StateValue = 10` öffnet es neu (initList läuft wieder). So entsteht ein Untermenü mit eigenen Zeilen (Werte ab 100). Hilfetext unten: `GUI_GeneralGuide` → `main/c_guide/m_guide`. Tasten sperren: `MenuMainBehavior.set_EnableInput(false)`. Tastatur lesen: `via.hid.Keyboard.get_Device()` (`MergedKeyboardDevice`), `isTrigger/isDown(via.hid.KeyboardKey)`. Umlaute in der Spielschrift gehen | ✅ 4. November 2026 |
| **Figur im Spielstand** | `MainFlowManager.GameHeaderSaveData`: `SurvivorTypeValue` (`SurvivorDefine.SurvivorType`, 0 = Leon `PL0000`, 1 = Claire `PL1000`), `ScenarioTypeValue` (`MainFlowManager.ScenarioType`: 0 `LEON_A`, 1 `CLAIRE_A`, 2 `LEON_B`, 3 `CLAIRE_B`, 4 `HUNK`, 5 `TOFU`, 6 `ROGUE`), dazu `GameStartTicks`/`FirstSaveTicks` (Spielbeginn). Nur `SurvivorTypeValue` = 1 vor dem Einspielen setzen → **Claire (`pl1000`) lädt in Leons Welt** (Szenario `LEON_A` bleibt), sichtbar, steuerbar. `PlayerManager.GameSaveData.PlayerType` stellt das Spiel selbst um (live 0 Leon, 1000 Claire) | ✅ 5. November 2026 |
| **Inventar im Spielstand** | `InventoryManager.SaveData.DataLists`: je Figur ein `inventory.Data` (`_SurvivorType`, im Leon-Stand 0 und ein unbenutzter Eintrag −1). `_Stocks` = 20 `StockItem` (`Index`, `DefaultItem`/`AdditionalItem` = `PrimitiveItem` mit `ItemId`, `WeaponId`, `BulletId`, `Count`, `WeaponParts`, dazu `ExData`, `IsWeaponEquip`), `_CurrentSlotSize` (8), `_MainData` (ausgerüsteter Platz), `_ShortcutDataList`, `_SubData`. Leer = `ItemId 0, WeaponId −1, Count 1`. Waffen: `ItemId 0`, `Count` = Schuss im Magazin, `BulletId` = Munitions-Item. Leon → Leon-Join übernimmt das Inventar des Hosts exakt | ✅ 5. November 2026 |
| **Itemkiste im Spielstand** | `ItemLockerManager.GameSaveData.SaveData` (`GimmickItemLockerControl.ItemLockerSaveData`) `._Items`: 400 `InventoryManager.ItemData`, eine Kiste (nicht je Figur). Alle auf leer gesetzt → Kiste im Spiel leer | ✅ 5. November 2026 |
| Waffen und Items | `EquipmentDefine.WeaponType`: 1 Matilda, 2 M19, 3 JMB Hp3, 4 Quickdraw Army (Namen im Inventar abgelesen), 5 gibt es nicht, 6 ungültig. 182/192/202 (`WP8000`/`WP8100`/`WP8200`) sind **keine** Messer („Invalid Weapon ID“), das Messer ist noch offen. `Item.ID` heißen nach Modellen (`sm70_000` …, 298 Werte): 15 (`sm70_100`) = Pistolenmunition (Matilda und JMB laden damit nach). Vermutung: `sm70_0xx` Heilung, `sm70_1xx` (15–30) Munition, `sm70_2xx` Schießpulver, `sm73_xxx` Schlüssel-Items | ✅ Waffen 1–4 und Item 15, ❓ Rest |
| Claire mit Leons Waffen | Claire kann Leons Matilda und M19 ausrüsten, zielen und schießen (Animation ok) | ✅ 5. November 2026 |
| Speichern erkennen | Pre-Hook auf `SaveDataManager.requestSaveGameData` (bzw. `requestSaveGameDataAuto`) läuft beim Speichern an der Schreibmaschine | ✅ Schreibmaschine 5. November 2026, ❓ automatisch |
| Fehler beim Kollegen (3. Nov.) | Eigenes Inventar, eigene Kiste und eigene Figur behalten: Nach Leon → Leon-Join stimmt alles, deshalb wurde beim Kollegen vermutlich gar nicht eingespielt (Hänger im Titelmenü, danach eigener Platz geladen) | ❓ (Vermutung) |
| **Join mit eigener Figur (Mod 0.11.4)** | Testbot-Spiegel, eigener Leon-Stand: Mitspieler lädt als Claire mit JMB Hp3 und der Pistolenmunition des Hosts, Kiste leer. Sicherung (`savejoin.on_host_saved`, Datei `reframework/data/re2r_coop_inventory.json`, Schlüssel = `GameStartTicks_FirstSaveTicks` des Hosts) und erneutes Beitreten nach „Reset Scripts“: gesichertes Inventar zurück (22 statt 24 Schuss). Leere Listen stehen in der JSON-Datei als `null` | ✅ 5. November 2026 |
| Spielsprache | `via.gui.GUISystem.get_MessageLanguage()` (natives Singleton) = 4 bei deutschem Text. `get_SubtitleLanguage`/`get_SpeechLanguage` liefern nil. Englisch (erwartet 1) noch nicht gegengeprüft | ✅ de, ❓ en |
| Generische Typen anlegen | `td:create_instance()`, `sdk.create_instance` → nil, `sdk.typeof` → nil, `Activator.CreateInstance` wirft. Betrifft z. B. `GimmickControlExtendSaveData`1<…ItemLockerSaveData>`, `GimmickBodyExtendSaveData`1<…GimmickElevator…>`: Fehlt so ein Objekt beim Freund, bleibt dieses Rätsel/dieser Schalter im Grundzustand (11 Stück beim Test Straße → Halle) | ✅ (offen) |
| Arrays und Listen anlegen | `sdk.create_managed_array(TypeDefinition, n)` geht auch für Spieltypen und Werttypen. Listen: `mItems`/`mSize` direkt setzen. Dictionaries: `Clear` + `set_Item` | ✅ |

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
