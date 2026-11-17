# Direct-mapped cache controller -- build / simulate helpers.
# Run from the repository root.  Requires Icarus Verilog (iverilog, vvp).

RTL      := rtl/main_memory.v rtl/cache_memory.v rtl/cache_controller.v rtl/cache_top.v
TB       := testbench/cache_tb.v
BUILD    := build
IVFLAGS  := -g2001 -Wall
LATENCIES:= 1 2 4 8

.PHONY: all phase1 phase1-all phase2 phase2-reports report audit final lat-sweep lint-rtl mutation yosys trace clean

all: phase1

$(BUILD):
	mkdir -p $(BUILD)

# --- Phase 1: compile (log saved), simulate default latency, save VCD + log ---
phase1: | $(BUILD)
	@echo "# iverilog: $$(iverilog -V 2>&1 | head -1)"  > results/phase1_compile_log.txt
	@echo "# vvp:      $$(vvp -V 2>&1 | head -1)"       >> results/phase1_compile_log.txt
	@echo "# command:  iverilog $(IVFLAGS) -s cache_tb -o $(BUILD)/cache_tb.vvp $(TB) $(RTL)" >> results/phase1_compile_log.txt
	iverilog $(IVFLAGS) -s cache_tb -o $(BUILD)/cache_tb.vvp $(TB) $(RTL) >> results/phase1_compile_log.txt 2>&1; \
	  rc=$$?; echo "# iverilog exit code: $$rc" >> results/phase1_compile_log.txt; cat results/phase1_compile_log.txt; exit $$rc
	vvp $(BUILD)/cache_tb.vvp +vcd=results/phase1_waveform.vcd | tee results/phase1_test_results.txt
	@grep -q "RESULT: ALL TESTS PASSED" results/phase1_test_results.txt

# --- Repeat the testbench at several main-memory latencies (no VCD) ---
lat-sweep: | $(BUILD)
	@set -e; for L in $(LATENCIES); do \
	  iverilog $(IVFLAGS) -s cache_tb -P cache_tb.MEM_LATENCY=$$L -o $(BUILD)/cache_tb_L$$L.vvp $(TB) $(RTL); \
	  vvp $(BUILD)/cache_tb_L$$L.vvp +novcd | grep -E "SUMMARY|RESULT|FAIL|MONITOR"; \
	done | tee results/phase1_latency_sweep.txt

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
	python3 -I scripts/audit_checks.py | tee results/final_audit_checks.txt

# --- Everything, from a clean tree: Phase 1 + Phase 2 regression, report, audit ---
final: phase1-all phase2 report audit

clean:
	rm -rf $(BUILD)

yosys:
	sh scripts/yosys_check.sh | tee results/phase1_yosys_check.txt

# --- Text trace of the Phase 1 VCD (evidence; not a waveform-viewer screenshot) ---
trace:
	python3 -I scripts/vcd_trace.py results/phase1_waveform.vcd > results/phase1_waveform_trace.txt

# --- Everything Phase 1 produces, from a clean tree ---
phase1-all: clean phase1 lat-sweep mutation yosys trace

mutation: | $(BUILD)
	python3 -I scripts/mutation_check.py . $(BUILD)/mutants | tee results/phase1_mutation_results.txt
