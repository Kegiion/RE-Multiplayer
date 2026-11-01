#include "coop/net/lua_bindings.hpp"

#include "coop/net/session.hpp"

#include <lua.hpp>

#include <chrono>
#include <string>

namespace coop::net {

namespace {

// Hinweis: luaL_error/luaL_check* springen per longjmp zurueck. Deshalb
// werden alle Argumente geprueft, BEVOR C++-Objekte auf dem Stack entstehen.

Session& session_of(lua_State* L) {
    return *static_cast<Session*>(lua_touserdata(L, lua_upvalueindex(1)));
}

uint16_t check_port(lua_State* L, int arg) {
    const lua_Integer port = luaL_checkinteger(L, arg);
    luaL_argcheck(L, port > 0 && port <= 65535, arg, "Port muss zwischen 1 und 65535 liegen");
    return static_cast<uint16_t>(port);
}

int push_result(lua_State* L, bool ok, const std::string& error) {
    if (ok) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushnil(L);
    lua_pushlstring(L, error.data(), error.size());
    return 2;
}

int l_version(lua_State* L) {
    lua_pushstring(L, kCoopnetVersion);
    return 1;
}

int l_time(lua_State* L) {
    using namespace std::chrono;
    static const auto start = steady_clock::now();
    lua_pushnumber(L, duration<double>(steady_clock::now() - start).count());
    return 1;
}

int l_host(lua_State* L) {
    const uint16_t port = check_port(L, 1);
    const lua_Integer max_peers = luaL_optinteger(L, 2, 3);
    luaL_argcheck(L, max_peers >= 1 && max_peers <= 32, 2, "max_peers muss zwischen 1 und 32 liegen");

    std::string error;
    const bool ok = session_of(L).host(port, static_cast<size_t>(max_peers), &error);
    return push_result(L, ok, error);
}

int l_connect(lua_State* L) {
    const char* address = luaL_checkstring(L, 1);
    const uint16_t port = check_port(L, 2);

    std::string error;
    const bool ok = session_of(L).connect(address, port, &error);
    return push_result(L, ok, error);
}

int l_disconnect(lua_State* L) {
    session_of(L).disconnect();
    return 0;
}

int l_send(lua_State* L) {
    size_t size = 0;
    const char* data = luaL_checklstring(L, 1, &size);
    const bool reliable = lua_toboolean(L, 2) != 0;
    const lua_Integer peer = luaL_optinteger(L, 3, kAllPeers);
    luaL_argcheck(L, peer >= 0, 3, "ungueltige Peer-ID");

    const bool ok = session_of(L).send(static_cast<uint32_t>(peer), data, size, reliable);
    lua_pushboolean(L, ok ? 1 : 0);
    return 1;
}

const char* event_type_name(EventType type) {
    switch (type) {
    case EventType::Connected: return "connect";
    case EventType::Disconnected: return "disconnect";
    case EventType::Message: return "message";
    }
    return "unknown";
}

int l_poll(lua_State* L) {
    const auto events = session_of(L).poll();

    lua_createtable(L, static_cast<int>(events.size()), 0);
    int index = 1;
    for (const auto& ev : events) {
        lua_createtable(L, 0, 4);
        lua_pushstring(L, event_type_name(ev.type));
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, ev.peer);
        lua_setfield(L, -2, "peer");
        lua_pushboolean(L, ev.reliable ? 1 : 0);
        lua_setfield(L, -2, "reliable");
        if (ev.type == EventType::Message) {
            lua_pushlstring(L, ev.data.data(), ev.data.size());
            lua_setfield(L, -2, "data");
        }
        lua_rawseti(L, -2, index++);
    }
    return 1;
}

int l_status(lua_State* L) {
    auto& session = session_of(L);
    const auto peers = session.peers();
    const auto stats = session.stats();
    const auto error = session.last_error();

    lua_createtable(L, 0, 4);

    lua_pushstring(L, to_string(session.mode()));
    lua_setfield(L, -2, "mode");

    if (!error.empty()) {
        lua_pushlstring(L, error.data(), error.size());
        lua_setfield(L, -2, "error");
    }

    lua_createtable(L, static_cast<int>(peers.size()), 0);
    int index = 1;
    for (const auto& peer : peers) {
        lua_createtable(L, 0, 3);
        lua_pushinteger(L, peer.id);
        lua_setfield(L, -2, "id");
        lua_pushlstring(L, peer.address.data(), peer.address.size());
        lua_setfield(L, -2, "address");
        lua_pushinteger(L, peer.rtt_ms);
        lua_setfield(L, -2, "rtt");
        lua_rawseti(L, -2, index++);
    }
    lua_setfield(L, -2, "peers");

    lua_createtable(L, 0, 4);
    lua_pushinteger(L, static_cast<lua_Integer>(stats.messages_sent));
    lua_setfield(L, -2, "messages_sent");
    lua_pushinteger(L, static_cast<lua_Integer>(stats.messages_received));
    lua_setfield(L, -2, "messages_received");
    lua_pushinteger(L, static_cast<lua_Integer>(stats.bytes_sent));
    lua_setfield(L, -2, "bytes_sent");
    lua_pushinteger(L, static_cast<lua_Integer>(stats.bytes_received));
    lua_setfield(L, -2, "bytes_received");
    lua_setfield(L, -2, "stats");

    return 1;
}

}  // namespace

void register_lua_api(lua_State* L, Session& session, const char* global_name) {
    static const luaL_Reg functions[] = {
        {"version", l_version},
        {"time", l_time},
        {"host", l_host},
        {"connect", l_connect},
        {"disconnect", l_disconnect},
        {"send", l_send},
        {"poll", l_poll},
        {"status", l_status},
        {nullptr, nullptr},
    };

    lua_createtable(L, 0, 8);
    lua_pushlightuserdata(L, &session);
    luaL_setfuncs(L, functions, 1);
    lua_setglobal(L, global_name);
}

}  // namespace coop::net
