// Fuzzes dorado's BED reader (aligner --bed-file): alignment/bed_file.cpp.
#include "alignment/bed_file.h"
#include "fuzz_common.h"

#include <exception>
#include <set>
#include <sstream>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string text(reinterpret_cast<const char*>(data), size);
    std::istringstream is(text);
    dorado::alignment::BedFile bed;
    try {
        if (!bed.load(is)) return 0;
    } catch (const std::exception&) {
        return 0;
    }
    // Look up every genome name that appears as a first column.
    std::istringstream lines(text);
    std::string line;
    size_t total = 0;
    while (std::getline(lines, line)) {
        auto tab = line.find_first_of("\t ");
        const auto& entries = bed.entries(line.substr(0, tab));
        for (const auto& e : entries) total += e.bed_line.size();
    }
    (void)total;
    return 0;
}
