#!/usr/bin/env python3
"""Randomized + directed-vector regression: RTL (Icarus) vs the Python reference model.

For every (profile, seed, memory latency):
  1. generate a reproducible transaction file with random.Random(seed)
  2. simulate it on the DUT with testbench/cache_tb_vec.v  (log, memory dump)
  3. run verification/reference_model.py on the SAME file
  4. compare every transaction line (hit/miss, returned byte, latency, memory
     read/write counts), the final 16-line cache state and the full 64 KiB memory
Failing cases are preserved (vector, expected, actual) under
verification/test_vectors/failing/. Seeds, profiles and parameters are fixed in
this file, so the regression is exactly reproducible.

Usage (repo root):
  python3 -I verification/randomized_tests.py                  # full regression
  python3 -I verification/randomized_tests.py --quick          # small smoke subset
  python3 -I verification/randomized_tests.py --gen-static     # (re)write static vectors only
"""
import argparse, concurrent.futures as cf, csv, hashlib, os, random, shutil, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference_model as ref
import performance as perf

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BUILD = os.path.join(ROOT, "build", "rand")
VECDIR = os.path.join(ROOT, "verification", "test_vectors")
RTL = ["rtl/main_memory.v", "rtl/cache_memory.v", "rtl/cache_controller.v", "rtl/cache_top.v"]
TB = ["testbench/cache_tb_vec.v", "testbench/wave_probe.v"]

DEFAULT_SEEDS = [1, 2, 3, 4, 5, 6]
DEFAULT_LATS = [1, 2, 3, 4, 8, 16]
VARLAT_MAX = 8
DEFAULT_TXNS = 2500


def word(op, addr=0, wd=0):
    return "%02x%04x%02x" % (op, addr & 0xFFFF, wd & 0xFF)


# ----------------------------------------------------------------- generators
def gen_uniform(r, n):
    return [word(1 if r.random() < 0.30 else 0, r.randrange(65536), r.randrange(256)) for _ in range(n)]


def gen_hotset(r, n):
    pool = [r.randrange(65536) for _ in range(24)]
    out = []
    for _ in range(n):
        a = r.choice(pool) if r.random() < 0.85 else r.randrange(65536)
        out.append(word(1 if r.random() < 0.35 else 0, a, r.randrange(256)))
    return out


def gen_conflict(r, n):
    idxs = r.sample(range(16), 3)
    tags = r.sample(range(1024), 6)
    out = []
    for _ in range(n):
        a = (r.choice(tags) << 6) | (r.choice(idxs) << 2) | r.randrange(4)
        out.append(word(1 if r.random() < 0.30 else 0, a, r.randrange(256)))
    return out


def gen_sequential(r, n):
    out = []
    while len(out) < n:
        a = r.randrange(65536); stride = 1 if r.random() < 0.8 else 4
        for _ in range(r.randrange(8, 65)):
            out.append(word(1 if r.random() < 0.20 else 0, a, r.randrange(256)))
            a = (a + stride) & 0xFFFF
    return out[:n]


def gen_write_heavy(r, n):
    base = r.randrange(0, 65536 - 256)
    return [word(1 if r.random() < 0.80 else 0, base + r.randrange(256), r.randrange(256)) for _ in range(n)]


def gen_mixed_reset(r, n):
    base = r.randrange(0, 65536 - 2048)
    out = []
    for _ in range(n):
        x = r.random()
        if x < 0.03:   out.append(word(ref.RESET))
        elif x < 0.06: out.append(word(ref.IDLE, 0, r.randrange(1, 6)))
        else:          out.append(word(1 if r.random() < 0.35 else 0, base + r.randrange(2048), r.randrange(256)))
    return out


def gen_corners(r, n):
    pool = list(range(0, 8)) + list(range(0xFFF8, 0x10000)) + list(range(0x003C, 0x0044)) + list(range(0xFFC0, 0xFFC8)) \
         + [(t << 6) | (i << 2) | o for t in (0, 1, 0x200, 0x3FF, 0x155, 0x2AA) for i in (0, 15) for o in (0, 3)]
    return [word(1 if r.random() < 0.40 else 0, r.choice(pool), r.randrange(256)) for _ in range(n)]


def gen_tagbits(r, n):
    idx = r.randrange(16)
    tags = [0, 0x3FF] + [1 << b for b in range(10)] + [0x3FF ^ (1 << b) for b in range(10)]
    return [word(1 if r.random() < 0.30 else 0, (r.choice(tags) << 6) | (idx << 2) | r.randrange(4), r.randrange(256)) for _ in range(n)]


PROFILES = {
    "uniform": gen_uniform, "hotset": gen_hotset, "conflict": gen_conflict, "sequential": gen_sequential,
    "write_heavy": gen_write_heavy, "mixed_reset": gen_mixed_reset, "corners": gen_corners, "tagbits": gen_tagbits,
}


def make_vectors(profile, seed, n):
    r = random.Random(seed * 1000003 + sum(ord(c) for c in profile))
    return PROFILES[profile](r, n) + [word(ref.END)]


# --------------------------------------------------------------- static vectors
STATIC = {
    # waveform scenarios (also compared with the model)
    "wave_cold_miss_refill": [(0, 0x0004)],
    "wave_cache_hit":        [(0, 0x0004), (0, 0x0004), (0, 0x0005)],
    "wave_conflict_replace": [(0, 0x0004), (0, 0x0044), (0, 0x0004)],
    "wave_write_hit":        [(0, 0x0104), (1, 0x0105, 0xA1), (0, 0x0105)],
    "wave_write_miss_alloc": [(1, 0x0208, 0x55), (0, 0x0209), (0, 0x0208)],
    "wave_back_to_back":     [(0, 0x0050), (0, 0x0054), (0, 0x0058), (0, 0x0050), (0, 0x0051), (1, 0x0055, 0x77), (0, 0x0055)],
    # Phase 1 directed sequence replayed through the model
    "directed_phase1_sequence": [(0, 0x0004), (0, 0x0004), (0, 0x0005), (0, 0x0006), (0, 0x0007), (0, 0x0008), (0, 0x000A),
                                 (0, 0x0044), (0, 0x0045), (0, 0x0004), (0, 0x0009), (0, 0x0000), (0, 0xFFFF), (0, 0xFFFC),
                                 (1, 0x0102, 0xA5), (0, 0x0100), (0, 0x0101), (0, 0x0102), (0, 0x0103), (1, 0x0101, 0x3C),
                                 (0, 0x0101), (2,), (0, 0x0101)],
}


def write_static():
    os.makedirs(VECDIR, exist_ok=True)
    for name, ops in STATIC.items():
        with open(os.path.join(VECDIR, name + ".vec"), "w") as f:
            for o in ops:
                f.write(word(o[0], *(o[1:] if len(o) > 1 else ())) + "\n")
            f.write(word(ref.END) + "\n")


# ------------------------------------------------------------------- simulation
def compile_tb(lat, varlat=False):
    exe = os.path.join(BUILD, ("vl_%d" if varlat else "L%d") % lat + ".vvp")
    cmd = ["iverilog", "-g2001", "-I", "testbench", "-s", "cache_tb_vec", "-P", "cache_tb_vec.MEM_LATENCY=%d" % lat, "-o", exe]
    if varlat:
        cmd += ["-DVARLAT"] + TB + ["testbench/cache_top_varlat.v"] + [x for x in RTL if x.endswith(("cache_controller.v", "cache_memory.v"))]
    else:
        cmd += TB + RTL
    c = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if c.returncode:
        raise SystemExit("compile failed:\n" + c.stderr)
    return exe


def read_lines(p):
    return [l.rstrip("\n") for l in open(p) if l.strip()]


def run_case(exe, vecfile, tag, lat, varlat):
    out = os.path.join(BUILD, tag + ".actual")
    mem = os.path.join(BUILD, tag + ".mem")
    exp = os.path.join(BUILD, tag + ".expected")
    expm = os.path.join(BUILD, tag + ".expmem")
    sim = subprocess.run(["vvp", exe, "+vec=" + vecfile, "+out=" + out, "+memdump=" + mem], cwd=ROOT, capture_output=True, text=True)
    ref.run(vecfile, exp, expm, lat)
    a, e = read_lines(out), read_lines(exp)
    problems = []
    if "RESULT: ALL TESTS PASSED" not in sim.stdout:
        problems.append("DUT protocol monitor reported errors:\n" + "\n".join(l for l in sim.stdout.splitlines() if "MONITOR" in l)[:600])
    if len(a) != len(e):
        problems.append("line count differs: DUT %d vs model %d" % (len(a), len(e)))
    ncmp = 0
    for i, (x, y) in enumerate(zip(a, e)):
        ncmp += 1
        if varlat and x.startswith("T "):          # latency column not comparable for random memory latency
            xs, ys = x.split(), y.split(); xs[7] = ys[7] = "-"; x, y = " ".join(xs), " ".join(ys)
        if x != y:
            problems.append("line %d differs:\n   DUT  : %s\n   MODEL: %s" % (i, x, y)); break
    # memory image
    mm = [l.strip() for l in open(mem) if l.strip() and not l.startswith("//")]
    em = [l.strip() for l in open(expm) if l.strip()]
    if mm != em:
        bad = next((i for i, (p, q) in enumerate(zip(mm, em)) if p != q), None)
        problems.append("memory image differs (first at 0x%04x: DUT %s model %s)" % (bad or 0, mm[bad] if bad is not None else "?", em[bad] if bad is not None else "?"))
    return problems, a, ncmp, hashlib.sha256("\n".join(e).encode()).hexdigest()[:16]


def job(args):
    exe, vecfile, tag, lat, varlat, name, seed = args
    try:
        problems, actual, ncmp, h = run_case(exe, vecfile, tag, lat, varlat)
    except Exception as ex:                          # keep the regression running, report the failure
        problems, actual, ncmp, h = ["exception: %r" % ex], [], 0, "-"
    return dict(name=name, seed=seed, lat=lat, varlat=varlat, tag=tag, vec=vecfile, problems=problems, actual=actual, ncmp=ncmp, h=h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--gen-static", action="store_true")
    ap.add_argument("--txns", type=int, default=DEFAULT_TXNS)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2)))
    ap.add_argument("--rtl-dir", default=None, help="negative-control mode: use RTL copies from this directory (e.g. a mutant)")
    a = ap.parse_args()
    global RTL, VECDIR
    if a.rtl_dir:
        RTL = [os.path.join(a.rtl_dir, os.path.basename(x)) for x in RTL]
        a.quick = True
    write_static()
    if a.gen_static:
        print("static vectors written to", VECDIR); return 0
    seeds = [1, 2] if a.quick else DEFAULT_SEEDS
    lats = [1, 4] if a.quick else DEFAULT_LATS
    txns = 400 if a.quick else a.txns
    shutil.rmtree(BUILD, ignore_errors=True); os.makedirs(BUILD)
    t0 = time.time()
    exes = {L: compile_tb(L) for L in lats}
    exes_vl = compile_tb(VARLAT_MAX, varlat=True)

    jobs = []
    for prof in PROFILES:
        for seed in seeds:
            vf = os.path.join(BUILD, "%s_seed%d.vec" % (prof, seed))
            open(vf, "w").write("\n".join(make_vectors(prof, seed, txns)) + "\n")
            for L in lats:
                jobs.append((exes[L], vf, "%s_s%d_L%d" % (prof, seed, L), L, False, prof, seed))
            jobs.append((exes_vl, vf, "%s_s%d_VL%d" % (prof, seed, VARLAT_MAX), VARLAT_MAX, True, prof, seed))
    for name in STATIC:
        vf = os.path.join(VECDIR, name + ".vec")
        for L in ([4] if a.quick else [1, 4, 16]):
            jobs.append((exes.get(L) or compile_tb(L), vf, "%s_L%d" % (name, L), L, False, name, 0))

    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        results = list(ex.map(job, jobs))

    failed = [r for r in results if r["problems"]]
    faildir = os.path.join(BUILD, "failing") if a.rtl_dir else os.path.join(VECDIR, "failing")
    if failed:
        os.makedirs(faildir, exist_ok=True)
        for r in failed:
            for ext in ("actual", "expected"):
                shutil.copy(os.path.join(BUILD, r["tag"] + "." + ext), os.path.join(faildir, r["tag"] + "." + ext))
            shutil.copy(r["vec"], os.path.join(faildir, r["tag"] + ".vec"))

    # representative vectors + expected outputs (seed 1) are kept in the repo
    if not a.quick:
        for prof in PROFILES:
            src = os.path.join(BUILD, "%s_seed1.vec" % prof)
            shutil.copy(src, os.path.join(VECDIR, "rand_%s_seed1.vec" % prof))
            ref.run(src, os.path.join(VECDIR, "rand_%s_seed1.L4.expected" % prof), None, 4)

    # performance metrics from the ACTUAL DUT logs (fixed-latency runs only)
    rows = []
    for r in results:
        if not r["varlat"] and r["actual"] and not r["problems"]:
            m = perf.compute(perf.parse_log(r["actual"]), r["lat"], r["name"], r["seed"])
            if m: rows.append(m)
    rows.sort(key=lambda m: (m["workload"], m["mem_latency_L"], str(m["seed"])))
    if not a.quick:
        with open(os.path.join(ROOT, "results", "performance_metrics.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=perf.FIELDS); w.writeheader(); w.writerows(rows)

    # report
    lines = []
    lines.append("# Reference-model regression: RTL (Icarus Verilog) vs independent Python model")
    lines.append("# generated by verification/randomized_tests.py%s" % (" --quick" if a.quick else ""))
    lines.append("# python: %s" % sys.version.split()[0])
    lines.append("# iverilog: %s" % subprocess.run(["iverilog", "-V"], capture_output=True, text=True).stdout.splitlines()[0])
    lines.append("# profiles: %s" % ", ".join(PROFILES))
    lines.append("# seeds: %s   fixed memory latencies: %s   variable-latency (max %d, pseudo-random per transaction): yes" % (seeds, lats, VARLAT_MAX))
    lines.append("# transactions per random vector: %d   total runs: %d   elapsed: %.1fs" % (txns, len(results), time.time() - t0))
    lines.append("# compared per run: every transaction line (hit/miss, returned byte, latency [fixed-latency runs], memory reads/writes),")
    lines.append("#                   final 16-line cache state (valid, tag, data) and the full 64 KiB memory image")
    lines.append("")
    lines.append("%-26s %5s %-9s %7s %9s %-18s %s" % ("workload", "seed", "memory", "lines", "result", "model-output-sha", "note"))
    for r in results:
        mem = ("var<=%d" % r["lat"]) if r["varlat"] else "L=%d" % r["lat"]
        lines.append("%-26s %5s %-9s %7d %9s %-18s %s" % (r["name"], r["seed"], mem, r["ncmp"], "FAIL" if r["problems"] else "PASS", r["h"],
                                                       "" if not r["problems"] else r["problems"][0].splitlines()[0]))
    lines.append("")
    tot_txn = sum(m["total_requests"] for m in rows)
    lines.append("TOTAL runs=%d  passed=%d  failed=%d  (fixed-latency DUT transactions compared against the model: %d)" % (len(results), len(results) - len(failed), len(failed), tot_txn))
    for r in failed:
        lines.append("")
        lines.append("FAILED CASE %s (vector preserved in verification/test_vectors/failing/)" % r["tag"])
        for p in r["problems"]: lines.append("  " + p.replace("\n", "\n  "))
    lines.append("RESULT: %s" % ("ALL COMPARISONS PASSED" if not failed else "MISMATCHES FOUND"))
    text = "\n".join(lines) + "\n"
    dest = os.path.join(BUILD, "reference_model_results.txt") if a.quick else os.path.join(ROOT, "results", "reference_model_results.txt")
    open(dest, "w").write(text)
    print("\n".join(lines[-4:]))
    print("report:", dest)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
