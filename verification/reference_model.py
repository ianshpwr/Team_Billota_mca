#!/usr/bin/env python3
"""Independent behavioural reference model of the direct-mapped cache.

Written from the SPECIFICATION (Direct_Mapped_Cache_Controller_Three_Phase_Plan.md
and docs/address_decomposition.md), NOT from the Verilog RTL: it knows nothing
about the FSM, wait states or handshakes. It models only architectural state:

    main memory (64 KiB bytes) | 16 cache lines {valid, tag(10), 4 data bytes}

Specified behaviour implemented here
    address   : tag = a[15:6], index = a[5:2], offset = a[1:0]
    read      : hit if line.valid and line.tag == tag, else fetch the aligned
                4-byte block, overwrite the line, set valid; return the byte.
    write     : write-through + write-allocate. On a miss the aligned block is
                fetched and installed first; then the byte is updated in the
                cache line AND written to main memory (1 memory write).
    reset     : invalidates all lines; main memory contents are preserved.
    memory    : initial value of byte a is (a[7:0] ^ a[15:8]) + 0x5A (mod 256)
                (documented test pattern, docs/module_interfaces.md section 5).

Timing contract (docs/fsm_design.md, verified separately by the testbench
monitor on every transaction) is applied only to produce the expected latency
column:  read hit 3, read miss 5+L, write hit 4+L, write miss 6+2L cycles,
L = max(1, memory latency).

Vector file format (one 8-hex-digit word per line): {op[7:0], addr[15:0], wdata[7:0]}
    op 00 read | 01 write | 02 reset | 03 idle(wdata cycles) | FF end
Output format is identical to the log written by testbench/cache_tb_vec.v.

CLI: python3 -I verification/reference_model.py <vec> <out_log> <mem_dump> [latency]
"""
import sys

READ, WRITE, RESET, IDLE, END = 0x00, 0x01, 0x02, 0x03, 0xFF


def init_byte(a):
    return (((a & 0xFF) ^ ((a >> 8) & 0xFF)) + 0x5A) & 0xFF


class CacheModel:
    NUM_LINES = 16

    def __init__(self, mem_latency=4):
        self.L = max(1, mem_latency)
        self.mem = bytearray(init_byte(a) for a in range(65536))
        self.reset()

    # -- architectural operations ------------------------------------------------
    def reset(self):
        self.valid = [False] * self.NUM_LINES
        self.tag = [0] * self.NUM_LINES
        self.data = [bytearray(4) for _ in range(self.NUM_LINES)]
        # (RTL clears the tag/data arrays to 0 as well; that is not architecturally
        #  visible and the model keeps the same zero state only so the final cache
        #  dump can be compared bit for bit.)

    @staticmethod
    def fields(addr):
        return addr >> 6, (addr >> 2) & 0xF, addr & 0x3

    def _is_hit(self, addr):
        tag, idx, _ = self.fields(addr)
        return self.valid[idx] and self.tag[idx] == tag

    def _fill(self, addr):
        tag, idx, _ = self.fields(addr)
        base = addr & 0xFFFC
        self.data[idx] = bytearray(self.mem[base:base + 4])
        self.tag[idx] = tag
        self.valid[idx] = True

    def read(self, addr):
        tag, idx, off = self.fields(addr)
        hit = self._is_hit(addr)
        mem_rd = 0
        if not hit:
            self._fill(addr)
            mem_rd = 1
        return hit, self.data[idx][off], mem_rd, 0

    def write(self, addr, value):
        tag, idx, off = self.fields(addr)
        hit = self._is_hit(addr)
        mem_rd = 0
        if not hit:                       # write-allocate
            self._fill(addr)
            mem_rd = 1
        self.data[idx][off] = value & 0xFF   # update cache line
        self.mem[addr] = value & 0xFF        # write-through to memory
        return hit, 0, mem_rd, 1

    # -- documented latency contract ---------------------------------------------
    def latency(self, is_write, hit):
        L = self.L
        if not is_write:
            return 3 if hit else 5 + L
        return 4 + L if hit else 6 + 2 * L


def load_vectors(path):
    words = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        w = int(line, 16)
        if (w >> 24) == END:
            break
        words.append(w)
    return words


def run(vec_path, out_path, dump_path, mem_latency=4):
    m = CacheModel(mem_latency)
    out = []
    for idx, w in enumerate(load_vectors(vec_path)):
        op, addr, wd = (w >> 24) & 0xFF, (w >> 8) & 0xFFFF, w & 0xFF
        if op == READ:
            hit, rd, mr, mw = m.read(addr)
            out.append("T %d 0 %04x %02x %d %02x %d %d %d" % (idx, addr, wd, int(hit), rd, m.latency(False, hit), mr, mw))
        elif op == WRITE:
            hit, rd, mr, mw = m.write(addr, wd)
            out.append("T %d 1 %04x %02x %d %02x %d %d %d" % (idx, addr, wd, int(hit), rd, m.latency(True, hit), mr, mw))
        elif op == RESET:
            m.reset()
            out.append("R %d" % idx)
        elif op == IDLE:
            out.append("I %d %d" % (idx, wd))
        else:
            raise SystemExit("bad op %02x at %d" % (op, idx))
    for i in range(16):
        d = m.data[i]
        out.append("C %d %d %03x %08x" % (i, int(m.valid[i]), m.tag[i], d[0] | d[1] << 8 | d[2] << 16 | d[3] << 24))
    open(out_path, "w").write("\n".join(out) + "\n")
    if dump_path:
        open(dump_path, "w").write("\n".join("%02x" % b for b in m.mem) + "\n")
    return m


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    run(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 4)
