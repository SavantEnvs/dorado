// Fuzzes dorado's sample-sheet CSV loader (--sample-sheet): utils/SampleSheet.cpp.
#include "fuzz_common.h"
#include "utils/SampleSheet.h"

#include <exception>
#include <sstream>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string text(reinterpret_cast<const char*>(data), size);
    std::istringstream is(text);
    dorado::utils::SampleSheet ss;
    try {
        ss.load(is, "fuzz.csv");
    } catch (const std::exception&) {
        return 0;
    }
    try {
        auto bcs = ss.get_barcode_values();
        if (bcs) {
            for (const auto& bc : *bcs) {
                (void)ss.get_alias(bc);
                (void)ss.get_sample_type(bc);
                (void)ss.barcode_is_permitted(bc);
            }
        }
        (void)ss.get_alias("FAX00000", "pos", "exp", "barcode01");
        (void)ss.get_sample_type("FAX00000", "pos", "exp", "barcode01");
    } catch (const std::exception&) {
    }
    return 0;
}
