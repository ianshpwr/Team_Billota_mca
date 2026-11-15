# Direct-mapped cache controller -- build / simulate helpers.
# Run from the repository root.  Requires Icarus Verilog (iverilog, vvp).

RTL      := rtl/main_memory.v rtl/cache_memory.v rtl/cache_controller.v rtl/cache_top.v
TB       := testbench/cache_tb.v
BUILD    := build
IVFLAGS  := -g2001 -Wall
LATENCIES:= 1 2 4 8

.PHONY: all test-python phase1 phase1-all phase2 phase2-reports report audit final lat-sweep lint-rtl mutation yosys trace clean

all: phase1

# Fast verification of the independent Python tools; no HDL tools required.
test-python:
	python3 -I -m unittest discover -s verification/tests -v

$(BUILD):
	mkdir -p $(BUILD)

# --- Phase 1: compile (log saved), simulate default latency, save VCD + log ---
phase1: | $(BUILD)
	@echo "# iverilog: $$(iverilog -V 2>&1 | head -1)"  > results/phase1_compile_log.txt
	@echo "# vvp:      $$(vvp -V 2>&1 | head -1)"       >> results/phase1_compile_log.txt
	@echo "# command:  iverilog $(IVFLAGS) -s cache_tb -o $(BUILD)/cache_tb.vvp $(TB) $(RTL)" >> results/phase1_compile_log.txt
	iverilog $(IVFLAGS) -s cache_tb -o $(BUILD)/cache_tb.vvp $(TB) $(RTL) >> results/phase1_compile_log.txt 2>&1; \
	  rc=$$?; echo "# iverilog exit code: $$rc" >> results/phase1_compile_log.txt; cat results/phase1_compile_log.txt; exit $$rc
	vvp $(BUILD)/cache_tb.vvp +vcd=results/phase1_waveform.vcd > results/phase1_test_results.txt 2>&1 || { cat results/phase1_test_results.txt; exit 1; }
	@cat results/phase1_test_results.txt
	@grep -q "RESULT: ALL TESTS PASSED" results/phase1_test_results.txt

# --- Repeat the testbench at several main-memory latencies (no VCD) ---
lat-sweep: | $(BUILD)
	@set -e; : > results/phase1_latency_sweep.txt; for L in $(LATENCIES); do \
	  iverilog $(IVFLAGS) -s cache_tb -P cache_tb.MEM_LATENCY=$$L -o $(BUILD)/cache_tb_L$$L.vvp $(TB) $(RTL); \
	  vvp $(BUILD)/cache_tb_L$$L.vvp +novcd > $(BUILD)/lat_sweep_L$$L.log 2>&1 || { cat $(BUILD)/lat_sweep_L$$L.log; exit 1; }; \
	  grep -E "SUMMARY|RESULT|FAIL|MONITOR" $(BUILD)/lat_sweep_L$$L.log >> results/phase1_latency_sweep.txt; \
	  grep -q "RESULT: ALL TESTS PASSED" $(BUILD)/lat_sweep_L$$L.log || { cat $(BUILD)/lat_sweep_L$$L.log; exit 1; }; \
	done; cat results/phase1_latency_sweep.txt

# --- RTL-only elaboration check (no testbench) ---
lint-rtl:
	iverilog $(IVFLAGS) -s cache_top -o /dev/null $(RTL)

# --- Phase 2: full regression (directed sweep, variable latency, reference model,
#     mutation, waveform VCDs, synthesis/lint) and the generated reports ---
phase2:
	sh scripts/phase2_regression.sh
	$(MAKE) phase2-reports

phase2-reports:
	python3 -I scripts/gen_phase2_reports.py

# --- Phase 3: report PDF (needs tectonic; figures need the optional .venv with matplotlib) ---
report:
	@if [ -x .venv/bin/python ]; then .venv/bin/python scripts/make_report_figures.py; else echo "(no .venv: keeping committed figure PNGs)"; fi
	python3 -I scripts/gen_report_numbers.py
	cd docs && tectonic IEEE_Project_Report.tex

# --- Mechanical repository audit (structure, links, secrets, consistency, over-claims) ---
audit:
	python3 -I scripts/audit_checks.py > results/final_audit_checks.txt 2>&1 || { cat results/final_audit_checks.txt; exit 1; }
	@cat results/final_audit_checks.txt

# --- Everything, from a clean tree: Phase 1 + Phase 2 regression, report, audit ---
final:
	$(MAKE) phase1-all
	$(MAKE) phase2
	$(MAKE) report
	$(MAKE) audit

clean:
	rm -rf $(BUILD)

yosys:
	sh scripts/yosys_check.sh > results/phase1_yosys_check.txt 2>&1 || { cat results/phase1_yosys_check.txt; exit 1; }
	@cat results/phase1_yosys_check.txt

# --- Text trace of the Phase 1 VCD (evidence; not a waveform-viewer screenshot) ---
trace:
	python3 -I scripts/vcd_trace.py results/phase1_waveform.vcd > results/phase1_waveform_trace.txt

# --- Everything Phase 1 produces, from a clean tree ---
phase1-all:
	$(MAKE) clean
	$(MAKE) phase1
	$(MAKE) lat-sweep mutation yosys trace

mutation: | $(BUILD)
	python3 -I scripts/mutation_check.py . $(BUILD)/mutants > results/phase1_mutation_results.txt 2>&1 || { cat results/phase1_mutation_results.txt; exit 1; }
	@cat results/phase1_mutation_results.txt
