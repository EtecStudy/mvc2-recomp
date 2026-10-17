cmake_minimum_required(VERSION 3.21)
# ============================================================================
# mvc2-recomp — Marvel vs. Capcom 2 (PS2, SLUS-204.86) native PC port
# via PS2Recomp static recompilation.
#
# FASE 0 skeleton. Real targets (recompiled game code + runtime) are added
# in later phases; see docs/architecture.md. This file currently exists so
# the top-level configure is exercised by the infrastructure smoke tests.
# ============================================================================
project(mvc2-recomp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(MVC2_BUILD_TESTS "Build mvc2-recomp infrastructure tests" ON)

# Hand-written runtime / glue code (src/) — populated from FASE 2 onwards.
# add_subdirectory(src)

if(MVC2_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

message(STATUS "mvc2-recomp FASE 0 skeleton configured (no game targets yet)")
