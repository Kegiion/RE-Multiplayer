# --- ENet (zuverlaessiges UDP) -------------------------------------------
add_library(enet STATIC
    enet/callbacks.c
    enet/compress.c
    enet/host.c
    enet/list.c
    enet/packet.c
    enet/peer.c
    enet/protocol.c
    enet/unix.c
    enet/win32.c)
target_include_directories(enet PUBLIC enet/include)
if(WIN32)
    target_link_libraries(enet PUBLIC ws2_32 winmm)
else()
    target_compile_definitions(enet PRIVATE
        HAS_SOCKLEN_T=1 HAS_GETADDRINFO=1 HAS_GETNAMEINFO=1 HAS_FCNTL=1
        HAS_POLL=1 HAS_MSGHDR_FLAGS=1 HAS_INET_PTON=1 HAS_INET_NTOP=1)
endif()

# --- Lua 5.4.3 (exakt die Version aus REFramework) ------------------------
# Das Plugin arbeitet direkt auf REFrameworks lua_State. Deshalb MUSS die
# Lua-Version identisch sein - nicht einfach aktualisieren!
file(GLOB LUA_SOURCES CONFIGURE_DEPENDS lua/src/*.c)
add_library(lua STATIC ${LUA_SOURCES})
target_include_directories(lua PUBLIC lua/src)
if(UNIX)
    target_compile_definitions(lua PRIVATE LUA_USE_POSIX)
endif()

# --- REFramework Plugin-API (nur Header) ----------------------------------
add_library(reframework_api INTERFACE)
target_include_directories(reframework_api INTERFACE reframework/include)
