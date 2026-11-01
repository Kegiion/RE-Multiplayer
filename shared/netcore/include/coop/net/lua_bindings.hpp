// Stellt eine Session als globale Lua-Tabelle `coopnet` bereit.
//
// Die Lua-Seite (Spiel-Logik) bleibt dadurch unabhaengig von C++ und kann
// in REFramework per "Reset Scripts" neu geladen werden, ohne dass die
// Netzwerkverbindung abreisst - die Session lebt im Plugin weiter.
//
// API (siehe docs/coopnet-lua-api.md):
//   coopnet.version()                       -> string
//   coopnet.time()                          -> Sekunden (monoton, mit Nachkommastellen)
//   coopnet.host(port [, max_peers])        -> true | nil, fehler
//   coopnet.connect(adresse, port)          -> true | nil, fehler
//   coopnet.disconnect()
//   coopnet.send(daten, reliable [, peer])  -> bool
//   coopnet.poll()                          -> { {type=, peer=, data=, reliable=}, ... }
//   coopnet.status()                        -> { mode=, error=, peers={...}, stats={...} }
#pragma once

struct lua_State;

namespace coop::net {

class Session;

constexpr const char* kCoopnetVersion = "0.1.0";

// Registriert die API als globale Tabelle (Standardname `coopnet`) im
// Lua-State. Die Session muss laenger leben als der Lua-State.
void register_lua_api(lua_State* L, Session& session, const char* global_name = "coopnet");

}  // namespace coop::net
