add_library(remods_coopnet SHARED src/plugin.cpp)
target_link_libraries(remods_coopnet PRIVATE coop_netcore reframework_api)
target_compile_definitions(remods_coopnet PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
# Immer "remods_coopnet.dll" (MinGW wuerde sonst "lib" voranstellen).
set_target_properties(remods_coopnet PROPERTIES PREFIX "")
