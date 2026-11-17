#!/usr/bin/env python3
"""Plots for the report, drawn from the saved measurement files (no invented data).
Run with the project venv:  .venv/bin/python scripts/make_report_figures.py
Inputs : results/phase2_latency_sweep.txt, results/performance_metrics.csv
Outputs: diagrams/fig_latency_vs_L.png, diagrams/fig_hit_ratio.png, diagrams/fig_avg_latency.png"""
import csv, re, collections
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams.update({"font.size": 8, "axes.grid": True, "grid.alpha": 0.3, "figure.dpi": 200})

# ---- measured transaction latency vs memory latency (from the directed-test sweep)
pts = []
for ln in open("results/phase2_latency_sweep.txt"):
    m = re.match(r"L=(\d+)\s+\d\s+47\s+0\s+0\s+PASS\s+(\d+)/(\d+)/(\d+)/(\d+)", ln)
    if m and int(m.group(1)) >= 1:
        pts.append(tuple(int(x) for x in m.groups()))
pts.sort()
L = [p[0] for p in pts]
fig, ax = plt.subplots(figsize=(3.4, 2.4))
for i, (lab, mk) in enumerate([("read hit", "o"), ("read miss", "s"), ("write hit", "^"), ("write miss", "d")]):
    ax.plot(L, [p[1 + i] for p in pts], marker=mk, ms=3, lw=1, label=lab)
ax.set_xscale("log"); ax.set_yscale("log")
ax.set_xlabel("memory latency L (cycles)"); ax.set_ylabel("transaction latency (cycles)")
ax.legend(frameon=False, fontsize=7)
fig.tight_layout(); fig.savefig("diagrams/fig_latency_vs_L.png"); plt.close(fig)

# ---- workload metrics from performance_metrics.csv
rows = list(csv.DictReader(open("results/performance_metrics.csv")))
wl = ["uniform", "hotset", "conflict", "sequential", "write_heavy", "mixed_reset", "corners", "tagbits"]
by = collections.defaultdict(list)
for r in rows:
    if r["workload"] in wl: by[(r["workload"], int(r["mem_latency_L"]))].append(r)

mean = lambda x: sum(x) / len(x)
fig, ax = plt.subplots(figsize=(3.4, 2.4))
hr = [[float(r["hit_ratio"]) for r in by[(w, 4)]] for w in wl]
ax.bar(range(len(wl)), [mean(h) for h in hr], yerr=[[mean(h) - min(h) for h in hr], [max(h) - mean(h) for h in hr]], capsize=2, color="#4c72b0")
ax.set_xticks(range(len(wl))); ax.set_xticklabels([w.replace("_", " ") for w in wl], fontsize=6, rotation=35, ha="right")
ax.set_ylabel("hit ratio (mean, min-max over 6 seeds)"); ax.set_ylim(0, 1)
fig.tight_layout(); fig.savefig("diagrams/fig_hit_ratio.png"); plt.close(fig)

fig, ax = plt.subplots(figsize=(3.4, 2.4))
Ls = sorted({int(r["mem_latency_L"]) for r in rows if r["workload"] in wl})
for w in wl:
    ax.plot(Ls, [mean([float(r["avg_latency_cycles"]) for r in by[(w, l)]]) for l in Ls], marker="o", ms=2.5, lw=1, label=w)
ax.set_xlabel("memory latency L (cycles)"); ax.set_ylabel("average transaction latency (cycles)")
ax.legend(frameon=False, fontsize=5.5, ncol=2)
fig.tight_layout(); fig.savefig("diagrams/fig_avg_latency.png"); plt.close(fig)
print("figures written")
