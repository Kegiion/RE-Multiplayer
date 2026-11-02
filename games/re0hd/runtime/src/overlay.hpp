// ImGui-Overlay im Spiel: Menue (Taste Einfg oder F8), Startmeldung, Log.
#pragma once

struct IDirect3DDevice9;

namespace remods::overlay {

void on_present(IDirect3DDevice9* device);
void on_before_reset();
void on_after_reset(bool ok);

}  // namespace remods::overlay
