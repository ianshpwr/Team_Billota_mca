#!/bin/sh
# Phase 2 synthesis / lint review. Output is the raw evidence behind results/synthesis_review.md.
# Everything here is a SYNTHESIS-TOOL ESTIMATE on generic or iCE40 logic. It is not
# place-and-route, has no timing analysis, and is not an FPGA/ASIC measurement.
# main_memory.v is a simulation model and is blackboxed / excluded.
# Usage (repo root): sh scripts/synthesis_review.sh
set -e
mkdir -p build
echo "### tool versions"; yosys -V; verilator --version; iverilog -V 2>&1 | head -1
echo
echo "### 1. Verilator lint (-Wall) per synthesizable module"
for top in cache_controller cache_memory; do
  echo "--- $top"; verilator --lint-only -Wall --top-module $top rtl/$top.v 2>&1 | grep -E "%Warning|%Error" || echo "no warnings"
done
echo "--- cache_top (+ cache_controller, cache_memory, main_memory model)"
verilator --lint-only -Wall --top-module cache_top rtl/cache_top.v rtl/cache_controller.v rtl/cache_memory.v rtl/main_memory.v 2>&1 | grep -E "%Warning|%Error" || echo "no warnings"
echo
echo "### 2. Yosys: elaboration, proc, check -assert (latches / multiple drivers / loops), per module"
for top in cache_controller cache_memory; do
  echo "--- $top"
  yosys -p "read_verilog rtl/cache_controller.v rtl/cache_memory.v; hierarchy -check -top $top; proc; opt_clean; check -assert; stat" > build/ys_check_$top.log 2>&1 && echo "exit 0" || { echo "FAILED"; tail -15 build/ys_check_$top.log; exit 1; }
  grep -E "Warning|ERROR|latch|Found and reported" build/ys_check_$top.log | grep -v "PROC_DLATCH\|No latch" || true
done
echo
echo "### 3. Yosys top level (cache_top) with the simulation memory model blackboxed"
yosys -p "read_verilog rtl/cache_top.v rtl/cache_controller.v rtl/cache_memory.v; read_verilog -lib rtl/main_memory.v; hierarchy -check -top cache_top; proc; opt_clean; check -assert; stat" > build/ys_top.log 2>&1 && echo "exit 0" || { echo "FAILED"; tail -20 build/ys_top.log; exit 1; }
grep -E "Warning|ERROR|Found and reported|=== " build/ys_top.log | grep -v "PROC_DLATCH\|No latch" || true
echo
echo "### 4. FSM extraction (cache_controller): detected states and transitions"
yosys -p "read_verilog rtl/cache_controller.v; hierarchy -top cache_controller; proc; opt_clean; fsm_detect; fsm_extract; fsm_info" > build/ys_fsm.log 2>&1 || { tail -20 build/ys_fsm.log; exit 1; }
grep -A3 -E "Not marking|Found FSM|Extracting FSM|FSM state register" build/ys_fsm.log | grep -v "^--$" | head -20
echo
echo "### 5. Generic technology-independent synthesis: flip-flop / gate counts"
for top in cache_controller cache_memory; do
  echo "--- $top"
  yosys -p "read_verilog rtl/cache_controller.v rtl/cache_memory.v; hierarchy -top $top; synth -top $top; stat" > build/ys_synth_$top.log 2>&1
  awk '/Printing statistics/{buf=""} {buf=buf"\n"$0} END{print buf}' build/ys_synth_$top.log | grep -E '=== |cells$|^ +[0-9]+ +[$]_' | head -24
done
echo
echo "### 6. iCE40 LUT4 mapping estimate (technology mapping only; no place-and-route, no timing)"
for top in cache_controller cache_memory; do
  echo "--- $top"
  yosys -p "read_verilog rtl/cache_controller.v rtl/cache_memory.v; hierarchy -top $top; synth_ice40 -top $top; stat" > build/ys_ice40_$top.log 2>&1 || { tail -15 build/ys_ice40_$top.log; exit 1; }
  grep -E "SB_LUT4|SB_DFF|SB_CARRY|SB_RAM|cells$|Number of cells" build/ys_ice40_$top.log | tail -12
done
echo
echo "### 7. Yosys warnings (all runs, unfiltered, de-duplicated)"
cat build/ys_*.log | grep -i "warning" | sort | uniq -c | sort -rn || true
