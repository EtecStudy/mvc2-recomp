# Inject a separate adapter target without modifying pinned upstream sources.
# Used via CMAKE_PROJECT_PS2RetroX_INCLUDE while upstream remains CMAKE_SOURCE_DIR.
add_executable(mvc2_analyzer_export "${CMAKE_CURRENT_LIST_DIR}/analyzer_export.cpp")
target_compile_features(mvc2_analyzer_export PRIVATE cxx_std_20)
target_link_libraries(mvc2_analyzer_export PRIVATE ps2_analyzer_lib)
