// FASE 0 infrastructure smoke test.
// Proves the local C++20 toolchain (cmake + ninja + g++) compiles, links
// and runs a binary produced by this project's own top-level CMakeLists.
// It also exercises a tiny MIPS-flavoured computation so the test does
// something real: sign-extend a 16-bit immediate the way R5900 does.
#include <cstdint>
#include <cstdio>

static std::int64_t sx16(std::uint32_t v) {
    return static_cast<std::int64_t>(static_cast<std::int16_t>(v & 0xFFFFu));
}

int main() {
    bool ok = (sx16(0x0000) == 0) && (sx16(0x7FFF) == 32767) &&
              (sx16(0x8000) == -32768) && (sx16(0xFFFF) == -1);
    std::printf("mvc2_smoke_test: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
