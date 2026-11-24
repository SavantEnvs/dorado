// Fuzzes dorado's model-argument parser (basecaller/duplex/download `--model` strings such as
// "hac,5mC@v2" or "dna_r10.4.1_e8.2_400bps_hac@v5.0.0,..."): models/model_complex.cpp, models.cpp,
// kits.cpp. Path-style arguments only store the string; nothing is opened.
#include "fuzz_common.h"
#include "models/model_complex.h"

#include <exception>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string raw(reinterpret_cast<const char*>(data), size);
    try {
        auto mc = dorado::models::ModelComplex::parse(raw);
        if (mc.is_named_style()) {
            (void)mc.get_named_simplex_model();
            (void)mc.get_named_mods_models();
        } else if (mc.is_variant_style()) {
            (void)mc.get_simplex_model_variant();
            (void)mc.get_mod_model_variants();
        }
        (void)mc.has_mods();
    } catch (const std::exception&) {
    }
    return 0;
}
