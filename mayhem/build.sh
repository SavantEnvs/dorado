#!/usr/bin/env bash
#
# mayhem/build.sh — build dorado's fuzz harnesses and the functional oracle.
#
# dorado's full CMake build hard-requires the CUDA toolkit plus ONT's CDN libtorch/Koi/pod5 binaries,
# none of which can be cached in a CPU-only, air-gapped image. The parsers of untrusted files live in
# torch-free libraries (utils, alignment, demux parsers), so we compile exactly those upstream
# sources directly (from /mayhem/dorado, plus the header-only submodules under dorado/3rdparty that
# CI checks out recursively) with the sanitizer + coverage flags, and link each harness against them.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
U="$SRC/dorado"
T="$U/3rdparty"
OUT="$SRC/mayhem/out"          # gitignored build dir (mayhem/.gitignore)
mkdir -p "$OUT/fuzz" "$OUT/test"

INCS=(-I"$U" -I"$U/utils/include" -I"$U/alignment/include" -I"$U/demux/include" -I"$U/poly_tail/include" -I"$U/models/include" -I"$U/secondary/common/include"
      -I"$U/compat/include" -I"$T/spdlog/include" -I"$T/toml11/include" -I"$T/date/include"
      -I"$T/edlib/edlib/include" -I"$T/ont-minimap2/src/3rdparty/minimap2" -I"$T/NVTX/c/include" -I"$T/intervaltree")
CXXSTD=(-std=c++23 -Wno-deprecated-literal-operator -Wno-unused-command-line-argument)

# The torch-free upstream sources the harnesses reach.
LIB_SRCS=(
  utils/SampleSheet.cpp
  utils/paf_utils.cpp
  utils/cigar.cpp
  utils/barcode_kits.cpp
  alignment/bed_file.cpp
  demux/parse_custom_kit.cpp
  utils/sequence_utils.cpp
  poly_tail/poly_tail_config.cpp
  models/model_complex.cpp
  models/models.cpp
  models/kits.cpp
  models/metadata.cpp
  secondary/common/region.cpp
)

# compile_lib <outdir> <flags...>: compile LIB_SRCS into <outdir> (make-style: only stale objects).
compile_lib() {
  local od="$1"; shift
  local pids=() s o
  for s in "${LIB_SRCS[@]}"; do
    o="$od/$(echo "$s" | tr '/' '_').o"
    ( "$CXX" "${CXXSTD[@]}" "$@" "${INCS[@]}" -c "$U/$s" -o "$o" ) &
    pids+=($!)
    if [ "${#pids[@]}" -ge "$MAYHEM_JOBS" ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
  done
  for p in "${pids[@]}"; do wait "$p"; done
}

# 1) Sanitized + SanCov-instrumented upstream objects (the fuzzed code).
FUZZ_FLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link -ffunction-sections -fdata-sections)
compile_lib "$OUT/fuzz" "${FUZZ_FLAGS[@]}"
"$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/fuzz/standalone_main.o"
"$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/fuzz/lsan_off.o"

LDGC=(-fuse-ld=lld -Wl,--gc-sections -lpthread)

# 2) Each harness twice: libFuzzer binary and standalone reproducer.
for h in sample_sheet bed_file paf custom_kit poly_tail model_complex region; do
  src="$SRC/mayhem/harnesses/fuzz_${h}.cpp"
  "$CXX" "${CXXSTD[@]}" "${FUZZ_FLAGS[@]}" "${INCS[@]}" -c "$src" -o "$OUT/fuzz/h_${h}.o"
  objs=($(ls "$OUT"/fuzz/*.o | grep -v -e '/h_' -e standalone_main -e lsan_off))
  "$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/fuzz/h_${h}.o" "${objs[@]}" \
      "$OUT/fuzz/lsan_off.o" "${LDGC[@]}" -o "$SRC/fuzz_${h}"
  "$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/fuzz/h_${h}.o" "$OUT/fuzz/standalone_main.o" "${objs[@]}" \
      "$OUT/fuzz/lsan_off.o" "${LDGC[@]}" -o "$SRC/fuzz_${h}-standalone"
done

# 3) Functional oracle with NORMAL flags (no sanitizers): mayhem/oracle/dorado_oracle.cpp drives the
#    same upstream parsers on known inputs; test.sh diffs its output against golden files.
compile_lib "$OUT/test" -O1 $COVERAGE_FLAGS -ffunction-sections -fdata-sections
"$CXX" "${CXXSTD[@]}" -O1 $COVERAGE_FLAGS "${INCS[@]}" "$SRC/mayhem/oracle/dorado_oracle.cpp" \
    $(ls "$OUT"/test/*_*.o) $COVERAGE_FLAGS "${LDGC[@]}" -o "$SRC/mayhem/out/dorado_oracle"

# 4) Upstream's torch-free Catch2 unit tests for the harnessed parsers. tests/main.cpp and the
#    dorado_tests binary need torch, but these test files include only the parser headers above plus
#    Catch2, so they link against the same non-sanitized $OUT/test objects and Catch2WithMain.
#    (CATCH_CONFIG_PREFIX_ALL is also passed on the command line: a CMake reconfigure after a
#    compiler-path change, e.g. ccache prefill vs plain re-run, drops the -D cache entries.)
#    Catch2 is built offline from the dorado/3rdparty/catch2 submodule with its own CMake (generated
#    catch_user_config.hpp, benchmark/ and internal/ headers), with the same normal flags.
CATCH_SRC="$T/catch2"; CATCH_BLD="$OUT/catch2"
cmake -S "$CATCH_SRC" -B "$CATCH_BLD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_CXX_FLAGS="-O1" -DCATCH_CONFIG_PREFIX_ALL=ON -DCATCH_INSTALL_DOCS=OFF \
    -DCATCH_INSTALL_EXTRAS=OFF -DCATCH_BUILD_TESTING=OFF -DBUILD_TESTING=OFF >/dev/null
cmake --build "$CATCH_BLD" -j "$MAYHEM_JOBS" >/dev/null
UNIT_TESTS=(CigarTest SampleSheetTests bed_file_test PafUtilsTest ModelMetadataTest ModelKitsTest
            SequenceUtilsTest StringUtilsTest SecondaryWindowTest TestUtils)
UNIT_FLAGS=("${CXXSTD[@]}" -O1 $COVERAGE_FLAGS -DCATCH_CONFIG_PREFIX_ALL=1 -Wno-macro-redefined -DDORADO_ENABLE_BENCHMARK_TESTS=0
            -I"$SRC/tests" -I"$CATCH_SRC/src" -I"$CATCH_BLD/generated-includes" "${INCS[@]}")
mkdir -p "$OUT/unit"
upids=()
for t in "${UNIT_TESTS[@]}"; do
  ( "$CXX" "${UNIT_FLAGS[@]}" -I"$U/secondary/consensus/include" -c "$SRC/tests/$t.cpp" -o "$OUT/unit/$t.o" ) & upids+=($!)
done
# Test-only, torch-free upstream sources SecondaryWindowTest needs beyond LIB_SRCS.
for s in secondary/common/window.cpp secondary/consensus/window_utils.cpp; do
  ( "$CXX" "${UNIT_FLAGS[@]}" -I"$U/secondary/consensus/include" -c "$U/$s" \
      -o "$OUT/unit/lib_$(echo "$s" | tr '/' '_').o" ) & upids+=($!)
done
for p in "${upids[@]}"; do wait "$p"; done
# SequenceUtilsTest's compute_overlap case maps with minimap2: build its library sources from the
# ont-minimap2 submodule (Makefile OBJS, sse2only variant), normal flags, test binary only.
MM2="$T/ont-minimap2/src/3rdparty/minimap2"
mkdir -p "$OUT/mm2"
for c in kthread kalloc misc bseq sketch sdust options index lchain align hit seed jump map format pe \
         esterr splitidx ksw2_ll_sse ksw2_extz2_sse ksw2_extd2_sse ksw2_exts2_sse; do
  ( "$CC" -O1 -g -msse4.1 -DHAVE_KALLOC -w -I"$MM2" -c "$MM2/$c.c" -o "$OUT/mm2/$c.o" ) & upids+=($!)
done
for p in "${upids[@]}"; do wait "$p"; done
"$CXX" -O1 $COVERAGE_FLAGS "$OUT"/unit/*.o $(ls "$OUT"/test/*_*.o) "$OUT"/mm2/*.o \
    "$CATCH_BLD/src/libCatch2Main.a" "$CATCH_BLD/src/libCatch2.a" -l:libz.a "${LDGC[@]}" \
    -o "$OUT/dorado_unit_tests"
echo "build.sh: done"
