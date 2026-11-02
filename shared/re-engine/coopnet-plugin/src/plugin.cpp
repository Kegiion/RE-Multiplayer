// coopnet - REFramework-Plugin fuer alle RE-Engine-Spiele.
//
// Das Plugin enthaelt nur den Netzwerk-Teil und ist spielunabhaengig. Es
// stellt jedem REFramework-Lua-State die Tabelle `coopnet` bereit. Die
// spielspezifische Logik (Spieler auslesen, Gegner synchronisieren, ...)
// steckt in den Lua-Skripten unter games/<spiel>/.
//
// Installation: remultiplayer_coopnet.dll nach <Spiel>/reframework/plugins/ kopieren.

#include <windows.h>

#include <reframework/API.h>

#include <lua.hpp>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "coop/net/lua_bindings.hpp"
#include "coop/net/session.hpp"

namespace {

// Absichtlich nie freigegeben: Ein Thread-Join waehrend des DLL-Entladens
// (Loader-Lock) kann das Spiel beim Beenden haengen lassen.
coop::net::Session* g_session = nullptr;

const REFrameworkSDKData* g_sdk = nullptr;

// ---- Forschungs-Funktionen ------------------------------------------------
// Lua in REFramework kann nicht alle Klassen des Spiels auflisten. Fuer die
// Analyse (Diagnose-Datei) holen wir das hier ueber die C-API nach.

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::string type_full_name(REFrameworkTypeDefinitionHandle t) {
    if (t == nullptr) {
        return {};
    }
    char buffer[512]{};
    unsigned int len = 0;
    if (g_sdk->type_definition->get_full_name(t, buffer, sizeof(buffer), &len) != REFRAMEWORK_ERROR_NONE) {
        return {};
    }
    return std::string{buffer, std::min<size_t>(len, sizeof(buffer))}.c_str();
}

// coopnet.find_types(text [, limit=500]) -> { "app.ropeway.Xyz", ... }
// Alle Klassen, deren voller Name `text` enthaelt (Gross/klein egal).
int l_find_types(lua_State* L) {
    const char* needle_c = luaL_checkstring(L, 1);
    const lua_Integer limit = luaL_optinteger(L, 2, 500);

    std::vector<std::string> found;
    {
        const std::string needle = lower(needle_c);
        const auto tdb = g_sdk->functions->get_tdb();
        const unsigned int count = g_sdk->tdb->get_num_types(tdb);
        for (unsigned int i = 0; i < count && static_cast<lua_Integer>(found.size()) < limit; ++i) {
            auto name = type_full_name(g_sdk->tdb->get_type(tdb, i));
            if (!name.empty() && lower(name).find(needle) != std::string::npos) {
                found.push_back(std::move(name));
            }
        }
    }

    lua_createtable(L, static_cast<int>(found.size()), 0);
    for (size_t i = 0; i < found.size(); ++i) {
        lua_pushlstring(L, found[i].data(), found[i].size());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    return 1;
}

// coopnet.list_singletons() -> { "app.ropeway.PlayerManager", ... }
// Alle "Manager"-Objekte, die das Spiel gerade geladen hat.
int l_list_singletons(lua_State* L) {
    std::vector<std::string> names;
    {
        std::vector<REFrameworkManagedSingleton> buffer(4096);
        unsigned int count = 0;
        const auto size = static_cast<unsigned int>(buffer.size() * sizeof(REFrameworkManagedSingleton));
        if (g_sdk->functions->get_managed_singletons(buffer.data(), size, &count) == REFRAMEWORK_ERROR_NONE) {
            count = std::min<unsigned int>(count, static_cast<unsigned int>(buffer.size()));
            for (unsigned int i = 0; i < count; ++i) {
                auto name = type_full_name(buffer[i].t);
                if (!name.empty()) {
                    names.push_back(std::move(name));
                }
            }
        }
        std::sort(names.begin(), names.end());
    }

    lua_createtable(L, static_cast<int>(names.size()), 0);
    for (size_t i = 0; i < names.size(); ++i) {
        lua_pushlstring(L, names[i].data(), names[i].size());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    return 1;
}

void on_lua_state_created(lua_State* L) {
    if (g_session == nullptr) {
        g_session = new coop::net::Session{};
    }
    coop::net::register_lua_api(L, *g_session);

    if (g_sdk != nullptr) {
        lua_getglobal(L, "coopnet");
        lua_pushcfunction(L, l_find_types);
        lua_setfield(L, -2, "find_types");
        lua_pushcfunction(L, l_list_singletons);
        lua_setfield(L, -2, "list_singletons");
        lua_pop(L, 1);
    }
    OutputDebugStringA("[coopnet] Lua-API registriert\n");
}

void on_lua_state_destroyed(lua_State*) {
    // Die Session bleibt bestehen: Nach "Reset Scripts" ist die Verbindung
    // weiterhin da und die Skripte machen einfach weiter.
}

}  // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    // Wir nutzen nur Funktionen, die es seit API 1.0 gibt. Damit laeuft das
    // Plugin auch mit aelteren REFramework-Versionen.
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = 0;
    version->patch = 0;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    g_sdk = param->sdk;
    const auto* functions = param->functions;
    functions->on_lua_state_created(on_lua_state_created);
    functions->on_lua_state_destroyed(on_lua_state_destroyed);
    OutputDebugStringA("[coopnet] Plugin geladen\n");
    return true;
}
