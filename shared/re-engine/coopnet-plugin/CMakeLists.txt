add_library(remultiplayer_coopnet SHARED src/plugin.cpp)
target_link_libraries(remultiplayer_coopnet PRIVATE coop_netcore reframework_api)
target_compile_definitions(remultiplayer_coopnet PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
# Immer "remultiplayer_coopnet.dll" (MinGW wuerde sonst "lib" voranstellen).
set_target_properties(remultiplayer_coopnet PROPERTIES PREFIX "")
