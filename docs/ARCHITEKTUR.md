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

## Neues Spiel hinzufügen (RE-Engine)

1. `games/<spiel>/coop/autorun/` anlegen und `game.lua` mit derselben Schnittstelle wie `re2r_coop/game.lua` schreiben.
2. Einstiegsskript kopieren und anpassen (Spiel-ID!).
3. In `CMakeLists.txt` eine neue Install-Komponente ergänzen.

Für Spiele ohne RE Engine (RE4 2005, RE5/6, Klassiker) bleibt `netcore` gleich. Dort brauchen wir statt REFramework einen eigenen Weg ins Spiel, z. B. eine DLL mit Hooks.
