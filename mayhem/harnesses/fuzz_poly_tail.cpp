// Fuzzes dorado's poly(A)-tail config TOML parser (--poly-tail-config / --estimate-poly-a):
// poly_tail/poly_tail_config.cpp (+ toml11, sequence validation).
#include "fuzz_common.h"
#include "poly_tail/poly_tail_config.h"

#include <exception>
#include <sstream>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string text(reinterpret_cast<const char*>(data), size);
    std::istringstream is(text);
    try {
        auto configs = dorado::poly_tail::prepare_configs(is);
        size_t n = 0;
        for (const auto& c : configs) n += c.barcode_id.size() + c.rc_front_primer.size();
        (void)n;
    } catch (const std::exception&) {
    }
    return 0;
}
