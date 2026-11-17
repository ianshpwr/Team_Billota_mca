#!/usr/bin/env python3
"""Performance metrics computed from ACTUAL simulation output logs.

Input: a result log written by testbench/cache_tb_vec.v (lines `T ...`).
Nothing here is estimated from a hardware model: every count and every latency
comes from the simulated DUT. Units are CLOCK CYCLES of the simulation; no clock
frequency, FPGA or silicon timing is assumed or claimed.

Metrics
  hit_ratio  = hits / requests            miss_ratio = misses / requests
  avg_latency_cycles   = mean of the measured accept->response cycles (all requests)
  amat_read_formula    = H + MR_read * MP_read     (reads only)
        H = 3 (read-hit time, measured), MP_read = 2 + L  (read-miss time 5+L minus H)
        -- the textbook AMAT, restricted to reads because every WRITE pays the
        -- write-through memory latency whether it hits or misses.
  amat_class_weighted  = sum over {read hit, read miss, write hit, write miss}
        of (fraction of requests in the class) * (documented class latency)
        This is an ASSUMPTION-based prediction (latency formulas), compared with the
        MEASURED avg_latency_cycles; they agree because the formulas were verified
        on every transaction by the testbench monitor.
"""
import sys

FIELDS = ["workload", "seed", "mem_latency_L", "total_requests", "reads", "writes", "hits", "misses",
          "hit_ratio", "miss_ratio", "mem_read_txns", "mem_write_txns", "avg_latency_cycles",
          "amat_read_formula", "amat_class_weighted", "total_latency_cycles"]


def parse_log(lines):
    txns = []
    for ln in lines:
        p = ln.split()
        if p and p[0] == "T":
            txns.append(dict(op=int(p[2]), hit=int(p[5]), lat=int(p[7]), mrd=int(p[8]), mwr=int(p[9])))
    return txns


def compute(txns, L, workload="", seed=""):
    L = max(1, L)
    n = len(txns)
    if n == 0:
        return None
    reads = [t for t in txns if t["op"] == 0]
    writes = [t for t in txns if t["op"] == 1]
    hits = sum(t["hit"] for t in txns)
    rh = sum(1 for t in reads if t["hit"]); rm = len(reads) - rh
    wh = sum(1 for t in writes if t["hit"]); wm = len(writes) - wh
    total_lat = sum(t["lat"] for t in txns)
    amat_read = ""
    if reads:
        amat_read = round(3 + (rm / len(reads)) * (2 + L), 4)
    cw = (rh * 3 + rm * (5 + L) + wh * (4 + L) + wm * (6 + 2 * L)) / n
    return {
        "workload": workload, "seed": seed, "mem_latency_L": L, "total_requests": n,
        "reads": len(reads), "writes": len(writes), "hits": hits, "misses": n - hits,
        "hit_ratio": round(hits / n, 6), "miss_ratio": round((n - hits) / n, 6),
        "mem_read_txns": sum(t["mrd"] for t in txns), "mem_write_txns": sum(t["mwr"] for t in txns),
        "avg_latency_cycles": round(total_lat / n, 4),
        "amat_read_formula": amat_read, "amat_class_weighted": round(cw, 4),
        "total_latency_cycles": total_lat,
    }


if __name__ == "__main__":
    log, L = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4
    r = compute(parse_log(open(log)), L, log)
    for k in FIELDS:
        print("%-22s %s" % (k, r[k]))
