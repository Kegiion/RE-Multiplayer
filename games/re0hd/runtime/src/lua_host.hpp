// Lua-Umgebung der RE0-Runtime.
//
// Bildet einen kleinen Teil der REFramework-API nach, damit die gemeinsame
// Lua-Bibliothek (remultiplayer_coop) und der Stil der RE2-Skripte auch hier passen:
//   re.on_frame(fn), re.on_draw_ui(fn)
//   imgui.*  (text, button, checkbox, input_text, tree_node, ...)
//   log.info/warn/error
//   json.load_file/dump_file      (aus remultiplayer/lib/json.lua, relativ zu remultiplayer/data/)
//   coopnet.*                     (Netzwerk, wie im RE2-Plugin)
// Dazu kommen RE0-eigene Funktionen:
//   mem.*     Speicher lesen/schreiben (fuer die Forschung mit Cheat Engine)
//   remultiplayer.*  Version, Pfade, Infos zur exe
//
// Alles laeuft im Render-Thread des Spiels (aus dem Present-Hook).
#pragma once

#include <string>
#include <vector>

namespace remultiplayer::lua_host {

// Pro Frame. Laedt bei Bedarf (erster Frame oder "Skripte neu laden") alle
// Skripte neu und ruft dann alle re.on_frame-Funktionen auf.
// imgui_active: true, wenn gerade ein ImGui-Frame laeuft (zwischen NewFrame
// und Render). Sonst tun die imgui.*-Funktionen nichts.
void run_frame(bool imgui_active);

// Im Menuefenster: ruft alle re.on_draw_ui-Funktionen auf.
void draw_ui();

// Beim naechsten Frame alle Skripte neu laden. Die Netzwerk-Session bleibt.
void request_reload();

// Fehler der Skripte (Laden und Laufzeit, jeder Text nur einmal).
std::vector<std::string> errors();

// Anzahl geladener Skripte aus remultiplayer/autorun/.
int script_count();

}  // namespace remultiplayer::lua_host
