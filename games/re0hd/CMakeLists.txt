# RE0 HD Remaster: re0hd.exe ist ein 32-Bit-Programm (MT Framework, D3D9).
# Wird nur bei einem Win32-Build gebaut: cmake -S . -B build32 -A Win32

# Loader: ersetzt dinput8.dll im Spielordner und laedt die Runtime.
add_library(re0hd_loader SHARED loader/dinput8.cpp)
target_compile_definitions(re0hd_loader PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(re0hd_loader PROPERTIES OUTPUT_NAME dinput8 PREFIX "")

# Runtime: Overlay, Lua, Netzwerk.
add_library(remods_re0 SHARED
    runtime/src/main.cpp
    runtime/src/log.cpp
    runtime/src/d3d9_hook.cpp
    runtime/src/overlay.cpp
    runtime/src/lua_host.cpp)
target_link_libraries(remods_re0 PRIVATE coop_netcore imgui d3d9)
target_compile_definitions(remods_re0 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(remods_re0 PROPERTIES PREFIX "")

# Paket: `cmake --install build32 --prefix dist/RE0HD-Coop --component re0hd-coop`
# Inhalt 1:1 in den RE0-Spielordner kopieren.
install(TARGETS re0hd_loader RUNTIME DESTINATION . COMPONENT re0hd-coop)
install(TARGETS remods_re0 RUNTIME DESTINATION remods COMPONENT re0hd-coop)
install(DIRECTORY ${PROJECT_SOURCE_DIR}/shared/re-engine/lua/ DESTINATION remods/autorun COMPONENT re0hd-coop)
install(DIRECTORY lua/autorun/ DESTINATION remods/autorun COMPONENT re0hd-coop)
install(DIRECTORY lua/lib/ DESTINATION remods/lib COMPONENT re0hd-coop)
