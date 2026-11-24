// Functional oracle: runs dorado's upstream parsers on a file and prints a canonical dump of what
// they parsed, so mayhem/test.sh can diff it against golden output.
//   dorado_oracle <sample_sheet|bed|paf|custom_kit|scoring> <file>
#include "alignment/bed_file.h"
#include "demux/parse_custom_kit.h"
#include "models/model_complex.h"
#include "poly_tail/poly_tail_config.h"
#include "utils/SampleSheet.h"
#include "utils/cigar.h"
#include "utils/paf_utils.h"

#include <spdlog/spdlog.h>

#include <algorithm>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

static void dump_list(const char* k, const std::vector<std::string>& v) {
    std::cout << k << "=";
    for (size_t i = 0; i < v.size(); ++i) std::cout << (i ? "," : "") << v[i];
    std::cout << "\n";
}

int main(int argc, char** argv) {
    spdlog::set_level(spdlog::level::off);
    if (argc != 3 && argc != 4) {
        std::cerr << "usage: dorado_oracle <mode> <file> [flow_cell_id]\n";
        return 2;
    }
    std::string mode = argv[1], file = argv[2];
    std::string fc = argc == 4 ? argv[3] : "";
    try {
        if (mode == "sample_sheet") {
            dorado::utils::SampleSheet ss;
            ss.load(file);
            std::cout << "type=" << (ss.get_type() == dorado::utils::SampleSheet::Type::barcode ? "barcode" : "none") << "\n";
            auto bcs = ss.get_barcode_values();
            if (bcs) {
                std::vector<std::string> v(bcs->begin(), bcs->end());
                std::sort(v.begin(), v.end());
                for (auto& b : v) {
                    std::cout << "barcode " << b << " permitted=" << ss.barcode_is_permitted(b);
                    std::string alias;
                    try {
                        alias = ss.get_alias(b);
                    } catch (const std::logic_error&) {
                        alias = "<not-unique>";
                    }
                    std::cout << " alias=" << alias << " fc_alias=" << ss.get_alias(fc, "", "", b)
                              << " type=" << ss.get_sample_type(fc, "", "", b);
                    std::cout << "\n";
                }
            } else {
                std::cout << "no barcodes\n";
            }
        } else if (mode == "bed") {
            dorado::alignment::BedFile bed;
            std::cout << "loaded=" << bed.load(file) << "\n";
            std::vector<std::string> genomes;
            std::ifstream in(file);
            std::string line;
            while (std::getline(in, line)) {
                std::string g = line.substr(0, line.find_first_of("\t "));
                if (std::find(genomes.begin(), genomes.end(), g) == genomes.end()) genomes.push_back(g);
            }
            for (const auto& g : genomes) {
                for (const auto& e : bed.entries(g)) {
                    std::cout << g << " " << e.start << " " << e.end << " " << e.strand << "\n";
                }
            }
        } else if (mode == "paf") {
            std::ifstream in(file);
            std::string line;
            while (std::getline(in, line)) {
                auto e = dorado::utils::parse_paf(line);
                std::cout << e.qname << " " << e.qlen << " " << e.qstart << "-" << e.qend << " "
                          << e.strand << " " << e.tname << " " << e.tlen << " " << e.tstart << "-"
                          << e.tend << " m=" << e.num_residue_matches << " b=" << e.alignment_block_length
                          << " q=" << e.mapq;
                auto cg = dorado::utils::paf_aux_get(e, "cg", 'Z');
                if (!cg.empty()) {
                    auto ops = dorado::parse_cigar_from_string(cg);
                    auto ser = dorado::serialize_cigar(ops);
                    std::cout << " ops=" << ops.size() << " cigar_len=" << ser.size()
                              << " roundtrip=" << (ser == cg) << " head=" << ser.substr(0, 24);
                }
                std::cout << "\n";
            }
        } else if (mode == "custom_kit") {
            auto [name, k] = dorado::demux::parse_custom_arrangement(file);
            std::cout << "name=" << name << " kit=" << k.name << " double_ends=" << k.double_ends
                      << " ends_different=" << k.ends_different << " rear_only=" << k.rear_only_barcodes
                      << "\n";
            std::cout << "flanks=" << k.top_front_flank << "|" << k.top_rear_flank << "|"
                      << k.bottom_front_flank << "|" << k.bottom_rear_flank << "\n";
            dump_list("barcodes", k.barcodes);
            dump_list("barcodes2", k.barcodes2);
        } else if (mode == "scoring") {
            dorado::barcode_kits::BarcodeKitScoringParams d{};
            auto p = dorado::demux::parse_scoring_params(file, d);
            std::cout << p.max_barcode_penalty << " " << p.barcode_end_proximity << " "
                      << p.min_barcode_penalty_dist << " " << p.min_separation_only_dist << " "
                      << p.flank_left_pad << " " << p.flank_right_pad << " " << p.front_barcode_window
                      << " " << p.rear_barcode_window << " " << p.min_flank_score << " "
                      << p.midstrand_flank_score << "\n";
        } else if (mode == "poly_tail") {
            auto cfgs = dorado::poly_tail::prepare_configs(file);
            for (const auto& c : cfgs) {
                std::cout << "bc=" << c.barcode_id << " enabled=" << c.enabled << " plasmid=" << c.is_plasmid
                          << " front=" << c.front_primer << " rear=" << c.rear_primer
                          << " rc_front=" << c.rc_front_primer << " pf=" << c.plasmid_front_flank
                          << " pr=" << c.plasmid_rear_flank << " interrupt=" << c.tail_interrupt_length
                          << " min_base=" << c.min_base_count << " window=" << c.primer_window << "\n";
            }
        } else if (mode == "model") {
            // Each line of the file is one --model argument.
            std::ifstream in(file);
            std::string line;
            while (std::getline(in, line)) {
                std::cout << line << " -> ";
                try {
                    auto mc = dorado::models::ModelComplex::parse(line);
                    if (mc.is_named_style()) {
                        std::cout << "named simplex=" << mc.get_named_simplex_model().name << " mods=";
                        for (const auto& m : mc.get_named_mods_models()) std::cout << m.name << ";";
                    } else if (mc.is_variant_style()) {
                        std::cout << "variant mods=" << mc.get_mod_model_variants().size();
                    } else {
                        std::cout << "path";
                    }
                } catch (const std::exception& e) {
                    std::cout << "error: " << e.what();
                }
                std::cout << "\n";
            }
        } else {
            std::cerr << "unknown mode\n";
            return 2;
        }
    } catch (const std::exception& e) {
        std::cout << "error: " << e.what() << "\n";
    }
    return 0;
}
