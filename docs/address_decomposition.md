# Address Decomposition and Direct Mapping

## Direct mapping

In a direct-mapped cache each memory block can live in exactly **one** cache
line, so a lookup needs one tag comparison.

```
line_index = (byte_address / BLOCK_SIZE) mod NUM_LINES
           = (byte_address >> 2) mod 16
```

Memory blocks whose block numbers differ by a multiple of 16 collide on the
same line (a **conflict**). The tag stores which of those competing blocks the
line currently holds.

## Derivation of the field widths

| Quantity | Derivation | Value |
|---|---|---|
| Address width | given | 16 bits (64 KiB, byte addressable) |
| Block size | given | 4 bytes |
| Offset bits | log2(4) | **2** |
| Number of lines | 64 B cache / 4 B block | 16 |
| Index bits | log2(16) | **4** |
| Tag bits | 16 − 4 − 2 | **10** |

```
 15                       6 5        2 1      0
+--------------------------+----------+--------+
|        tag [15:6]        | idx[5:2] | off    |
|         10 bits          |  4 bits  | [1:0]  |
+--------------------------+----------+--------+
```

* `tag    = address[15:6]`
* `index  = address[5:2]`
* `offset = address[1:0]`
* Block base address (aligned) = `{address[15:2], 2'b00}` = `address & 16'hFFFC`

## Capacity and storage overhead

| Item | Calculation | Bits |
|---|---|---|
| Data storage | 16 lines × 32 bits | 512 |
| Tag storage | 16 lines × 10 bits | 160 |
| Valid storage | 16 lines × 1 bit | 16 |
| **Total logical storage** | 512 + 160 + 16 | **688** |
| Data capacity | 16 × 4 bytes | 64 bytes |
| Overhead ratio | (160 + 16) / 512 | 34.4 % |

The full address space has 65,536 bytes = **16,384** four-byte blocks (not 256).
Each cache line is therefore shared by 16,384 / 16 = **1,024** memory blocks,
which is why 10 tag bits are required (2^10 = 1,024).

*Evidence:* a generic Yosys synthesis of `cache_memory` maps to exactly
672 + 16 = **688 flip-flops**, matching the table above
(`results/phase1_yosys_check.txt`). This is a count of storage elements, not a
physical area or timing result.

## Byte ordering inside a block (little-endian)

| Offset | Block bits | Memory byte address |
|---|---|---|
| 0 | `[7:0]`   | `base + 0` |
| 1 | `[15:8]`  | `base + 1` |
| 2 | `[23:16]` | `base + 2` |
| 3 | `[31:24]` | `base + 3` |

`block = { mem[base+3], mem[base+2], mem[base+1], mem[base] }`.
The same convention is used by `main_memory.v` (block read assembly) and
`cache_memory.v` (byte select/merge). Mutation M9 (big-endian assembly in the
memory model) and M1 (reversed byte select) are both detected by the testbench.

## Worked examples

| Address | Tag | Index | Offset | Notes |
|---|---|---|---|---|
| `0x0004` | `0x000` | 1  | 0 | first cold miss in the testbench |
| `0x0044` | `0x001` | 1  | 0 | conflicts with `0x0004` (same index, different tag) |
| `0x0102` | `0x004` | 0  | 2 | write-allocate example |
| `0xFFFF` | `0x3FF` | 15 | 3 | maximum tag, maximum index, maximum offset |
| `0x0000` | `0x000` | 0  | 0 | minimum address |
