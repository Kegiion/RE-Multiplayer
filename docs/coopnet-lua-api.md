# coopnet: Lua-API des Plugins

Das Plugin `remods_coopnet.dll` stellt in jedem REFramework-Lua-State die globale Tabelle `coopnet` bereit. Normalerweise benutzt man sie nicht direkt, sondern über `remods_coop.session`. Die Referenz hilft beim Debuggen.

| Funktion | Rückgabe | Beschreibung |
|---|---|---|
| `coopnet.version()` | string | Plugin-Version, z. B. `"0.1.0"` |
| `coopnet.time()` | number | Monotone Zeit in Sekunden (hochauflösend) |
| `coopnet.host(port [, max_peers=3])` | `true` oder `nil, fehler` | Host auf UDP-Port starten |
| `coopnet.connect(adresse, port)` | `true` oder `nil, fehler` | Als Client verbinden. Das Ergebnis kommt als Event. |
| `coopnet.disconnect()` | – | Verbindung bzw. Host beenden |
| `coopnet.send(daten, reliable [, peer=0])` | bool | Binärstring senden. `peer = 0` heißt an alle. |
| `coopnet.poll()` | Liste von Events | Alle neuen Events seit dem letzten Aufruf |
| `coopnet.status()` | Tabelle | Modus, Fehler, Peers, Statistik |

**Events** aus `poll()`:

```lua
{ type = "connect",    peer = 1 }
{ type = "disconnect", peer = 1 }   -- peer = 0: Verbindungsaufbau fehlgeschlagen
{ type = "message",    peer = 1, data = "...", reliable = true }
```

**Status** aus `status()`:

```lua
{
  mode  = "idle" | "hosting" | "connecting" | "connected",
  error = "letzte Fehlermeldung",          -- nur wenn vorhanden
  peers = { { id = 1, address = "1.2.3.4:27350", rtt = 23 } },
  stats = { messages_sent =, messages_received =, bytes_sent =, bytes_received = },
}
```

Die Session lebt im Plugin weiter, wenn REFramework die Skripte neu lädt. Eine bestehende Verbindung bleibt also erhalten.
