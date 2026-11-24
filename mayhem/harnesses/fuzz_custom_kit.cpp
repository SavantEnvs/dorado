// Fuzzes dorado's custom barcode-arrangement TOML parser (demux --barcode-arrangement):
// demux/parse_custom_kit.cpp (+ toml11). The API takes a file name, so the input is written to a
// per-iteration temp file.
#include "demux/parse_custom_kit.h"
#include "fuzz_common.h"

#include <exception>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string path = dorado_fuzz::write_temp(data, size, ".toml");
    if (path.empty()) return 0;
    try {
        auto kit = dorado::demux::parse_custom_arrangement(path);
        (void)kit;
    } catch (const std::exception&) {
    }
    try {
        dorado::barcode_kits::BarcodeKitScoringParams defaults{};
        auto params = dorado::demux::parse_scoring_params(path, defaults);
        (void)params;
    } catch (const std::exception&) {
    }
    unlink(path.c_str());
    return 0;
}
