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
    runtime/src/lua_host.cpp
    runtime/src/mt_explorer.cpp
    runtime/src/safe_mem.cpp
    runtime/src/input_hook.cpp)
target_link_libraries(remods_re0 PRIVATE coop_netcore imgui d3d9 dxguid)
target_compile_definitions(remods_re0 PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

# Git-Commit als Build-ID (wird im Spiel angezeigt)
find_package(Git QUIET)
set(REMODS_BUILD_ID "lokal")
if(GIT_FOUND)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        OUTPUT_VARIABLE REMODS_BUILD_ID_GIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(REMODS_BUILD_ID_GIT)
        set(REMODS_BUILD_ID ${REMODS_BUILD_ID_GIT})
    endif()
endif()
target_compile_definitions(remods_re0 PRIVATE REMODS_BUILD_ID="${REMODS_BUILD_ID}")
set_target_properties(remods_re0 PROPERTIES PREFIX "")

# Paket: `cmake --install build32 --prefix dist/RE0HD-Coop --component re0hd-coop`
# Inhalt 1:1 in den RE0-Spielordner kopieren.
install(TARGETS re0hd_loader RUNTIME DESTINATION . COMPONENT re0hd-coop)
install(TARGETS remods_re0 RUNTIME DESTINATION remods COMPONENT re0hd-coop)
install(DIRECTORY ${PROJECT_SOURCE_DIR}/shared/re-engine/lua/ DESTINATION remods/autorun COMPONENT re0hd-coop)
install(DIRECTORY lua/autorun/ DESTINATION remods/autorun COMPONENT re0hd-coop)
install(DIRECTORY lua/lib/ DESTINATION remods/lib COMPONENT re0hd-coop)

# --- Installer ---------------------------------------------------------------
# Eine einzige exe (REMods-RE0-Installer.exe), die alle Dateien des Pakets als
# Ressourcen enthaelt. Ressource 1 = Verzeichnis "id|relativer/pfad".

# Versionen fuer die Anzeige im Installer
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/lua/autorun/re0hd_coop.lua RE0_MOD_VERSION_LINE
    REGEX "^local MOD_VERSION = \"[^\"]+\"")
string(REGEX REPLACE ".*\"([^\"]+)\".*" "\1" RE0_MOD_VERSION "${RE0_MOD_VERSION_LINE}")
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/runtime/src/runtime.hpp RE0_RUNTIME_VERSION_LINE
    REGEX "kRuntimeVersion = \"[^\"]+\"")
string(REGEX REPLACE ".*\"([^\"]+)\".*" "\1" RE0_RUNTIME_VERSION "${RE0_RUNTIME_VERSION_LINE}")

set(RE0_PAYLOAD_RC "")
set(RE0_PAYLOAD_INDEX "")
set(RE0_PAYLOAD_DEPENDS "")
set(RE0_PAYLOAD_ID 100)
macro(re0_payload source dest)
    math(EXPR RE0_PAYLOAD_ID "${RE0_PAYLOAD_ID} + 1")
    string(APPEND RE0_PAYLOAD_RC "${RE0_PAYLOAD_ID} RCDATA \"${source}\"\n")
    string(APPEND RE0_PAYLOAD_INDEX "${RE0_PAYLOAD_ID}|${dest}\n")
    list(APPEND RE0_PAYLOAD_DEPENDS "${source}")
endmacro()

re0_payload("$<TARGET_FILE:re0hd_loader>" "dinput8.dll")
re0_payload("$<TARGET_FILE:remods_re0>" "remods/remods_re0.dll")
foreach(dir_pair
        "${PROJECT_SOURCE_DIR}/shared/re-engine/lua|remods/autorun"
        "${CMAKE_CURRENT_SOURCE_DIR}/lua/autorun|remods/autorun"
        "${CMAKE_CURRENT_SOURCE_DIR}/lua/lib|remods/lib")
    string(REPLACE "|" ";" dir_parts "${dir_pair}")
    list(GET dir_parts 0 src_dir)
    list(GET dir_parts 1 dest_dir)
    file(GLOB_RECURSE lua_files RELATIVE "${src_dir}" CONFIGURE_DEPENDS "${src_dir}/*.lua")
    list(SORT lua_files)
    foreach(f ${lua_files})
        re0_payload("${src_dir}/${f}" "${dest_dir}/${f}")
    endforeach()
endforeach()

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/payload_index.txt "${RE0_PAYLOAD_INDEX}")
file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/payload_$<CONFIG>.rc
    CONTENT "1 RCDATA \"${CMAKE_CURRENT_BINARY_DIR}/payload_index.txt\"\n${RE0_PAYLOAD_RC}")

add_executable(re0hd_installer WIN32
    installer/installer.cpp
    ${CMAKE_CURRENT_BINARY_DIR}/payload_$<CONFIG>.rc)
add_dependencies(re0hd_installer re0hd_loader remods_re0)
set_source_files_properties(${CMAKE_CURRENT_BINARY_DIR}/payload_$<CONFIG>.rc PROPERTIES
    OBJECT_DEPENDS "${RE0_PAYLOAD_DEPENDS};${CMAKE_CURRENT_BINARY_DIR}/payload_index.txt")
target_compile_definitions(re0hd_installer PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE
    REMODS_MOD_VERSION="${RE0_MOD_VERSION}" REMODS_RUNTIME_VERSION="${RE0_RUNTIME_VERSION}"
    REMODS_BUILD_ID="${REMODS_BUILD_ID}")
if(MSVC)
    target_compile_options(re0hd_installer PRIVATE /utf-8)
endif()
target_link_libraries(re0hd_installer PRIVATE shell32 ole32 advapi32)
set_target_properties(re0hd_installer PROPERTIES OUTPUT_NAME "REMods-RE0-Installer")

# `cmake --install build32 --prefix dist/RE0HD-Installer --component re0hd-installer`
install(TARGETS re0hd_installer RUNTIME DESTINATION . COMPONENT re0hd-installer)
