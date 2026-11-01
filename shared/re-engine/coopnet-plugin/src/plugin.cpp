// coopnet - REFramework-Plugin fuer alle RE-Engine-Spiele.
//
// Das Plugin enthaelt nur den Netzwerk-Teil und ist spielunabhaengig. Es
// stellt jedem REFramework-Lua-State die Tabelle `coopnet` bereit. Die
// spielspezifische Logik (Spieler auslesen, Gegner synchronisieren, ...)
// steckt in den Lua-Skripten unter games/<spiel>/.
//
// Installation: remods_coopnet.dll nach <Spiel>/reframework/plugins/ kopieren.

#include <windows.h>

#include <reframework/API.h>

#include "coop/net/lua_bindings.hpp"
#include "coop/net/session.hpp"

namespace {

// Absichtlich nie freigegeben: Ein Thread-Join waehrend des DLL-Entladens
// (Loader-Lock) kann das Spiel beim Beenden haengen lassen.
coop::net::Session* g_session = nullptr;

void on_lua_state_created(lua_State* L) {
    if (g_session == nullptr) {
        g_session = new coop::net::Session{};
    }
    coop::net::register_lua_api(L, *g_session);
    OutputDebugStringA("[coopnet] Lua-API registriert\n");
}

void on_lua_state_destroyed(lua_State*) {
    // Die Session bleibt bestehen: Nach "Reset Scripts" ist die Verbindung
    // weiterhin da und die Skripte machen einfach weiter.
}

}  // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    // Wir nutzen nur on_lua_state_created/destroyed, die es seit API 1.0 gibt.
    // Damit laeuft das Plugin auch mit aelteren REFramework-Versionen.
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = 0;
    version->patch = 0;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    const auto* functions = param->functions;
    functions->on_lua_state_created(on_lua_state_created);
    functions->on_lua_state_destroyed(on_lua_state_destroyed);
    OutputDebugStringA("[coopnet] Plugin geladen\n");
    return true;
}
