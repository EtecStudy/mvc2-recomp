# Infrastructure smoke tests (FASE 0). See docs/bootstrap.md §tests.
add_executable(mvc2_smoke_test smoke_test.cpp)
add_test(NAME infra.smoke COMMAND mvc2_smoke_test)
