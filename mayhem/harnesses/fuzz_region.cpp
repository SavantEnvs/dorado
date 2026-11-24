// Fuzzes dorado's region parser (polish/variant --regions): secondary/common/region.cpp.
// --regions is either a comma-separated "name[:start[-end]]" list or the path of a BED-like file,
// so the input is split at the first NUL: the head is parsed as the string form, the tail is
// written to a fresh temp file whose path is passed to exercise the file form.
#include "fuzz_common.h"
#include "secondary/common/region.h"

#include <cstring>
#include <exception>
#include <string>
#include <utility>
#include <vector>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

static void exercise(const std::string& arg) {
    using namespace dorado::secondary;
    std::vector<Region> regions;
    try {
        regions = parse_regions(arg);
    } catch (const std::exception&) {
        return;
    }
    size_t total = 0;
    for (const auto& r : regions) total += to_string(r).size();
    (void)total;
    try {
        validate_regions(regions, {{"chr1", 1000}, {"chr2", 50}});
    } catch (const std::exception&) {
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    const char* p = reinterpret_cast<const char*>(data);
    const void* nul = std::memchr(p, '\0', size);
    const size_t head = nul ? static_cast<size_t>(static_cast<const char*>(nul) - p) : size;

    exercise(std::string(p, head));

    if (nul) {
        std::string path = dorado_fuzz::write_temp(data + head + 1, size - head - 1, ".bed");
        if (path.empty()) return 0;
        exercise(path);
        unlink(path.c_str());
    }
    return 0;
}
