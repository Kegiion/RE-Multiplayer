// Hook auf DirectInput 8 (IDirectInputDevice8::GetDeviceState/GetDeviceData).
//
// RE0 liest Tastatur und Maus ueber DirectInput, nicht ueber Fenster-
// Nachrichten. Damit
//   - bekommt das Spiel keine Eingaben, solange unser Menue offen ist, und
//   - koennen wir Tasten einspeisen (spaeter: Partner-Steuerung durch den
//     Mitspieler ueber das Netzwerk).
//
// Lua-API (globale Tabelle `input`):
//   input.set_key(dik, gedrueckt)   Taste einspeisen (DIK_-Code, z. B. 0xC8 = Pfeil hoch)
//   input.clear()                   alle eingespeisten Tasten loslassen
//   input.key_down(dik)             ist die Taste auf der echten Tastatur gedrueckt?
//   input.stats()                   Zaehler: welche DirectInput-Funktionen das Spiel nutzt
#pragma once

struct lua_State;

namespace remods::input {

bool install();

// Solange true, sieht das Spiel keine Tastatur- und Mauseingaben.
void set_blocked(bool blocked);

void register_lua(lua_State* L);

}  // namespace remods::input
