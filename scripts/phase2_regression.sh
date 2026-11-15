#!/bin/sh
# Phase 2 full regression (repo root).  Re-creates every Phase 2 evidence file:
#   results/complete_test_results.txt   results/phase2_latency_sweep.txt
#   results/phase2_mutation_results.txt results/reference_model_results.txt
#   results/performance_metrics.csv     results/synthesis_review_raw.txt
#   results/waveforms/*.vcd             (screenshots are produced separately, see docs/verification_strategy.md)
set -e
mkdir -p build results/waveforms
RTL="rtl/main_memory.v rtl/cache_memory.v rtl/cache_controller.v rtl/cache_top.v"
FLAGS="-g2001 -Wall -I testbench"
LATS="0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 32 64 100 255 1000"
EXH_LATS=" 1 2 4 "
VL_LATS="2 3 8 16 40"

echo "[1/6] compile warnings check (all testbenches, -Wall)"
: > build/compile_warnings.txt
for t in cache_tb cache_tb_directed cache_tb_vec; do
  case $t in cache_tb) f="testbench/cache_tb.v";; cache_tb_directed) f="testbench/cache_tb_directed.v";; cache_tb_vec) f="testbench/cache_tb_vec.v testbench/wave_probe.v";; esac
  iverilog $FLAGS -s $t -o build/w_$t.vvp $f $RTL >> build/compile_warnings.txt 2>&1
done
iverilog $FLAGS -DVARLAT -s cache_tb_directed -o build/w_vl.vvp testbench/cache_tb_directed.v testbench/cache_top_varlat.v rtl/cache_controller.v rtl/cache_memory.v >> build/compile_warnings.txt 2>&1
echo "      compiler output lines: $(wc -l < build/compile_warnings.txt)"

echo "[2/6] directed testbench, fixed latency sweep"
: > results/phase2_latency_sweep.txt
printf "%-12s %-10s %-7s %-14s %-14s %-9s %s\n" "memory" "exhaustive" "tests" "tests_failed" "checks_failed" "result" "measured cycles hit/rmiss/whit/wmiss" >> results/phase2_latency_sweep.txt
for L in $LATS; do
  E=0; case "$EXH_LATS" in *" $L "*) E=1;; esac
  iverilog $FLAGS -s cache_tb_directed -P cache_tb_directed.MEM_LATENCY=$L -P cache_tb_directed.EXHAUSTIVE=$E -o build/d_$L.vvp testbench/cache_tb_directed.v $RTL
  vvp build/d_$L.vvp > build/d_L$L.log 2>&1
  S=$(grep "SUMMARY" build/d_L$L.log | sed 's/.*TESTS=\([0-9]*\) TESTS_FAILED=\([0-9]*\) CHECKS_PASS=\([0-9]*\) CHECKS_FAIL=\([0-9]*\).*/\1 \2 \4/')
  R=$(grep "^RESULT" build/d_L$L.log | sed 's/RESULT: //')
  C=$(grep LATENCY_CSV build/d_L$L.log | cut -d, -f3-6 | tr ',' '/')
  set -- $S
  printf "%-12s %-10s %-7s %-14s %-14s %-9s %s\n" "L=$L" "$E" "$1" "$2" "$3" "$( [ "$R" = "ALL TESTS PASSED" ] && echo PASS || echo FAIL )" "$C" >> results/phase2_latency_sweep.txt
done
echo "[3/6] directed testbench, variable (pseudo-random) memory latency"
printf "\n%-14s %-7s %-14s %-14s %-9s %s\n" "memory" "tests" "tests_failed" "checks_failed" "result" "measured memory latency histogram (cycles:count)" >> results/phase2_latency_sweep.txt
for L in $VL_LATS; do
  iverilog $FLAGS -DVARLAT -s cache_tb_directed -P cache_tb_directed.MEM_LATENCY=$L -P cache_tb_directed.EXHAUSTIVE=0 -o build/v_$L.vvp testbench/cache_tb_directed.v testbench/cache_top_varlat.v rtl/cache_controller.v rtl/cache_memory.v
  vvp build/v_$L.vvp > build/v_L$L.log 2>&1
  S=$(grep "SUMMARY" build/v_L$L.log | sed 's/.*TESTS=\([0-9]*\) TESTS_FAILED=\([0-9]*\) CHECKS_PASS=\([0-9]*\) CHECKS_FAIL=\([0-9]*\).*/\1 \2 \4/')
  R=$(grep "^RESULT" build/v_L$L.log | sed 's/RESULT: //')
  H=$(grep MEMLAT_HIST build/v_L$L.log | awk -F, '{printf "%s:%s ", $2, $3}')
  set -- $S
  printf "%-14s %-7s %-14s %-14s %-9s %s\n" "random 1..$L" "$1" "$2" "$3" "$( [ "$R" = "ALL TESTS PASSED" ] && echo PASS || echo FAIL )" "$H" >> results/phase2_latency_sweep.txt
done
cat results/phase2_latency_sweep.txt
if grep -q FAIL results/phase2_latency_sweep.txt; then echo "SWEEP HAS FAILURES"; exit 1; fi

echo "[4/6] reference-model + randomized regression"
python3 -I verification/randomized_tests.py > build/reference_regression.log 2>&1 || { cat build/reference_regression.log; exit 1; }
tail -4 build/reference_regression.log

echo "[5/6] mutation check (Phase 1 + Phase 2 testbenches)"
python3 -I scripts/mutation_check_p2.py . build/mutants_p2 > results/phase2_mutation_results.txt 2>&1 || { cat results/phase2_mutation_results.txt; exit 1; }
tail -3 results/phase2_mutation_results.txt

echo "[6/6] waveform VCDs, synthesis/lint review"
iverilog $FLAGS -s cache_tb_vec -P cache_tb_vec.MEM_LATENCY=4 -o build/vec4.vvp testbench/cache_tb_vec.v testbench/wave_probe.v $RTL
for n in wave_cold_miss_refill wave_cache_hit wave_conflict_replace wave_write_hit wave_write_miss_alloc wave_back_to_back; do
  vvp build/vec4.vvp +vec=verification/test_vectors/$n.vec +out=build/$n.out +vcd=results/waveforms/$n.vcd > build/$n.log 2>&1 || { cat build/$n.log; exit 1; }
  grep -q "^RESULT: ALL TESTS PASSED" build/$n.log || { cat build/$n.log; exit 1; }
  grep -E "^RESULT" build/$n.log
done
sh scripts/synthesis_review.sh > results/synthesis_review_raw.txt 2>&1 || { cat results/synthesis_review_raw.txt; exit 1; }
echo "synthesis review: exit 0"
echo "PHASE 2 REGRESSION COMPLETE"
