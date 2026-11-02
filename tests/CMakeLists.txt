# Diese Tests laufen ohne Spiel (auch unter Linux) und pruefen Netzwerk-Kern,
# Lua-Anbindung und das gemeinsame Lua-Protokoll.

add_executable(netcore_test netcore_test.cpp)
target_link_libraries(netcore_test PRIVATE coop_netcore)
add_test(NAME netcore COMMAND netcore_test)

# Lua-Tests laufen mit tools/luarun (zwei Sessions `net_a`, `net_b`).
set(REMODS_LUA_PATH "${PROJECT_SOURCE_DIR}/shared/re-engine/lua/?.lua")
set(RE2R_AUTORUN "${PROJECT_SOURCE_DIR}/games/re2r/coop/autorun")
set(RE0HD_LUA "${PROJECT_SOURCE_DIR}/games/re0hd/lua")

foreach(name protocol session re2r_mock re0hd_mock re0hd_puppet testbot)
    add_test(NAME lua_${name} COMMAND remods_luarun "${CMAKE_CURRENT_SOURCE_DIR}/lua/${name}_test.lua")
    set_tests_properties(lua_${name} PROPERTIES ENVIRONMENT
        "REMODS_LUA_PATH=${REMODS_LUA_PATH};REMODS_RE2R_AUTORUN=${RE2R_AUTORUN};REMODS_RE0HD_LUA=${RE0HD_LUA};REMODS_TOOLS=${PROJECT_SOURCE_DIR}/tools")
endforeach()
