# Performance Metrics Summary (Phase 2)

All numbers are computed by `verification/performance.py` from the **actual simulation logs** of the RTL (clock cycles of the simulated design). No clock frequency, FPGA or silicon timing is assumed or claimed. Raw per-run data: `results/performance_metrics.csv` (309 rows).

## Assumptions and definitions

* Latency = cycles from request acceptance to the response edge. Documented/measured: read hit 3, read miss 5+L, write hit 4+L, write miss 6+2L (L = main-memory latency in cycles).
* Hit ratio = hits/requests; miss ratio = misses/requests (a write is a hit if its block is cached).
* `AMAT_read = H + MR_read x MP` with H = 3 and MP = 2+L is the textbook formula and applies to **reads only**: every write pays the write-through memory latency (4+L even on a hit), so the single-formula AMAT underestimates mixed workloads.
* `AMAT_class` = sum over {read hit, read miss, write hit, write miss} of fraction x documented latency. It equals the measured average latency because the formulas were verified on every transaction by the testbench monitor; it is a *consistency check*, not independent evidence.
* Workloads are synthetic (generator profiles in `verification/randomized_tests.py`, fixed seeds 1-6, 2500 requests each); hit ratios say nothing about real programs.

## Mean over seeds 1-6, 2500 requests per run, memory latency L = 4

| Workload | Requests | Reads | Writes | Hit ratio | Miss ratio | Mem reads | Mem writes | Avg latency (cycles) | AMAT_read (cycles) | AMAT_class (cycles) |
|---|---|---|---|---|---|---|---|---|---|---|
| uniform | 2500 | 1746 | 754 | 0.0009 | 0.9991 | 2498 | 754 | 10.501 | 8.993 | 10.501 |
| hotset | 2500 | 1634 | 866 | 0.3790 | 0.6210 | 1552 | 866 | 8.457 | 6.723 | 8.457 |
| conflict | 2500 | 1763 | 737 | 0.1633 | 0.8367 | 2092 | 737 | 9.495 | 8.029 | 9.495 |
| sequential | 2500 | 1997 | 503 | 0.5887 | 0.4113 | 1028 | 503 | 6.474 | 5.456 | 6.474 |
| write_heavy | 2500 | 493 | 2007 | 0.2451 | 0.7549 | 1887 | 2007 | 11.543 | 7.502 | 11.543 |
| mixed_reset | 2348 | 1526 | 822 | 0.0215 | 0.9785 | 2298 | 822 | 10.621 | 8.867 | 10.621 |
| corners | 2500 | 1491 | 1009 | 0.2977 | 0.7023 | 1756 | 1009 | 9.231 | 7.221 | 9.231 |
| tagbits | 2500 | 1742 | 758 | 0.0447 | 0.9553 | 2388 | 758 | 10.247 | 8.729 | 10.247 |

## Average latency (cycles) versus memory latency L (mean over seeds)

| Workload | L=1 | L=2 | L=3 | L=4 | L=8 | L=16 |
|---|---|---|---|---|---|---|
| uniform | 6.60 | 7.90 | 9.20 | 10.50 | 15.70 | 26.11 |
| hotset | 5.56 | 6.52 | 7.49 | 8.46 | 12.33 | 20.06 |
| conflict | 6.10 | 7.23 | 8.36 | 9.49 | 14.02 | 23.07 |
| sequential | 4.64 | 5.25 | 5.86 | 6.47 | 8.92 | 13.82 |
| write_heavy | 6.87 | 8.43 | 9.99 | 11.54 | 17.77 | 30.24 |
| mixed_reset | 6.64 | 7.96 | 9.29 | 10.62 | 15.94 | 26.56 |
| corners | 5.91 | 7.02 | 8.13 | 9.23 | 13.65 | 22.50 |
| tagbits | 6.47 | 7.73 | 8.99 | 10.25 | 15.28 | 25.35 |

## Measured vs predicted

Maximum |measured average latency - class-weighted prediction| over all 288 fixed-latency runs: **0.000000 cycles** (rounding only).

Write-through cost: in the `write_heavy` workload the average latency at L=16 is 30.24 cycles versus 20.06 for `hotset` (read-dominant), because every write stalls for the memory write.
