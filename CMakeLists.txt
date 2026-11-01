cmake_minimum_required(VERSION 3.20)
project(REMods LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Statische C/C++-Runtime: Die DLL braucht dann kein extra VC++-Redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

option(REMODS_BUILD_TESTS "Tests bauen (laufen auch unter Linux)" ON)

add_subdirectory(third_party)
add_subdirectory(shared/netcore)
add_subdirectory(tools)

# REFramework-Plugins gibt es nur unter Windows.
if(WIN32)
    add_subdirectory(shared/re-engine/coopnet-plugin)
endif()

if(REMODS_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# --- Pakete --------------------------------------------------------------
# `cmake --install build --prefix dist/re2r-coop --component re2r-coop`
# erzeugt einen Ordner, der 1:1 in den Spielordner von RE2 kopiert wird.
if(WIN32)
    install(TARGETS remods_coopnet
        RUNTIME DESTINATION reframework/plugins
        COMPONENT re2r-coop)
endif()
install(DIRECTORY shared/re-engine/lua/
    DESTINATION reframework/autorun
    COMPONENT re2r-coop)
install(DIRECTORY games/re2r/coop/autorun/
    DESTINATION reframework/autorun
    COMPONENT re2r-coop)
