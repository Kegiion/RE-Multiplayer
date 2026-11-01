add_executable(remods_luarun luarun/main.cpp)
target_link_libraries(remods_luarun PRIVATE coop_netcore)
if(MINGW)
    target_link_options(remods_luarun PRIVATE -static)
endif()

# Werkzeug-Paket: `cmake --install build --prefix dist/REMods-Tools --component tools`
install(TARGETS remods_luarun RUNTIME DESTINATION . COMPONENT tools)
install(DIRECTORY ${PROJECT_SOURCE_DIR}/shared/re-engine/lua/ DESTINATION lua COMPONENT tools)
install(FILES testbot/testbot.lua DESTINATION . COMPONENT tools)
if(WIN32)
    install(FILES testbot/testbot.bat DESTINATION . COMPONENT tools)
endif()
