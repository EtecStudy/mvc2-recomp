// Independent map export using the pinned upstream analyzer API.
// Never imports Ghidra's CSV: sharing it would invalidate the cross-check.
#include "ps2recomp/elf_analyzer.h"
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>

static std::string csv(const std::string &s) {
    std::string out = "\"";
    for (char c : s) out += c == '"' ? "\"\"" : std::string(1, c);
    return out + "\"";
}

int main(int argc, char **argv) {
    if (argc != 4) {
        std::cerr << "Usage: mvc2_analyzer_export INPUT_ELF OUTPUT_TOML OUTPUT_CSV\n";
        return 2;
    }
    try {
        ps2recomp::ElfAnalyzer analyzer(argv[1]);
        if (!analyzer.analyze() || !analyzer.generateToml(argv[2])) return 1;
        const auto &functions = analyzer.getFunctions();
        if (functions.empty()) throw std::runtime_error("Analyzer returned an empty map");
        std::vector<const ps2recomp::Function *> ordered;
        ordered.reserve(functions.size());
        for (const auto &f : functions) ordered.push_back(&f);
        std::sort(ordered.begin(), ordered.end(), [](const auto *a, const auto *b) {
            return a->start < b->start;
        });
        std::ofstream out(argv[3]);
        out.exceptions(std::ios::badbit | std::ios::failbit);
        out << "Name,Start,End,Size\n";
        for (const auto *record : ordered) {
            const auto &f = *record;
            if (f.end <= f.start) throw std::runtime_error("Invalid analyzer range");
            out << csv(f.name) << ",0x" << std::hex << std::setw(8) << std::setfill('0') << f.start
                << ",0x" << std::setw(8) << f.end << ',' << std::dec << (f.end-f.start) << '\n';
        }
        out.close();
        std::cout << "Exported " << functions.size() << " independent analyzer records\n";
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "Analyzer export failed: " << e.what() << '\n';
        return 1;
    }
}
