#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for dorado's file parsers (built by mayhem/build.sh with normal
# flags). Each case runs mayhem/out/dorado_oracle on an upstream test-data file (tests/data/...) or a
# case under mayhem/oracle/cases and diffs the parsed dump against mayhem/oracle/expected/<n>.txt.
# It also runs upstream's own Catch2 unit tests for the same parsers (tests/CigarTest.cpp,
# SampleSheetTests.cpp, bed_file_test.cpp, PafUtilsTest.cpp, ModelMetadataTest.cpp, ModelKitsTest.cpp,
# SequenceUtilsTest.cpp, StringUtilsTest.cpp, SecondaryWindowTest.cpp), built by build.sh as
# mayhem/out/dorado_unit_tests. Those files are torch- and htslib-free; the rest of the dorado_tests
# binary (and tests/main.cpp) links libtorch, which this CPU-only image cannot fetch, so it is not run.
# The CTRF line counts every Catch2 test case plus every oracle case.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

ORACLE="$SRC/mayhem/out/dorado_oracle"
if [ ! -x "$ORACLE" ]; then
  echo "test.sh: $ORACLE missing — run mayhem/build.sh first" >&2
  emit_ctrf "dorado-oracle" 0 1
  exit 1
fi

D=tests/data
C=mayhem/oracle/cases
CASES=(
  "sample_sheet_single:sample_sheet $D/sample_sheets/single_barcode.csv PAO25751"
  "sample_sheet_invalid:sample_sheet $D/sample_sheets/invalid.csv"
  "sample_sheet_nobarcode:sample_sheet $D/sample_sheets/no_barcode.csv"
  "sample_sheet_weird:sample_sheet $D/sample_sheets/valid_but_weird.csv"
  "sample_sheet_unique:sample_sheet $C/unique_barcodes.csv"
  "bed_test:bed $D/bedfile_test/test_bed.bed"
  "bed_target:bed $D/aligner_test/target.bed"
  "bed_simple:bed $C/simple.bed"
  "paf_test:paf $D/paf_utils/test.paf"
  "sample_sheet_unique_fc:sample_sheet $C/unique_barcodes.csv FAX12345"
  "kit_single:custom_kit $D/barcode_demux/custom_barcodes/test_kit_single_ended.toml"
  "kit_rear:custom_kit $D/barcode_demux/custom_barcodes/test_kit_single_ended_rear.toml"
  "kit_double:custom_kit $D/barcode_demux/custom_barcodes/test_kit_double_ended.toml"
  "kit_diff_flanks:custom_kit $D/barcode_demux/custom_barcodes/test_kit_ends_different_flanks.toml"
  "kit_diff_barcodes:custom_kit $D/barcode_demux/custom_barcodes/test_kit_ends_different_barcodes.toml"
  "kit_dual:custom_kit $D/barcode_demux/custom_barcodes/dual_arr.toml"
  "kit_rpb004:custom_kit $D/barcode_demux/custom_barcodes/RPB004.toml"
  "kit_bad_double:custom_kit $D/barcode_demux/custom_barcodes/bad_double_ended_kit.toml"
  "kit_bad_params:custom_kit $D/barcode_demux/custom_barcodes/bad_double_ended_kit_not_all_params_set.toml"
  "kit_flank_free:custom_kit $D/barcode_demux/custom_barcodes/flank_free_arrangement.toml"
  "poly_tail_default:poly_tail $D/poly_a/configs/polya.toml"
  "poly_tail_bc01_disabled:poly_tail $D/poly_a/configs/polya_bc01_disabled.toml"
  "model_args:model $C/models.txt"
  "scoring_params:scoring $D/barcode_demux/custom_barcodes/scoring_params.toml"
  "scoring_split:scoring $D/barcode_demux/custom_barcodes/dual_arr_split.toml"
  "scoring_default:scoring $D/barcode_demux/custom_barcodes/test_kit_single_ended.toml"
)

passed=0; failed=0

# 1) Upstream Catch2 unit tests, run from the repo root (TestUtils' get_data_dir uses ./tests/data).
UNIT="$SRC/mayhem/out/dorado_unit_tests"
if [ -x "$UNIT" ]; then
  xml="$(mktemp)"
  "$UNIT" --rng-seed 1 -r console -r "xml::out=$xml" | tail -3; urc=${PIPESTATUS[0]}
  up=$(grep -c '<OverallResult success="true"' "$xml"); uf=$(grep -c '<OverallResult success="false"' "$xml")
  rm -f "$xml"
  echo "catch2: $up passed, $uf failed (rc=$urc)"
  if [ "$urc" -ne 0 ] && [ "$uf" -eq 0 ]; then uf=1; fi
  if [ "$up" -eq 0 ]; then uf=$((uf+1)); fi
  passed=$((passed+up)); failed=$((failed+uf))
else
  echo "FAIL $UNIT missing — run mayhem/build.sh first"; failed=$((failed+1))
fi

# 2) Oracle cases.
for c in "${CASES[@]}"; do
  name="${c%%:*}"; args="${c#*:}"
  exp="mayhem/oracle/expected/$name.txt"
  # shellcheck disable=SC2086
  got="$("$ORACLE" $args 2>&1)"; rc=$?
  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then printf '%s\n' "$got" > "$exp"; fi
  if [ $rc -eq 0 ] && [ -f "$exp" ] && [ "$got" = "$(cat "$exp")" ]; then
    passed=$((passed+1)); echo "PASS $name"
  else
    failed=$((failed+1)); echo "FAIL $name (rc=$rc)"
    [ -f "$exp" ] && diff <(printf '%s\n' "$got") "$exp" | head -5
  fi
done
emit_ctrf "dorado-oracle" "$passed" "$failed"
