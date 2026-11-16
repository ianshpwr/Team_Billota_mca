#!/usr/bin/env python3
"""Text trace of a VCD: one row per rising clock edge, signals sampled just
BEFORE the edge (i.e. what the synchronous logic sees at that edge).

This is a text rendering for evidence/review. It is NOT a substitute for
viewing the waveform in a waveform viewer.

Usage: python3 -I scripts/vcd_trace.py <file.vcd> [first_cycle] [last_cycle]
"""
import sys

STATES = {0:"IDLE",1:"COMPARE_TAG",2:"READ_HIT",3:"READ_MISS",4:"MEMORY_READ_WAIT",
          5:"REFILL",6:"WRITE_HIT",7:"WRITE_MISS",8:"MEMORY_WRITE_WAIT",9:"RESPONSE"}
SIGS = ["rst","cpu_req","cpu_we","cpu_addr","cpu_ready","cpu_resp_valid","cpu_rdata",
        "dbg_state","dbg_lookup","dbg_hit","dbg_index","dbg_tag","dbg_line_valid",
        "dbg_refill","dbg_byte_we","mem_req","mem_we","mem_addr","mem_done"]

def parse(path):
    ids, scope, vals = {}, [], {}
    with open(path) as f:
        it = iter(f)
        for line in it:                      # header
            t = line.split()
            if not t: continue
            if t[0] == "$scope": scope.append(t[2])
            elif t[0] == "$upscope": scope.pop()
            elif t[0] == "$var" and scope == ["cache_tb"]:
                ids.setdefault(t[3], t[4])   # id -> name (top-level TB scope only)
            elif t[0] == "$enddefinitions": break
        cur = {n: "x" for n in ids.values()}
        byname = {n: i for i, n in ids.items()}
        rows, t_now, pending, clk_prev = [], 0, [], "0"
        def flush(time, changes):
            nonlocal clk_prev
            snap = dict(cur)                 # state BEFORE this timestamp's changes
            for i, v in changes:
                if i in ids: cur[ids[i]] = v
            if clk_prev == "0" and cur.get("clk") == "1":
                rows.append((time, snap))
            clk_prev = cur.get("clk", clk_prev)
        for line in it:
            line = line.strip()
            if not line: continue
            if line[0] == "#":
                flush(t_now, pending); pending = []; t_now = int(line[1:])
            elif line[0] in "01xzXZ" and not line.startswith("$"):
                pending.append((line[1:], line[0]))
            elif line[0] == "b":
                v, i = line[1:].split()
                pending.append((i, v))
        flush(t_now, pending)
    return rows

def fmt(name, v):
    if v is None or any(bit in v.lower() for bit in "xz"): return "x"
    n = int(v, 2)
    if name == "dbg_state": return STATES.get(n, str(n))
    if name in ("cpu_addr","mem_addr","dbg_tag"): return "%04X" % n if name != "dbg_tag" else "%03X" % n
    if name == "cpu_rdata": return "%02X" % n
    return str(n)

def main():
    rows = parse(sys.argv[1])
    lo = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    hi = int(sys.argv[3]) if len(sys.argv) > 3 else len(rows) - 1
    short = {"cpu_resp_valid":"resp","cpu_ready":"rdy","dbg_state":"state","dbg_lookup":"lkp",
             "dbg_hit":"hit","dbg_index":"idx","dbg_tag":"tag","dbg_line_valid":"lval",
             "dbg_refill":"rfl","dbg_byte_we":"bwe","cpu_addr":"addr","cpu_rdata":"rdata",
             "cpu_req":"req","cpu_we":"we","mem_req":"mreq","mem_we":"mwe","mem_addr":"maddr","mem_done":"mdone"}
    cols = [s for s in SIGS if s in short]
    print("cyc  time(ns) " + " ".join("%-17s" % short[c] if c == "dbg_state" else "%-5s" % short[c] for c in cols))
    for n, (t, snap) in enumerate(rows):
        if n < lo or n > hi: continue
        print("%4d %8.1f " % (n, t / 1000.0) + " ".join(
            ("%-17s" if c == "dbg_state" else "%-5s") % fmt(c, snap.get(c)) for c in cols))

main()
