# Infrastructure smoke tests (FASE 0). See docs/bootstrap.md §tests.
add_executable(mvc2_smoke_test smoke_test.cpp)
add_test(NAME infra.smoke COMMAND mvc2_smoke_test)

if(UNIX)
    add_test(NAME infra.active_target COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/test_target.sh")
endif()

find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_test(NAME infra.recomp_config COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_normalize_config.py")

find_program(NODE_EXECUTABLE node REQUIRED)
add_test(NAME infra.iop_parser COMMAND "${NODE_EXECUTABLE}" --test "${CMAKE_CURRENT_SOURCE_DIR}/test_iop_inventory.mjs")

add_test(NAME infra.iop_facts COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_iop_facts.py")

add_test(NAME infra.function_map_comparison COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_compare_function_maps.py")

add_test(NAME infra.analyzer_deps_restore COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_restore_analyzer_deps.py")
