// ImGui-Overlay im Spiel: Menue (Taste Einfg oder F8), Startmeldung, Log.
#pragma once

struct IDirect3DDevice9;

namespace remultiplayer::overlay {

void on_present(IDirect3DDevice9* device);
void on_before_reset();

// Fuer Lua: Mauszeiger in diesem Frame zeigen (eigene Fenster ausserhalb des Menues)
void request_cursor();
bool menu_open();
float scale();  // Skalierung der Oberflaeche (720p = 1.0)
void on_after_reset(bool ok);

}  // namespace remultiplayer::overlay
