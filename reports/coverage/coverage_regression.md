# AXI-Stream Fusion: Coverage Regression Report

## Regression Summary

- Total seeds: **5**
- Passed: **5**
- Failed: **0**
- Merged functional coverage: **18/18 (100.00%)**

## Per-Seed Results

| Seed | Status | Coverage | AXI Beats | Packets | APB |
|---|---|---:|---:|---:|---:|
| 12345 | PASS | 18/18 (100.00%) | 143 | 33 | 51 |
| 2026 | PASS | 16/18 (88.89%) | 151 | 33 | 51 |
| 74018 | PASS | 16/18 (88.89%) | 139 | 33 | 51 |
| 314159 | PASS | 17/18 (94.44%) | 150 | 33 | 51 |
| 271828 | PASS | 18/18 (100.00%) | 152 | 33 | 51 |

## Merged Functional Coverage Matrix

| Functional Bin | Total Hits | Status |
|---|---:|---|
| Route 0 packet | 85 | HIT |
| Route 1 packet | 80 | HIT |
| Route 0 x short packet | 9 | HIT |
| Route 0 x medium packet | 34 | HIT |
| Route 0 x long packet | 42 | HIT |
| Route 1 x short packet | 7 | HIT |
| Route 1 x medium packet | 33 | HIT |
| Route 1 x long packet | 40 | HIT |
| Route 0 x full final TKEEP | 8 | HIT |
| Route 0 x partial final TKEEP | 77 | HIT |
| Route 1 x full final TKEEP | 5 | HIT |
| Route 1 x partial final TKEEP | 75 | HIT |
| Invalid APB access | 25 | HIT |
| Mid-packet APB route update | 40 | HIT |
| Source backpressure | 33 | HIT |
| Output 0 backpressure | 326 | HIT |
| Output 1 backpressure | 366 | HIT |
| Simultaneous output pending | 17 | HIT |

## Coverage Holes

No uncovered bins within the defined 18-bin functional coverage model.

## Failed Runs

All requested regression seeds passed.

## Methodology and Limitations

- Per-seed functional coverage is computed from 18 explicitly defined transaction-level bins.
- Merged coverage uses a logical union: a bin is covered if at least one passing run hits it.
- Total Hits is the sum of observed bin counts across passing runs, not the number of unique bins.
- Failed runs are excluded from merged coverage and remain visible in the regression results.
- This report does not represent RTL code coverage, native SV covergroups, UCIS, or exhaustive verification.
