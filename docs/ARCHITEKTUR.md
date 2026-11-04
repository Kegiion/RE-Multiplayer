# Architektur

## Überblick

```
┌──────────────────────── Resident Evil 2 (re2.exe) ─────────────────────────┐
│                                                                            │
│  REFramework (dinput8.dll)                                                 │
│   ├── Lua: reframework/autorun/                                            │
│   │    ├── re2r_coop.lua         Einstieg, Menü, Ablauf pro Frame          │
│   │    ├── re2r_coop/game.lua    ◄── kennt RE2-Klassen (Adapter)           │
│   │    ├── re2r_coop/ghost.lua   Mitspieler anzeigen                       │
│   │    ├── re2r_coop/diag.lua    Diagnose-Datei schreiben                  │
│   │    └── remultiplayer_coop/          gemeinsam für alle Spiele                 │
│   │         ├── protocol.lua     Nachrichtenformat                         │
│   │         └── session.lua      Handshake, Peers, Verteilung              │
│   │                 │                                                      │
│   │                 ▼  globale Tabelle `coopnet`                           │
│   └── Plugin: reframework/plugins/remultiplayer_coopnet.dll                       │
│        └── netcore (C++) ── eigener Netzwerk-Thread ── ENet (UDP)          │
└────────────────────────────────────────┬───────────────────────────────────┘
                                         │ Internet / LAN / VPN
                                         ▼
                                Mitspieler (gleiches Setup)
```

## Warum so?

**REFramework als Basis.** Es gibt für alle RE-Engine-Spiele (RE2/3/4 Remake, RE7, Village, RE9) Zugriff auf jede Spielklasse per Reflection, ohne dass wir Speicheradressen von Hand suchen müssen. Das spart uns Monate an Reverse Engineering.

**C++ nur fürs Netzwerk, Spiellogik in Lua.**
- Lua kann man im Spiel per *Reset Scripts* neu laden, ohne das Spiel neu zu starten. Für uns im Duo ist das der schnellste Weg: Ich ändere ein Skript, du lädst es neu und probierst es aus.
- Lua hat in REFramework keine Netzwerkfunktionen, deshalb liefert das Plugin sie nach (`coopnet`).
- Das Plugin ist **spielunabhängig**. Für RE3, RE4 usw. brauchen wir dieselbe DLL, nur neue Lua-Skripte.

**Netzwerk in eigenem Thread.** Während Ladebildschirmen ruft das Spiel teilweise keine Skripte auf. Würde das Netzwerk nur pro Frame laufen, gäbe es dort Verbindungsabbrüche.

**Die Verbindung überlebt „Reset Scripts“.** Die Session lebt im Plugin. Nach einem Neuladen schickt die neue Lua-Session ein HELLO mit `want_reply` und ist sofort wieder synchron.

**ENet (UDP)** bietet zwei Kanäle:
- *reliable*: garantiert und in Reihenfolge, für Ereignisse (Tür geöffnet, Item aufgehoben, Treffer)
- *unreliable*: nur das Neueste zählt, für Positionen (20× pro Sekunde)

**Lua-Version.** Das Plugin enthält Lua **5.4.3 in exakt der Fassung aus REFramework** (`third_party/lua`). Es arbeitet direkt auf REFrameworks `lua_State`, deshalb dürfen die Versionen nicht abweichen. Nicht einfach aktualisieren!

## Host-Modell

Ein Spieler ist **Host**, der andere **Client**. Für den Story-Koop wird der Host die „Wahrheit“ über die Welt besitzen: Gegner, Türen, Items und Story-Fortschritt. Der Client meldet seine eigenen Aktionen, der Host entscheidet und verteilt das Ergebnis. Bei zwei Spielern ist das die einfachste Lösung, die konsistent bleibt.

## Protokoll

Definiert in `shared/re-engine/lua/remultiplayer_coop/protocol.lua`. Jede Nachricht besteht aus einem Byte Typ plus den Feldern per `string.pack`. Wenn sich eine Nachricht ändert, wird `protocol.VERSION` erhöht. Spieler mit unterschiedlicher Version werden beim Handshake erkannt und abgelehnt.

| ID | Nachricht | Kanal | Inhalt |
|---|---|---|---|
| 1 | HELLO | reliable | Protokollversion, Spiel, Mod-Version, Name |
| 2 | PLAYER_STATE | unreliable | seq, Bereich, Position, Rotation, Figur, Flags |
| 3 | CHAT | reliable | Text (zum Testen) |
| 4 | ANIM_BANKS | reliable | Nummer des Satzes, Pfade der Animationsdateien (Haupt-Bank, bis zu 4 weitere). Bei Änderung und alle 3 s |
| 5 | ANIM_STATE | unreliable | seq, Bank-Satz, Ebenen 0 bis 3 (Bank, Animation, Bild, Überblendung), 12 Steuer-Variablen, Schalter-Bitfeld |
| 6–8 | SAVE_REQUEST, SAVE_BEGIN, SAVE_CHUNK | reliable | Spielstand des Hosts für den Join |
| 9 | INPUT_STATE | unreliable | Eingaben (Knopfmaske, Sticks, Kamera), steuert die Partner-Figur |
| 10–26 | ENEMY_*, PLAYER_HIT, PLAYER_DOWN, REVIVE_*, GAME_OVER, ITEM_*, HOST_SAVED | gemischt | Gegner, Tod und Items (RE2), **noch nicht aktiv**, siehe `docs/re2r-konzept-gegner-tod-items.md` |

## Übersetzung (i18n)

Alle sichtbaren Texte der RE-Engine-Mods laufen über `shared/re-engine/lua/remultiplayer_coop/i18n.lua`:

- Texte über Schlüssel: `t("conn.host")`, Platzhalter in geschweiften Klammern: `t("status.ping", { ms = 40 })` → „Ping 40 ms“.
- Sprachdateien sind Lua-Tabellen. Gemeinsame Texte (Sitzung, Verbindung, Status, Chat) liegen in `remultiplayer_coop/lang/`, Texte einer Mod in `<mod>/lang/` (RE2: `re2r_coop/lang/`, geladen über `re2r_coop/text.lua`).
- Fehlt ein Schlüssel in der gewählten Sprache, kommt Englisch, fehlt er auch dort, der Schlüssel selbst.
- Sprachwahl im Mod-Menü (Einfg-Menü und Titelmenü „Multiplayer“): Automatisch (Spielsprache), Deutsch, English. Gespeichert in der Mod-Konfiguration (`language`). Die Spielsprache liefert der Adapter `game.get_game_language()`. In RE2 liest er `via.gui.GUISystem.get_MessageLanguage`: Wert 4 = Deutsch ist im Spiel bestätigt, alle anderen Werte sind noch **unbestätigt** und ergeben vorerst Englisch.
- **Neue Sprache:** `<code>.lua` neben `de.lua`/`en.lua` anlegen (gemeinsam und pro Mod) und in `languages.lua` eintragen. Der Test `lua_i18n` prüft, dass jede Sprachdatei dieselben Schlüssel hat wie Englisch, und dass jeder Schlüssel, der im Code als Zeichenkette vorkommt (`"<gruppe>.<name>"`, Gruppe aus den Sprachdateien), in Englisch existiert. Er liest dafür die Hauptdatei und alle per `require` geladenen Module; Module, die noch nicht geladen werden, stehen als Einstieg im Test.
- Gespeicherte Meldungen (z. B. Fehler der Mitspieler-Figur, `titlemenu.error`, Hinweise von `items_net`) speichern den Schlüssel plus Werte und werden erst beim Anzeigen übersetzt, damit ein Sprachwechsel sofort wirkt. Rohe Lua-Fehlermeldungen laufen unverändert durch `t()` (unbekannter Schlüssel = Text selbst).
- Interne Fehler in `error(...)`/`assert(...)` (z. B. `anim`, `weapon`, `serial`, `transfer`, `game_adapter`) bleiben deutsch und unübersetzt: Sie landen nur im Log bzw. in den Debug-Infos und sind für die Fehlersuche gedacht.
- imgui-Texte in den Sprachdateien wie bisher ohne Umlaute (ae, oe, ue, ss). Texte im Spielmenü (`tm.*`, Spielschrift) dürfen Umlaute haben.

## Neues Spiel hinzufügen (RE-Engine)

1. `games/<spiel>/coop/autorun/` anlegen und `game.lua` mit derselben Schnittstelle wie `re2r_coop/game.lua` schreiben.
2. Einstiegsskript kopieren und anpassen (Spiel-ID!).
3. In `CMakeLists.txt` eine neue Install-Komponente ergänzen.
4. Texte über `remultiplayer_coop.i18n` und eigene Sprachdateien `<mod>/lang/` (siehe „Übersetzung“).

Für Spiele ohne RE Engine (MT Framework: RE1 HD, RE5, RE6, Revelations) bleibt `netcore` gleich. Dort brauchen wir statt REFramework einen eigenen Weg ins Spiel. Für RE0 HD gibt es den schon (Loader `dinput8.dll` + Runtime), er dient als Vorlage. Originale, die ein Remake haben (z. B. RE4 2005), machen wir nicht (siehe `docs/ROADMAP.md`).
