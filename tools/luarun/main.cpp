// remods_luarun - fuehrt ein Lua-Skript mit zwei Netzwerk-Sessions aus.
//
// Wird fuer die automatischen Tests und fuer den Testbot benutzt.
// Im Skript verfuegbar:
//   net_a, net_b  - wie `coopnet` im Spiel (zwei unabhaengige Sessions)
//   sleep_ms(ms)  - warten
//   arg           - Kommandozeilen-Argumente nach dem Skriptnamen (arg[1], ...)
//
// Aufruf: remods_luarun <skript.lua> [argumente ...]
//
// Lua-Module werden gesucht in: <Ordner der exe>/lua/, <Ordner des Skripts>/
// und in REMODS_LUA_PATH (Umgebungsvariable, Lua-Pfadmuster).
#include "coop/net/lua_bindings.hpp"
#include "coop/net/session.hpp"

#include <lua.hpp>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

namespace {

int l_sleep_ms(lua_State* L) {
    std::this_thread::sleep_for(std::chrono::milliseconds{luaL_checkinteger(L, 1)});
    return 0;
}

std::string dir_of(const std::string& path) {
    const auto pos = path.find_last_of("/\\");
    return pos == std::string::npos ? std::string{"."} : path.substr(0, pos);
}

void prepend_package_path(lua_State* L, const std::string& extra) {
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "path");
    const std::string path = extra + ";" + lua_tostring(L, -1);
    lua_pop(L, 1);
    lua_pushstring(L, path.c_str());
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "Aufruf: %s <skript.lua> [argumente ...]\n", argv[0]);
        return 2;
    }
    const std::string script = argv[1];

    coop::net::Session a, b;
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    coop::net::register_lua_api(L, a, "net_a");
    coop::net::register_lua_api(L, b, "net_b");
    lua_register(L, "sleep_ms", l_sleep_ms);

    std::string search = dir_of(argv[0]) + "/lua/?.lua;" + dir_of(script) + "/?.lua";
    if (const char* env = std::getenv("REMODS_LUA_PATH")) {
        search = std::string{env} + ";" + search;
    }
    prepend_package_path(L, search);

    lua_createtable(L, argc - 2, 1);
    lua_pushstring(L, script.c_str());
    lua_rawseti(L, -2, 0);
    for (int i = 2; i < argc; ++i) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i - 1);
    }
    lua_setglobal(L, "arg");

    int rc = 0;
    if (luaL_dofile(L, script.c_str()) != LUA_OK) {
        std::fprintf(stderr, "%s\n", lua_tostring(L, -1));
        rc = 1;
    }
    lua_close(L);
    return rc;
}
