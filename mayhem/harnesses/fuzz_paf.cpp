// Fuzzes dorado's PAF row parser (correct --from-paf) and CIGAR string parser:
// utils/paf_utils.cpp, utils/cigar.cpp. The CIGAR parser is reached the way
// `dorado correct --from-paf` reaches it: through the cg:Z: tag of a parsed row.
#include "fuzz_common.h"
#include "utils/cigar.h"
#include "utils/paf_utils.h"

#include <exception>
#include <sstream>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    dorado_fuzz::silence_logging();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    std::string text(reinterpret_cast<const char*>(data), size);
    std::istringstream lines(text);
    std::string line;
    while (std::getline(lines, line)) {
        try {
            dorado::utils::PafEntry e = dorado::utils::parse_paf(line);
            (void)dorado::utils::serialize_paf(e);
            auto cg = dorado::utils::paf_aux_get(e, "cg", 'Z');
            auto ops = dorado::parse_cigar_from_string(cg);
            (void)dorado::serialize_cigar(ops);
        } catch (const std::exception&) {
        }
    }
    return 0;
}
