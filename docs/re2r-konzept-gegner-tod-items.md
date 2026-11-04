# RE2 Remake: Konzept Gegner, Tod und Items

Stand: 4. November 2026, Mod 0.9.1, Protokoll 3. Grundlage sind die Design-Entscheidungen des Users in `docs/ROADMAP.md`.

Dieses Dokument legt fest, **was** übertragen wird und **wer** entscheidet. Wie das Spiel intern funktioniert, wissen wir für Gegner, Tod und Items noch fast nicht. Jeder Teil endet deshalb mit der Liste **„Im Spiel zu erforschen“**. Alles dort ist **unbestätigt**. Als bestätigt gelten nur die Fakten aus `games/re2r/research/README.md`.

Neue Nachrichten sind hier nur **Vorschläge**. `protocol.lua` ändert der Projektleiter nach Abstimmung (siehe „Vorschlag fürs Protokoll“ am Ende).

## Ausgangslage (bestätigt)

- Jeder Spieler hat sein eigenes Spiel. Der Mitspieler lädt beim Beitreten den Live-Stand des Hosts (`savejoin.lua`, 32 Teile aus `SaveDataManager.GameSaveManagerDic`, darunter `EnemyManager`, `InventoryManager`, `ItemManager`, `GimmickSetManager`). Beide Welten **starten also gleich**, laufen danach aber auseinander.
- Der Mitspieler ist in der Welt des anderen eine **echte zweite Spielfigur** (`partner.lua`, Player-Prefab mit `PlayerCondition`, `HitController`, `CharacterController`) und wird über seine Eingaben (`INPUT_STATE`) gesteuert. Er läuft, zielt und schießt aus eigener Kraft. Abweichung zur echten Position: im Mittel 0,25 m, höchstens 1,0 m.
- Bereich = Zone `Map.ID` (`PlayerCondition.get_StaySceneAreaID()`), z. B. `st4_101_0`. In Zwischensequenzen ist die Zone kurz `Invalid`.
- `EnemyManager.get_onFixedAreaChange()` ist ein Ereignis `Action<Map.ID, Map.ID>` beim Bereichswechsel (aus der Diagnose, noch nicht benutzt).
- `PLAYER_STATE.flags` ist bisher immer 0 und kann für Zustände genutzt werden.

## Grundsätze

1. **Der Host besitzt die Welt.** Gegner, Weltitems und der Ausgang eines Todes werden beim Host entschieden. Der Mitspieler meldet, der Host bestätigt.
2. **Treffer zählen so, wie der Schütze sie sieht.** Wer schießt, erkennt den Treffer in seinem eigenen Spiel und meldet ihn. Sonst sieht der Mitspieler Treffer, die beim Host danebengehen (Zielrichtung und Position weichen bis 1 m ab).
3. **Kein doppelter Schaden.** Die Partner-Figur schießt in der Welt des Hosts mit. Ihr Schaden an Gegnern wird beim Host unterdrückt, es zählt nur die Meldung des Mitspielers.
4. **Lieber selten etwas doppelt als festhängen.** Bei gleichzeitigen Aktionen (beide heben dasselbe Item auf) gewinnt der Host bzw. die erste Meldung. Kleine Unstimmigkeiten werden nicht zurückgedreht.
5. **Erst die einfache Fassung.** Packen, Beißen und Haltegriffe (Zombie packt den Spieler) kommen in einer zweiten Stufe.

---

## Teil 1: Gegner (Meilenstein 3)

### Wer simuliert welche Gegner?

Beide Spiele laden für eine Zone dieselben Gegner, weil beide vom selben Stand ausgehen. RE2 lädt Zonen aber nur um die **eigene** Spielfigur herum (vermutet, siehe Forschung). Daraus folgt eine Regel pro Zone (`enemy_net.zone_owner`):

| Lage | Besitzer der Gegner in der Zone | Verhalten |
|---|---|---|
| Host ist in der Zone (oder hat sie geladen) | **Host** | Beim Host läuft die echte KI. Beim Mitspieler sind dieselben Gegner **Puppen**: KI aus, Position, Drehung und Animation kommen vom Host. |
| Nur der Mitspieler ist in der Zone | **Mitspieler (geliehen)** | Beim Mitspieler läuft die echte KI. Er meldet Spawn, Lebenspunkte und Tod an den Host. Der Host trägt Tode in seine Welt ein, damit die Gegner nicht wieder auftauchen. |
| Keiner ist da | niemand | Nichts zu tun. |

Kommt der Host in eine geliehene Zone, geht der Besitz an ihn zurück: Der Mitspieler schickt einen letzten Stand (`ENEMY_HANDOVER`), der Host übernimmt Lebenspunkte und Position, danach sind die Gegner beim Mitspieler wieder Puppen. Die Übergabe dauert einen Moment, dafür reicht es, wenn die Gegner beim Wechsel kurz stehen bleiben.

So bleibt die Host-Welt maßgeblich, und trotzdem können sich die Spieler frei trennen (Design-Entscheidung).

### Kennung eines Gegners

Beide Spiele müssen sich einig sein, welcher Gegner gemeint ist.

- **Bevorzugt:** eine stabile Kennung aus dem Spiel, die beim Laden desselben Stands gleich ist (z. B. aus der Spawn-Tabelle oder den Spielstand-Daten des `EnemyManager`). Ob es so etwas gibt, ist die wichtigste Forschungsfrage (E1).
- **Notlösung:** Der Besitzer vergibt eine Netz-Kennung `eid` (uint16) und schickt Art, Zone und Startposition. Die Gegenseite ordnet den nächstgelegenen Gegner derselben Art in derselben Zone zu (bis 2 m Abstand). Ohne Treffer erzeugt sie keinen eigenen Gegner, sondern zeigt ihn erst einmal nicht an.

Die `eid` gilt nur für die laufende Verbindung. Für das Eintragen von Toden in die Welt des Hosts braucht es aber die stabile Kennung aus dem Spiel (`key`).

### Was wird übertragen

| Daten | Wann | Kanal |
|---|---|---|
| Spawn (Art, Zone, Kennung, Position, Lebenspunkte) | einmal beim Erscheinen und bei Neuverbindung | reliable |
| Position, Drehung, KI-Modus, Ziel, Animation (Ebene 0) | **10× pro Sekunde**, alle Gegner der Zone in einem Paket | unreliable |
| Lebenspunkte | bei Änderung | reliable |
| Tod / Entfernen | einmal | reliable |
| Treffer des Mitspielers | je Treffer | reliable |
| Schaden an einem Spieler | je Treffer | reliable |

10× pro Sekunde reicht für Gegner, die meist langsam sind. Die Puppen werden wie bei `ghost.lua` geglättet. Für Animationen genügt in der ersten Fassung Ebene 0 (Körper). Wenn das zu ruckelig ist, kommen weitere Ebenen dazu (wie bei `ANIM_STATE`).

### Nachrichten (Vorschlag)

IDs ab 10, da 1 bis 9 belegt sind.

| ID | Name | Richtung | Kanal | Felder | Größe |
|---|---|---|---|---|---|
| 10 | `ENEMY_SPAWN` | Besitzer → andere | reliable | `eid` I2, `kind` s1 (Art, z. B. Prefab-Name), `key` s1 (stabile Kennung, "" = keine), `zone` I2 (`Map.ID`), `x`,`y`,`z` f, `yaw` f, `hp` f, `hp_max` f, `flags` B | 32 B + Texte |
| 11 | `ENEMY_STATE` | Besitzer → andere | unreliable | `seq` I4, `zone` I2, `data` s2 = Anzahl B + je Gegner 26 Bytes (`enemy_net.pack_states`) | 10 + 26 × n B, bei 20 Gegnern 530 B, also ca. 5 KB/s |
| 12 | `ENEMY_HP` | Host → Mitspieler bzw. Leihbesitzer → Host | reliable | `eid` I2, `hp` f, `flags` B (Bit 0 = betäubt/umgefallen, Bit 1 = Körperteil verloren) | 8 B |
| 13 | `ENEMY_DEAD` | Besitzer → andere | reliable | `eid` I2, `key` s1, `zone` I2, `killer` B (0 Host, 1 Mitspieler, 2 Umgebung) | 7 B + Text |
| 14 | `ENEMY_DESPAWN` | Besitzer → andere | reliable | `eid` I2, `reason` B (0 Zone entladen, 1 Besitzwechsel) | 4 B |
| 15 | `ENEMY_HIT` | Mitspieler → Host | reliable | `hit_seq` I4, `eid` I2, `damage` f, `part` B (Körperteil), `weapon` I2, `flags` B (Bit 0 = kritisch, Bit 1 = Messer) | 15 B |
| 16 | `PLAYER_HIT` | Host → Mitspieler | reliable | `eid` I2, `damage` f, `kind` B (0 normal, 1 Packen beginnt, 2 Packen endet), `dir` f (Richtung des Treffers) | 12 B |
| 17 | `ENEMY_HANDOVER` | Leihbesitzer → Host | reliable | `zone` I2, `data` s2 (je Gegner `eid`, `key`, Position, `hp`) | variabel |

Datensatz in `ENEMY_STATE` (`enemy_net.RECORD`, 26 Bytes): `eid` I2, `x`,`y`,`z` f, `yaw` i2 (Radiant × 10000), `mode` B (KI-Zustand, spielabhängig), `target` B (0 keins, 1 Host, 2 Mitspieler), `bank` I2, `motion` I4, `frame` I2 (Bild × 10). Bis 255 Gegner pro Paket. Das Packen und Entpacken ist schon gebaut und getestet (`re2r_coop/enemy_net.lua`, `tests/lua/re2r_coop_logic_test.lua`).

### Ablauf: Mitspieler trifft einen Gegner (Host besitzt ihn)

1. Der Mitspieler schießt in seinem Spiel auf die Gegner-Puppe. Sein Spiel erkennt den Treffer und will Schaden abziehen.
2. Ein Hook auf die Schadensverarbeitung der Puppe **verhindert den Abzug** und schickt `ENEMY_HIT` mit Schaden und Körperteil. Die Treffer-Reaktion (Blut, Zucken) darf lokal sofort laufen, das fühlt sich direkt an.
3. Der Host prüft grob: Gegner lebt, Abstand zwischen Partner-Figur und Gegner passt zur Waffe, nicht mehr Treffer als die Waffe schießen kann. Dann zieht er den Schaden am echten Gegner ab (am liebsten über die Schadensmethode des Spiels, damit Betäuben, Umfallen und Körperteile wie gewohnt funktionieren).
4. Der Host schickt `ENEMY_HP`, bei Tod `ENEMY_DEAD`. Beim Mitspieler fällt die Puppe dann um (Animation aus `ENEMY_STATE`), danach bleibt sie liegen bzw. wird entfernt.

Schüsse der Partner-Figur in der Welt des Hosts machen beim Host **keinen** Schaden (Grundsatz 3). Dafür muss der Host am Treffer erkennen, wer geschossen hat (Forschung E6).

### Ablauf: Gegner greift einen Spieler an

- **Host als Ziel:** läuft wie im normalen Spiel.
- **Mitspieler als Ziel:** Beim Host greift der Gegner die Partner-Figur an. Der Host erkennt den Schaden an der Partner-Figur, **verhindert ihn dort** und schickt `PLAYER_HIT`. Der Mitspieler zieht den Schaden in seinem Spiel bei sich selbst ab (seine Lebenspunkte gehören ihm). Die Puppe des Gegners zeigt beim Mitspieler den Angriff.
- **Packen (Zombie, Licker, Hund):** In der ersten Fassung wird ein Packen an der Partner-Figur beim Host in einen normalen Treffer umgewandelt (Schaden, kurzer Rückstoß). Echte Haltegriffe mit Befreien kommen in Stufe 2, weil dafür beide Spiele dieselbe Animation synchron spielen müssen.
- **Mitspieler in einer geliehenen Zone:** Sein eigenes Spiel macht alles selbst, wie im Solo-Spiel. Der Host erfährt nur Tode.

### Getrennte Bereiche

- Jeder sieht die Gegner seiner eigenen Zone. Gegner der Zone des anderen interessieren nicht (keine Puppen erzeugen).
- Ist der Mitspieler in einer Zone, die der Host noch geladen hat (Nachbarzone), bleibt der Host Besitzer.
- Tode aus geliehenen Zonen trägt der Host in seine Welt ein (Forschung E8). Lebenspunkte angeschossener Gegner werden bei der Rückgabe übernommen (`ENEMY_HANDOVER`).
- Der Spielstand des Hosts enthält dann die richtigen Tode. Beim nächsten Join oder nach einem Game Over passt die Welt wieder für beide.

### Mr. X

Mr. X ist ein einziger Gegner, der zwischen Zonen wandert. Er wird **immer vom Host besessen** (auch in geliehenen Zonen, dort ist er beim Mitspieler eine Puppe).

- **Zielwahl** (`enemy_net.Chaser`): Ziel ist der nähere erreichbare Spieler. Gewechselt wird erst, wenn der andere **mindestens 3 m näher** ist und das **2 s lang** bleibt. Ein Schuss (Lärm) zieht ihn sofort zum Schützen und hält ihn 8 s dort. Am Boden liegende Spieler sind keine Ziele. Ist das Ziel in keiner für ihn erreichbaren Zone, nimmt er sofort das andere. Die Zahlen sind Startwerte zum Ausprobieren.
- **Umsetzung:** Beim Host bekommt die KI von Mr. X als Ziel die Partner-Figur statt Leon/Claire, wenn der Mitspieler gewählt ist (Forschung E9). Ob die KI eine fremde Figur überhaupt als Ziel annimmt, ist offen.
- **Mitspieler in einer anderen Zone:** Mr. X folgt beim Host den Wegen des Spiels. Wechselt er in die Zone des Mitspielers, kommt er dort als Puppe an. Hat der Host diese Zone nicht geladen, kann seine KI dort nicht laufen. Erste Fassung: **Mr. X jagt nur Spieler in Zonen, die der Host geladen hat.** Ist der Mitspieler weit weg, hat er Ruhe vor Mr. X. So vom User entschieden (siehe „Entscheidungen des Users“).
- Mr. X in der Welt des Mitspielers: Erscheint er dort durch dessen eigenes Spiel (Story-Ereignis), wird er unterdrückt bzw. zur Puppe gemacht. Es gibt nur den Mr. X des Hosts.

### Im Spiel zu erforschen: Gegner (alles unbestätigt)

| Nr. | Frage | Wie prüfen |
|---|---|---|
| E1 | **Stabile Kennung:** Hat jeder Gegner eine Kennung, die beim Laden desselben Stands in beiden Spielen gleich ist? Kandidaten: Felder der Gegner-Komponente, Einträge in der Spielstand-Data des `EnemyManager` (Teil aus `GameSaveManagerDic`), GUID/Name des GameObjects, Spawn-Punkt in `GimmickSetManager`. | In derselben Zone zweimal vom selben Platz laden und die Liste vergleichen. |
| E2 | **Liste der lebenden Gegner:** Wie kommt man an alle aktiven Gegner einer Zone? `EnemyManager`-Felder/Methoden ansehen (Listen, `get_*`), Klassensuche `coopnet.find_types("Enemy")`. | Konsole: Liste ausgeben, mit Gegnern im Raum vergleichen. |
| E3 | **Art eines Gegners:** Gibt es eine Art-ID (Enum) oder nur den Prefab-/GameObject-Namen? Wie heißen Zombie, Licker, Hund, Mr. X, G? | Namen der GameObjects aus E2 ausgeben. |
| E4 | **Lebenspunkte:** Wo stehen die Lebenspunkte (aktuell, maximal) eines Gegners, und kann man sie setzen? Komponente mit „HitPoint“, „Life“ o. ä. suchen, nicht raten. | Gegner anschießen, Werte vorher/nachher vergleichen. |
| E5 | **Schadensverarbeitung:** Welche Methode zieht bei einem Treffer Schaden ab? (Hook auf Kandidaten aus `app.Collision.HitController` und der Gegner-Komponente, zählen, welche bei einem Schuss genau einmal feuert.) Kann ein Pre-Hook den Abzug verhindern (`sdk.PreHookResult.SKIP_ORIGINAL`), ohne dass die Treffer-Reaktion fehlt? | Schuss mit aktivem Hook, Lebenspunkte prüfen. |
| E6 | **Schütze erkennen:** Steht im Treffer (Argument der Methode aus E5) die Quelle? Unterscheidbar Leon gegen Partner-Figur? | Partner (Testbot) schießen lassen, Argumente ausgeben. |
| E7 | **KI abschalten:** Wie friert man die KI eines Gegners ein, ohne dass er verschwindet (Komponente deaktivieren, `set_Enabled`, Update überspringen per Hook)? Danach Position per `Transform.set_Position` und Animation per `changeMotion` setzbar? | Einen Zombie anhalten und per Konsole verschieben. |
| E8 | **Tod in die Welt eintragen:** Wie merkt sich das Spiel, dass ein Gegner tot ist (bleibt nach Zonenwechsel/Laden tot)? Kann man das für einen Gegner einer anderen Zone setzen? | Gegner töten, Spielstand-Data des `EnemyManager` vor und nach dem Tod vergleichen. |
| E9 | **Ziel der KI:** Wie wählt ein Gegner (Zombie, Mr. X) sein Ziel? Gibt es ein Ziel-Feld, oder nimmt er immer `PlayerManager.get_CurrentPlayer()`? Greift er die Partner-Figur heute schon von selbst an? | Testbot-Partner neben einen Zombie stellen, Host weit weg. |
| E10 | **Zonen laden:** Welche Zonen sind im Spiel geladen (nur die eigene oder auch Nachbarzonen)? Gibt es eine Liste? `EnemyManager.get_onFixedAreaChange()` beim Zonenwechsel mitschreiben. | Konsole beim Gehen durch Türen. |
| E11 | **Schaden am Spieler:** Welche Methode zieht dem Spieler Lebenspunkte ab (an `PlayerCondition` bzw. `HitController`)? Lässt sie sich für die Partner-Figur verhindern und beim eigenen Spieler mit einem eigenen Wert auslösen? | Zombie an Leon/Partner, Hook mitzählen. |
| E12 | **Packen:** Welche Zustände/Methoden laufen, wenn ein Zombie packt? Lässt sich das für die Partner-Figur in einen normalen Treffer umwandeln? | Stufe 2, nur ansehen. |
| E13 | **Gegner-Animation:** Haben Gegner dieselbe `via.motion.Motion` wie die Spieler (Ebenen, `get_MotionBankID`, `get_MotionID`)? Reicht Ebene 0 für ein glaubwürdiges Bild? | Wie bei `anim.lua`, an einem Zombie. |
| E14 | **Mr. X:** Wie heißt seine Klasse, wo steht sein Ziel und seine Zone, wie wechselt er die Zone? Reagiert er auf Geräusche (Ereignis/Methode)? | Erst wenn er im Spiel auftaucht (Polizeistation nach dem Hubschrauber). |

---

## Teil 2: Tod und Wiederbeleben

### Regeln (Design)

- Fallen die Lebenspunkte eines Spielers auf 0, **liegt er am Boden** statt zu sterben.
- Der andere kann ihn **innerhalb von 30 s** aufheben: hingehen (höchstens 1,5 m), Aktionstaste **3 s halten**. Danach steht er mit 30 % der Lebenspunkte wieder auf (Zustand „Danger“).
- Sterben beide oder läuft die Frist ab: **Game Over für beide**, weiter am letzten Speicherpunkt des Hosts.
- Alle Zahlen sind Startwerte (`revive.DEFAULTS`) und sollen später im Menü des Hosts einstellbar sein.

### Zustände

Der Host führt den Zustandsautomaten für beide Spieler (`re2r_coop/revive.lua`, getestet):

```
          Lebenspunkte 0                 Helfer hält Taste
 ALIVE ─────────────────────► DOWN ─────────────────────► REVIVING
   ▲                           │  ▲      losgelassen/zu weit  │
   │                           │  └───────────────────────────┤
   │        30 s abgelaufen    │                              │ 3 s gehalten
   │        oder beide DOWN    ▼                              │
   │                       GAME_OVER                          │
   └──────────────────────────────────────────────────────────┘
```

- Während REVIVING läuft die Frist nicht ab. Wird abgebrochen, nachdem sie abgelaufen wäre, gibt es 2 s Gnadenfrist.
- Fällt der Helfer selbst, bricht das Aufheben ab und es ist Game Over (beide liegen).
- Wer am Boden liegt, ist kein Ziel für Gegner (`Chaser` bekommt für ihn `nil`). Ob normale Gegner weiter auf ihn einschlagen, hängt von E9 ab. Am einfachsten: Schaden an Liegenden wird ignoriert.

### Ablauf und Nachrichten (Vorschlag)

Lebenspunkte und Zustand gehören dem jeweiligen Spieler. Der Host entscheidet nur den Übergang.

| ID | Name | Richtung | Kanal | Felder |
|---|---|---|---|---|
| 18 | `PLAYER_DOWN` | Spieler → Host (der Host meldet sich lokal selbst) | reliable | `reserved` B |
| 19 | `REVIVE_REQUEST` | Helfer → Host | reliable | `action` B (1 beginnen, 0 abbrechen), `distance` f |
| 20 | `REVIVE_EVENT` | Host → Mitspieler | reliable | `event` B (1 DOWNED, 2 REVIVE_BEGIN, 3 REVIVE_CANCEL, 4 REVIVED, 5 SOLO), `who` B (0 Host, 1 Mitspieler), `by` B, `time_left` f (Sekunden bis Frist bzw. bis aufgehoben) |
| 21 | `GAME_OVER` | Host → Mitspieler | reliable | `reason` B (1 beide am Boden, 2 Frist abgelaufen), `slot` I2 (Speicherplatz, den der Host lädt) |

Dazu in `PLAYER_STATE.flags` (keine neue Nachricht, nur Bedeutung festlegen): Bit 0 = am Boden, Bit 1 = wird aufgehoben, Bit 2 = Danger. Damit zeigt die Gegenseite auch bei verlorenen reliable-Paketen schnell den richtigen Zustand. Die Felder stehen im `revive.lua`-Ereignis schon bereit.

Ablauf beim Mitspieler:

1. Seine Lebenspunkte fallen auf 0. Ein Hook verhindert den normalen Tod (Forschung T1), hält die Lebenspunkte bei 1 und spielt die Liege-Animation. Er schickt `PLAYER_DOWN`.
2. Der Host ruft `revive:down("client", now)` und schickt die Ereignisse als `REVIVE_EVENT` zurück. Beide zeigen „Mitspieler am Boden: 30 s“ (imgui-Fenster genügt für den Anfang).
3. Der Host steht neben ihm und hält die Taste. Er ruft lokal `revive:begin(...)`. Ist der Mitspieler der Helfer, schickt dieser `REVIVE_REQUEST`.
4. Nach 3 s: `REVIVED`. Der Liegende setzt seine Lebenspunkte auf 30 % und steht auf.
5. Bei `GAME_OVER` lösen beide das Game Over aus (siehe unten).

Während des Liegens sendet der Liegende weiter `PLAYER_STATE` und `INPUT_STATE`, aber ohne Eingaben (Figur bleibt liegen). In der Welt des anderen spielt die Partner-Figur die Liege-Animation (Forschung T2).

### Game Over für beide

1. Der Host schickt `GAME_OVER` mit dem Platz, den er gleich lädt. Er selbst löst das normale Game Over des Spiels aus (Forschung T3), Fortsetzen lädt seinen letzten Speicherpunkt.
2. Der Mitspieler zeigt ebenfalls den Game-Over-Bildschirm, lädt aber **nicht** seinen eigenen Stand. Er wartet, bis der Host wieder im Spiel ist (`PLAYER_STATE` mit gültiger Zone), und tritt dann über den vorhandenen Join (`SAVE_REQUEST`, `savejoin.lua`) dem frischen Stand des Hosts bei.
3. Danach `revive:reset()` auf beiden Seiten.

Wichtig für Teil 3: Beim Neuladen bekäme der Mitspieler das Inventar des Hosts. Er muss sein **eigenes Inventar vom Zeitpunkt des Speicherns** zurückbekommen (siehe „Inventar bei Game Over und Speichern“).

### Randfälle

| Fall | Verhalten |
|---|---|
| Liegender verliert die Verbindung | Der andere spielt allein weiter (`SOLO`). Kein Game Over. |
| Helfer verliert die Verbindung, der andere liegt | Beim Liegenden normales Game Over seines Spiels (niemand kann helfen). Wenn er wieder verbindet, tritt er dem Stand des Hosts neu bei. |
| Host stürzt ab | Der Mitspieler ist allein in seiner Welt. Liegt er, Game Over. Sonst kann er weiterspielen, sein Fortschritt zählt aber nicht für den Host. |
| Zwischensequenz beginnt, während jemand liegt | Entschieden: Liegende stehen **automatisch auf** (mit 30 % der Lebenspunkte), die Frist ist während der Sequenz angehalten (so umgesetzt in `revive:cutscene`). Erkennung: Zone wird `Invalid` (bestätigt) bzw. ein besseres Signal aus T5. |
| Spieler fällt während einer Zwischensequenz | Die Frist zählt erst ab dem Ende der Sequenz. |
| Spieler in verschiedenen Zonen | Aufheben geht nur in Reichweite. Ist der Helfer zu weit weg, läuft die Frist eben ab. Eine Anzeige mit Entfernung hilft (gibt es schon in `ghost.lua`). |
| Tod durch Sofort-Tod-Angriff (z. B. Packen ohne Befreien, Sturz, Story) | Wie normaler Tod: Liegen statt Sterben, solange das Spiel das zulässt (T4). Sonst direkt Game Over für beide. |
| Beide fallen im selben Moment | `both_down`, Game Over. Nur ein Game Over (`revive` meldet es einmal). |

### Im Spiel zu erforschen: Tod (alles unbestätigt)

| Nr. | Frage | Wie prüfen |
|---|---|---|
| T1 | **Lebenspunkte des Spielers:** Wo stehen sie (aktuell, maximal), kann man sie setzen? Kandidat ist `PlayerCondition` (bestätigt als Zustandskomponente), Felder/Methoden mit „HitPoint“/„Vital“ suchen. Welche Methode löst den Tod aus, kann ein Hook ihn verhindern? | Konsole: Felder von `PlayerCondition` ausgeben, Schaden nehmen und vergleichen. |
| T2 | **Liege-Animation:** Gibt es eine, die man halten kann (Ende der Todesanimation einfrieren)? Welche Bank/Motion spielt beim Tod (`ANIM_STATE` mitschreiben)? Bleibt die Figur dabei steuerbar und von Gegnern unbehelligt? | Mit Testbot sterben lassen und die Ebenen aufzeichnen. |
| T3 | **Game Over auslösen:** Welche Klasse/Methode zeigt den Game-Over-Bildschirm (Kandidat: Zustand des `MainFlowManager`)? Was lädt „Fortsetzen“: letzten Speicherplatz, Checkpoint-Platz 21 (`RogueCheckPointDataNumber`) oder einen Autosave? | Absichtlich sterben, `MainFlowManager`-Zustand und `LoadGameDataIndex` mitschreiben. |
| T4 | **Sofort-Tod:** Welche Angriffe töten ohne Lebenspunkte-Abzug (Haltegriff-Tode, Story)? Laufen sie über dieselbe Methode wie T1? | Ansehen, wenn es vorkommt. |
| T5 | **Zwischensequenz erkennen:** Gibt es ein besseres Signal als `Invalid`-Zone (Ereignis/Flag in einem Manager)? | Konsole vor und während einer Sequenz. |
| T6 | **Danger-Zustand:** Wie setzt das Spiel den Zustand „Danger“ (Hinken), reicht das Setzen der Lebenspunkte? | Lebenspunkte per Konsole senken. |
| T7 | **Aufheben-Taste:** Welche `InputDefine.Kind` nimmt man (Aktion/Interagieren), ohne dass die Figur gleichzeitig etwas anderes tut (Tür öffnen, Item nehmen)? | Konsole: Knopfmaske beim Drücken ausgeben. |

---

## Teil 3: Items

### Regeln (Design)

- Jeder hat **sein eigenes Inventar und seine eigene Munition**.
- **Schlüssel- und Story-Items bekommen beide**, damit niemand festhängt.
- Die Welt des Hosts ist maßgeblich.

### Welche Items sind Schlüssel-Items?

- **Vorrang hat das Spiel selbst:** Hat ein Item im Spiel eine Kategorie bzw. Eigenschaft „Schlüssel/wichtig“ (Forschung I2), nehmen wir die.
- **Ergänzend eine Liste** im Mod (`re2r_coop/items.lua`, später), mit der wir Fälle von Hand korrigieren können.
- **Zu Schlüssel-Items zählen:** Schlüssel, Medaillons, Schachfiguren, Stecker, Karten (Pläne), Dokumente/Akten, Teile für Rätsel, Story-Gegenstände und Erweiterungen, die man nur einmal findet (z. B. Hüfttaschen, die das Inventar vergrößern). Waffen gelten **nicht** als Schlüssel-Items (jeder findet seine eigenen, Leon und Claire haben ohnehin andere).
- **Nicht dazu:** Munition, Heilkräuter, Sprays, Schießpulver, Granaten, Messer, Tinte.

### Weltitems: wer darf aufheben, verschwinden sie bei beiden?

| Art | Wer darf | Was passiert |
|---|---|---|
| Verbrauchsitems (Munition, Kräuter, Pulver …) | **wer zuerst kommt** | Das Item verschwindet bei beiden. Nur der Finder bekommt es. Das entspricht der Menge des Solo-Spiels (Schwierigkeit „wie Solo“). |
| Schlüssel- und Story-Items | einer hebt auf | Verschwindet bei beiden. **Beide** bekommen es ins Inventar. |
| Weltitems in geliehenen Zonen | der Mitspieler | Wie oben, der Host trägt das Aufheben in seine Welt ein. |

Gleichzeitiges Aufheben desselben Items: Der Mitspieler hebt **sofort** auf (keine Wartezeit), meldet es und der Host bestätigt. Hat der Host es im selben Moment selbst genommen, behalten beide ihr Exemplar (Grundsatz 4). Das ist selten und billiger als ein Zurückdrehen.

### Ablauf: Aufheben

1. Ein Spieler hebt ein Weltitem auf. Ein Hook auf die Aufheben-Methode (Forschung I3) liest Kennung des Weltitems (`item_key`), Item-ID und Anzahl.
2. **Mitspieler hebt auf:** Er schickt `ITEM_PICKUP`. Der Host entfernt das Weltitem in seiner Welt (Forschung I4) und schickt `ITEM_TAKEN` als Bestätigung.
3. **Host hebt auf:** Er schickt `ITEM_TAKEN`. Der Mitspieler entfernt das Weltitem in seiner Welt.
4. **Schlüssel-Item:** Zusätzlich `ITEM_GRANT` an den anderen. Er bekommt das Item ins Inventar (Forschung I5). Ist sein Inventar voll, landet es in seiner Itemkiste, und er bekommt einen Hinweis.
5. **Schlüssel-Item verbraucht** (Tür geöffnet, Rätsel gelöst, „wird nicht mehr benötigt“): Das Spiel wirft es selbst weg, sobald die zugehörige Story-Stelle erledigt ist. Das funktioniert beim anderen erst, wenn Türen und Story-Flags abgeglichen sind (Meilenstein 4). Bis dahin schickt der Benutzer `ITEM_DISCARD`, und der andere entfernt das Item ebenfalls.

### Nachrichten (Vorschlag)

| ID | Name | Richtung | Kanal | Felder |
|---|---|---|---|---|
| 22 | `ITEM_PICKUP` | Mitspieler → Host | reliable | `item_key` s1 (Kennung des Weltitems), `item_id` I4, `count` I2, `zone` I2 |
| 23 | `ITEM_TAKEN` | Host → Mitspieler | reliable | `item_key` s1, `by` B (0 Host, 1 Mitspieler), `zone` I2 |
| 24 | `ITEM_GRANT` | Finder → anderer | reliable | `item_id` I4, `count` I2, `extra` I4 (spielabhängig, z. B. Zustand/Ladung, Forschung I1) |
| 25 | `ITEM_DISCARD` | Benutzer → anderer | reliable | `item_id` I4 |

### Itemkiste

Jeder hat seine eigene Itemkiste. Das passt zum eigenen Inventar und braucht keinen Abgleich. Schlüssel-Items in der Kiste des einen helfen dem anderen nicht. Deshalb bekommen beide ihr eigenes Exemplar.

### Inventar bei Join, Game Over und Speichern

Hier gibt es eine Spannung zum aktuellen Join-Fehler „Der Beitretende behält das Inventar seines eigenen Spielstands“ (`RE2-uebergabe.md`):

- **Beim ersten Beitreten** (entschieden): Waffen passend zur eigenen Figur, Munition, Heilung und Schlüssel-Items vom Host, eigene Itemkiste **leer**. Danach laufen die Inventare auseinander.
- **Beim erneuten Beitreten** (Verbindungsabbruch, Game Over) würde der Join das Inventar wieder mit dem des Hosts überschreiben. Das widerspricht „eigenes Inventar“. Vorschlag: Der Mitspieler speichert sein eigenes Inventar und seine Itemkiste **lokal** (die Teile `InventoryManager`, `ItemLockerManager`, ggf. `EquipmentManager` aus `capture_live`), und zwar jedes Mal, wenn der Host speichert. Dafür schickt der Host eine kurze Nachricht `HOST_SAVED` (ID 26, reliable, `slot` I2, `session_id` I4). Beim erneuten Beitreten zum selben Host-Spielstand ersetzt der Mitspieler diese Teile durch seine lokale Kopie, bevor `apply_to_list` sie einspielt.
- Schlüssel-Items, die der Host seit dem Speichern bekommen hat, sind nach einem Game Over bei beiden weg (beide sind auf demselben Speicherstand), das passt.
- Die Figur (Leon/Claire) des Mitspielers ist laut Design die andere Hauptfigur. Ihre Waffen sind andere als die des Hosts. Für die Startausstattung beim ersten Beitreten heißt das: Schlüssel-Items und Verbrauchsitems vom Host übernehmen, Waffen durch die passenden der eigenen Figur ersetzen (Forschung I6).

### Im Spiel zu erforschen: Items (alles unbestätigt)

| Nr. | Frage | Wie prüfen |
|---|---|---|
| I1 | **Inventar lesen:** Wie sieht ein Eintrag im `InventoryManager` aus (Item-ID, Anzahl, Waffe, Munition, Zustand)? Welches Enum hat die Item-ID? Bekannt ist nur der Typname `app.ropeway.gamemastering.InventoryManager.ItemData` aus den Testdaten von `re2r_savejoin_test.lua`, das ist kein bestätigter Spieltyp. | Konsole: Inventar des Spielers ausgeben, mit dem Bildschirm vergleichen. |
| I2 | **Schlüssel-Kategorie:** Hat jedes Item eine Kategorie bzw. Eigenschaft (Schlüssel, Wichtig, Waffe, Munition, Heilung)? Wo steht die Tabelle (Item-Daten-Liste in einem Manager oder einer UserData)? | Klassensuche „ItemDefine“, „ItemCategory“, „KeyItem“ per `coopnet.find_types`, nicht raten. |
| I3 | **Aufheben erkennen:** Welche Methode läuft beim Aufheben eines Weltitems (am Weltitem/Gimmick oder am `InventoryManager`)? Welche Argumente hat sie (Item-ID, Anzahl, Weltobjekt)? | Hooks auf Kandidaten, Item aufheben, mitzählen. |
| I4 | **Weltitem entfernen:** Wie markiert das Spiel ein Weltitem als aufgehoben (Flag im `ItemManager` bzw. `GimmickSetManager`, Spielstand-Teil)? Kann man es für ein Item setzen, das man nicht selbst aufgehoben hat, und verschwindet es dann sofort (oder erst nach dem Neuladen der Zone)? | Spielstand-Teil `ItemManager` vor/nach dem Aufheben vergleichen (`capture_live` hilft). |
| I5 | **Item ins Inventar geben:** Gibt es eine Methode wie „Item hinzufügen“ am `InventoryManager`, die auch die Anzeige aktualisiert? Was passiert bei vollem Inventar? Wie legt man ein Item in die Itemkiste (`ItemLockerManager`)? | Konsole: ein Kraut hinzufügen. |
| I6 | **Waffen pro Figur:** Lassen sich Leons Waffen Claire geben (und umgekehrt)? Was passiert, wenn das Inventar des Hosts beim Join an die andere Figur geht? | Nach dem Join-Fix (Claire als Mitspieler) prüfen. |
| I7 | **Weltitem-Kennung:** Hat jedes Weltitem eine stabile Kennung, die in beiden Spielen gleich ist (wie E1)? | In derselben Zone zweimal vom selben Platz laden und vergleichen. |
| I8 | **„Wird nicht mehr benötigt“:** Wann und wo wirft das Spiel ein Schlüssel-Item weg (Methode, Flag)? | Schlüssel benutzen, bis die Meldung kommt. |
| I9 | **Speichern erkennen:** Welche Methode läuft, wenn der Host an der Schreibmaschine speichert (für `HOST_SAVED`)? Auch beim automatischen Speichern? | Hook auf `SaveDataManager`-Methoden, speichern. |

---

## Vorschlag fürs Protokoll (zur Abstimmung mit dem Projektleiter)

- Neue Nachrichten 10 bis 26 wie oben. `protocol.encode` kann keine Listen, deshalb nutzen `ENEMY_STATE` und `ENEMY_HANDOVER` ein `s2`-Feld `data` mit eigenem Format (`enemy_net.pack_states`). Das ist in `re2r_coop` gebaut und muss nicht in `shared/`.
- Bedeutung von `PLAYER_STATE.flags` festlegen (RE2): Bit 0 am Boden, Bit 1 wird aufgehoben, Bit 2 Danger. Das ändert das Format nicht.
- **`protocol.VERSION` auf 4 erhöhen**, wenn die ersten dieser Nachrichten kommen. Alte Stände würden die neuen IDs zwar ignorieren, aber dann schießt einer auf Gegner, die beim anderen nicht sterben. Das ist schlimmer als eine klare Ablehnung beim Verbinden.
- Reihenfolge der Umsetzung: (1) E2, E3, E7, E13 → Gegner als Puppen beim Mitspieler, nur Anzeige. (2) E4, E5, E6 → Treffer und Tod. (3) T1, T2, T3 → Wiederbeleben mit `revive.lua`. (4) I1, I3, I4, I5 → Items. (5) E8, E10 → getrennte Zonen. (6) E9, E14 → Mr. X.

## Schon gebaut (ohne Spiel, getestet)

| Datei | Inhalt |
|---|---|
| `games/re2r/coop/autorun/re2r_coop/revive.lua` | Zustandsautomat Tod und Wiederbeleben (Host entscheidet): Liegen, Aufheben, Abbruch, Frist, Zwischensequenz, Verbindungsabbruch, Game Over |
| `games/re2r/coop/autorun/re2r_coop/enemy_net.lua` | Packen/Entpacken vieler Gegner (26 Bytes je Gegner), Besitzer pro Zone, Zielwahl mit Hysterese für Mr. X |
| `tests/lua/re2r_coop_logic_test.lua` | Tests dazu (ctest `lua_re2r_coop_logic`) |

Beide Module werden noch von nichts geladen. Am Spielverhalten ändert sich nichts.

## Entscheidungen des Users (4. November 2026)

1. **Mr. X** jagt in der ersten Fassung nur in Zonen, die der Host geladen hat. Ein weit entfernter Mitspieler hat Ruhe vor ihm.
2. **Verbrauchsitems:** wer zuerst kommt. Sie verschwinden bei beiden.
3. **Zwischensequenz, während jemand liegt:** Der Liegende steht automatisch auf, mit 30 % der Lebenspunkte.
4. **Startwerte** 30 s Frist und 3 s Taste halten bleiben vorerst. Feinschliff nach dem ersten Test im Spiel.
5. **Erstes Beitreten:** Waffen passend zur eigenen Figur, Munition, Heilung und Schlüssel-Items vom Host, eigene Itemkiste leer.
