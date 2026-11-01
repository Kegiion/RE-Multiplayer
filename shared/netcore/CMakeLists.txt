add_library(coop_netcore STATIC
    src/session.cpp
    src/lua_bindings.cpp)
target_include_directories(coop_netcore PUBLIC include)
target_link_libraries(coop_netcore PUBLIC enet lua)
if(UNIX)
    find_package(Threads REQUIRED)
    target_link_libraries(coop_netcore PUBLIC Threads::Threads)
endif()
