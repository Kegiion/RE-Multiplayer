# Fremdbibliotheken

Alle Bibliotheken liegen als Quellcode im Repo, damit der Build ohne Internet funktioniert.

| Ordner | Was | Version / Herkunft | Lizenz |
|---|---|---|---|
| `enet/` | Zuverlässiges UDP-Netzwerk | ENet 1.3.18 (github.com/lsalzman/enet) | MIT (`enet/LICENSE`) |
| `lua/` | Lua-Interpreter | Lua 5.4.3, **exakt die Kopie aus REFramework** (`dependencies/lua`, Stand Commit 1813bf3) | MIT (siehe Lua-Copyright in `lua/src/lua.h`) |
| `reframework/` | Plugin-API-Header | REFramework, `include/reframework/` (Commit 1813bf3, Plugin-API 1.15.0) | MIT (`reframework/LICENSE`) |
| `imgui/` | Menü im Spiel (nur RE0-Runtime) | Dear ImGui 1.93.0 (github.com/ocornut/imgui, Tag v1.93.0, Commit c1aaac6). Nur Kern-Dateien und die Backends `dx9` und `win32` | MIT (`imgui/LICENSE.txt`) |

**Wichtig zu Lua:** Unser Plugin arbeitet direkt auf REFrameworks `lua_State`. Die Lua-Version muss deshalb exakt zu der in REFramework eingebauten passen. Wenn REFramework Lua aktualisiert, müssen wir mitziehen.
