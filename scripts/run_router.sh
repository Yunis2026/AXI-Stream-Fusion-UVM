#!/usr/bin/env bash
# Compile and execute the buffered router directed tests.

set -euo pipefail

# Resolve the project root.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p obj_dir/router waves logs

echo "[INFO] Compiling buffered router..."

verilator \
  --binary \
  --timing \
  --trace \
  -Wall \
  -Wno-fatal \
  -j 4 \
  --top-module tb_router \
  --Mdir obj_dir/router \
  rtl/sync_fifo.sv \
  rtl/apb_route_regs.sv \
  rtl/buffered_router.sv \
  tb/tb_router.sv \
  > logs/router_compile.log 2>&1

echo "[INFO] Running router verification..."

./obj_dir/router/Vtb_router | tee logs/router_simulation.log

# Require the testbench to reach its final PASS summary.
grep -q "ALL ROUTER DIRECTED TESTS PASSED" logs/router_simulation.log

echo "[INFO] Router verification completed successfully."
