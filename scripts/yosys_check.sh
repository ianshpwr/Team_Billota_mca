#!/bin/sh
# Quick Yosys synthesizability / latch check of the synthesizable modules.
# main_memory.v is a simulation model and is deliberately excluded.
# Usage (from repo root): sh scripts/yosys_check.sh
set -e
mkdir -p build
yosys -V
for top in cache_controller cache_memory; do
  echo "=================== generic synth + check: $top ==================="
  yosys -p "read_verilog rtl/cache_controller.v rtl/cache_memory.v; \
            hierarchy -check -top $top; proc; opt; check -assert; synth -top $top; stat" \
        > build/yosys_$top.log 2>&1 && echo "yosys exit: 0" || { echo "yosys FAILED"; tail -20 build/yosys_$top.log; exit 1; }
  echo "-- warnings/errors in log:"; grep -Ei "warning|error" build/yosys_$top.log || echo "(none)"
  echo "-- latch cells:"; grep -Ei '\$_?d?latch' build/yosys_$top.log | grep -v "PROC_DLATCH\|No latch" || echo "(none)"
  echo "-- resource estimate (generic gate-level, NOT an FPGA/ASIC result):"
  sed -n '/^8. Printing statistics/,/^End of script/p' build/yosys_$top.log | sed -e '/^$/d;/^End of script/d'
done
