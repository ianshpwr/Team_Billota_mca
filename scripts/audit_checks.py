#!/usr/bin/env python3
"""Mechanical repository audit (part of the final audit, plan 3.4 / 3.7).
Checks: structure vs the plan, local markdown links, secret patterns, temporary files, PDF presence,
figure files, traceability cross-references, result consistency, and over-claim wording.
Usage (repo root): python3 -I scripts/audit_checks.py   -> prints a table, exit code 1 on any FAIL."""
import os, re, subprocess, sys

ROOT = os.getcwd()
res = []
def check(name, ok, detail=""):
    res.append((name, ok, detail))

def exists(p): return os.path.exists(os.path.join(ROOT, p))
def read(p): return open(os.path.join(ROOT, p), errors="replace").read()

# 1. structure (plan section 3.3 + management files)
required = """README.md LICENSE .gitignore Makefile rtl/cache_controller.v rtl/cache_memory.v rtl/main_memory.v rtl/cache_top.v
testbench/cache_tb.v testbench/cache_tb_directed.v testbench/cache_tb_vec.v testbench/tb_common.vh
verification/reference_model.py verification/randomized_tests.py verification/performance.py verification/test_vectors
docs/IEEE_Project_Report.tex docs/IEEE_Project_Report.pdf docs/architecture.md docs/address_decomposition.md docs/fsm_design.md
docs/module_interfaces.md docs/verification_strategy.md docs/individual_contributions.md docs/interview_questions.md docs/project_defense.md
docs/git_workflow.md docs/final_audit.md diagrams/block_diagram.png diagrams/fsm_diagram.png
results/phase1_test_results.txt results/phase1_compile_log.txt results/phase1_waveform.vcd results/complete_test_results.txt
results/coverage_summary.md results/performance_metrics.csv results/reference_model_results.txt results/synthesis_review.md results/waveforms
video/prototype_video_link.md video/demo_script.md video/recording_checklist.md
DEVELOPMENT_LOG.md PHASE_STATUS.md REQUIREMENTS_TRACEABILITY.md TEST_RESULTS.md""".split()
missing = [p for p in required if not exists(p)]
check("required files/directories present (%d)" % len(required), not missing, ", ".join(missing))
shots = [f for f in os.listdir("results/waveforms") if f.endswith(".png")] if exists("results/waveforms") else []
check("six waveform screenshots present", len(shots) >= 6, "%d png" % len(shots))

# 2. local markdown links
bad = []
mds = [p for p in ["README.md"] + ["docs/" + f for f in os.listdir("docs") if f.endswith(".md")] + ["video/" + f for f in os.listdir("video") if f.endswith(".md")]
       + ["results/waveforms/README.md", "results/coverage_summary.md", "results/synthesis_review.md", "results/performance_summary.md", "TEST_RESULTS.md",
          "PHASE_STATUS.md", "REQUIREMENTS_TRACEABILITY.md", "DEVELOPMENT_LOG.md"] if exists(p)]
for md in mds:
    base = os.path.dirname(md)
    for m in re.finditer(r"\]\(([^)#\s]+)(#[^)]*)?\)", read(md)):
        t = m.group(1)
        if re.match(r"[a-z]+:", t): continue
        if not os.path.exists(os.path.normpath(os.path.join(ROOT, base, t))): bad.append("%s -> %s" % (md, t))
check("local markdown links resolve (%d files scanned)" % len(mds), not bad, "; ".join(bad[:8]))

# 3. secrets
pats = [r"AKIA[0-9A-Z]{16}", r"-----BEGIN [A-Z ]*PRIVATE KEY-----", r"ghp_[A-Za-z0-9]{30,}", r"xox[baprs]-[A-Za-z0-9-]{10,}",
        r"(?i)(password|passwd|api[_-]?key|secret|token)\s*[:=]\s*['\"][^'\"]{6,}['\"]", r"sk-[A-Za-z0-9]{20,}"]
skip = (".git", ".venv", "build", ".playwright-mcp")
hits = []
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in skip]
    for f in fn:
        p = os.path.join(dp, f)
        if f.endswith((".png", ".pdf", ".vcd", ".ico", ".wasm")): continue
        try: t = open(p, errors="ignore").read()
        except Exception: continue
        if f in ("audit_checks.py",): continue
        for pt in pats:
            if re.search(pt, t): hits.append("%s:%s" % (os.path.relpath(p, ROOT), pt[:20]))
check("no credentials/secret patterns in tracked-type files", not hits, "; ".join(hits[:5]))

# 4. temp files
tmp = []
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in skip + ("__pycache__",)]
    for f in fn:
        if f.endswith((".vvp", ".o", ".swp", ".bak", ".orig", ".aux", ".log")) or f in ("a.out",): tmp.append(os.path.relpath(os.path.join(dp, f), ROOT))
check("no stray temporary build files outside ignored dirs", not tmp, ", ".join(tmp[:6]))
ign = subprocess.run(["git", "check-ignore", "build", ".venv", ".playwright-mcp"], capture_output=True, text=True).stdout.split()
check(".gitignore covers build/, .venv/, .playwright-mcp/", set(ign) >= {"build", ".venv", ".playwright-mcp"}, " ".join(ign))
big = [(os.path.relpath(os.path.join(dp, f), ROOT), os.path.getsize(os.path.join(dp, f))) for dp, dn, fn in os.walk(ROOT) if not any(s in dp for s in skip) for f in fn if os.path.getsize(os.path.join(dp, f)) > 2_000_000]
check("no tracked-type file larger than 2 MB", not big, str(big))

# 5. PDF
if exists("docs/IEEE_Project_Report.pdf"):
    d = open("docs/IEEE_Project_Report.pdf", "rb").read()
    pages = "?"
    try:
        out = subprocess.run(["pdfinfo", "docs/IEEE_Project_Report.pdf"], capture_output=True, text=True).stdout
        m = re.search(r"Pages:\s+(\d+)", out)
        if m: pages = m.group(1)
    except FileNotFoundError:
        pass
    check("report PDF valid header and >= 5 pages (pdfinfo)", d.startswith(b"%PDF") and pages.isdigit() and int(pages) >= 5, "pages=%s size=%dKB" % (pages, len(d) // 1024))
tex = read("docs/IEEE_Project_Report.tex")
figs = re.findall(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}", tex)
check("all report figures exist (%d)" % len(figs), all(os.path.exists(os.path.join(ROOT, "docs", f)) for f in figs), ", ".join(f for f in figs if not os.path.exists(os.path.join(ROOT, "docs", f))))
for sec in ["Introduction", "Literature Review", "Problem Statement", "Objectives", "Proposed Solution", "System Architecture", "Address Mapping Methodology",
            "Cache Controller FSM", "RTL Implementation", "Verification Methodology", "Results and Discussion", "Performance Analysis", "Individual Contributions",
            "Limitations", "Future Scope", "Conclusion"]:
    if "\\section{" + sec + "}" not in tex: check("report section: " + sec, False)
check("report has abstract, keywords, references", all(k in tex for k in ["\\begin{abstract}", "IEEEkeywords", "thebibliography"]))
check("report cites 10 references, all cited in text", len(re.findall(r"\\bibitem", tex)) == 10 and all(("\\cite{%s}" % k.split("}")[0]) or True for k in re.findall(r"\\bibitem\{([^}]+)\}", tex))
      and all(re.search(r"\\cite\{[^}]*\b%s\b" % k, tex) for k in re.findall(r"\\bibitem\{([^}]+)\}", tex)))

# 6. traceability cross-references
tr, tres = read("REQUIREMENTS_TRACEABILITY.md"), read("TEST_RESULTS.md")
ids = set(re.findall(r"\b([DEL]-\d\d[A-Z]?|C-01|P1-\d\d)\b", tr))
miss_ids = sorted(i for i in ids if i not in tres)
check("every test ID in the traceability matrix exists in TEST_RESULTS.md (%d IDs)" % len(ids), not miss_ids, ", ".join(miss_ids))
for m in re.finditer(r"`((?:results|docs|testbench|verification|scripts|rtl)/[A-Za-z0-9_./*-]+)`", tr):
    p = m.group(1)
    if "*" in p or p.endswith("/"): continue
check("traceability evidence paths exist", all(exists(m.group(1)) for m in re.finditer(r"`((?:results|docs|testbench|verification|scripts|rtl)/[A-Za-z0-9_./-]+\.[a-z]+)`", tr)),
      ", ".join(m.group(1) for m in re.finditer(r"`((?:results|docs|testbench|verification|scripts|rtl)/[A-Za-z0-9_./-]+\.[a-z]+)`", tr) if not exists(m.group(1)))[:300])

# 7. result consistency
ct = read("results/complete_test_results.txt")
check("complete_test_results: ALL TESTS PASSED and 0 failed tests", "RESULT: ALL TESTS PASSED" in ct and "TESTS_FAILED=0" in ct)
check("reference model: ALL COMPARISONS PASSED", "RESULT: ALL COMPARISONS PASSED" in read("results/reference_model_results.txt"))
sw = read("results/phase2_latency_sweep.txt")
check("latency sweep: no FAIL rows", "FAIL" not in sw.replace("tests_failed", "").replace("checks_failed", ""))
check("TEST_RESULTS.md: no FAIL entries", not re.search(r"\| FAIL", tres))
check("Phase 1 evidence intact (122 checks, 0 failures)", "PASS=122 FAIL=0" in read("results/phase1_test_results.txt"))
check("mutation: Phase 2 bench detects all mutants", "not detected by the Phase 2 directed testbench: 0" in read("results/phase2_mutation_results.txt"))

# 8. over-claim scan
claims = []
for p in mds + ["docs/IEEE_Project_Report.tex"]:
    t = read(p)
    for m in re.finditer(r"(?i)\b(\d+(\.\d+)?\s*(MHz|GHz)|fmax|timing closure|tested on (an )?fpga|ran on (an )?fpga|video (was|has been) recorded)\b", t):
        ctx = t[max(0, m.start() - 60): m.end() + 40].replace("\n", " ")
        if not re.search(r"(?i)\b(no|not|never|without|nor|neither|unless|until)\b", ctx): claims.append("%s: ...%s..." % (p, ctx))
check("no unqualified frequency / FPGA-run / video-recorded claims", not claims, " | ".join(claims[:3]))

# 9. placeholders (informational)
todo = sum(len(re.findall(r"\[TODO|\\todo\{", read(p))) for p in ["README.md", "docs/individual_contributions.md", "docs/IEEE_Project_Report.tex", "video/prototype_video_link.md", "LICENSE"] if exists(p))
check("INFO: %d human-input placeholders remain (names, enrollment, URL, video, copyright)" % todo, True)

w = max(len(n) for n, _, _ in res)
for n, ok, d in res:
    print("%-4s %-*s %s" % ("PASS" if ok else "FAIL", w, n, ("- " + d) if d else ""))
fails = sum(1 for _, ok, _ in res if not ok)
print("\nAUDIT CHECKS: %d, FAILED: %d" % (len(res), fails))
sys.exit(1 if fails else 0)
