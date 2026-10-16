#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_stress_uvm.sh
#
# Description:
#   Compile and execute randomized Router UVM stress tests.
#
# Tests:
#   S01 - FIFO full
#   S02 - Independent output backpressure
#   S03 - Random packet and APB stress
#
# Usage:
#   ./scripts/run_router_stress_uvm.sh
#   SEED=2026 ./scripts/run_router_stress_uvm.sh

set -euo pipefail

# --------------------------------------------------
# 1. Project paths
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

BUILD_DIR="obj_dir/router_stress_uvm"

COMPILE_LOG="logs/router_stress_uvm_compile.log"

SEED="${SEED:-12345}"

SIM_LOG="logs/router_stress_uvm_seed_${SEED}.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 2. Compile complete UVM environment
# --------------------------------------------------

echo "[INFO] Compiling Router UVM stress environment..."

verilator \
  --binary \
  --timing \
  --trace \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_router_stress_uvm_top \
  --Mdir "$BUILD_DIR" \
  -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
  +incdir+external/uvm/src \
  +incdir+tb/uvm \
  external/uvm/src/uvm_pkg.sv \
  tb/uvm/axis_if.sv \
  tb/uvm/apb_if.sv \
  tb/uvm/axis_pkg.sv \
  tb/uvm/apb_pkg.sv \
  tb/uvm/router_dynamic_pkg.sv \
  tb/uvm/router_stress_pkg.sv \
  rtl/sync_fifo.sv \
  rtl/apb_route_regs.sv \
  rtl/buffered_router.sv \
  tb/uvm/tb_router_stress_uvm_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 3. Run simulation with a reproducible seed
# --------------------------------------------------

echo "[INFO] Running Router UVM stress test..."
echo "[INFO] Random seed: ${SEED}"

"./${BUILD_DIR}/Vtb_router_stress_uvm_top" \
  "+verilator+seed+${SEED}" \
  +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# --------------------------------------------------
# 4. Check directed scenario results
# --------------------------------------------------

if ! grep -Fq "[PASS] S01 FIFO full and fifth-beat stall" "$SIM_LOG"; then
    echo "[FAIL] S01 FIFO full verification missing."
    exit 1
fi

if ! grep -Fq "[PASS] S02 independent FIFO backpressure" "$SIM_LOG"; then
    echo "[FAIL] S02 independent backpressure verification missing."
    exit 1
fi

if ! grep -Fq "[PASS] S03 randomized packet stress" "$SIM_LOG"; then
    echo "[FAIL] S03 randomized traffic verification missing."
    exit 1
fi

# --------------------------------------------------
# 5. Check scoreboard completion
# --------------------------------------------------

if ! grep -Fq "STRESS_SUMMARY" "$SIM_LOG"; then
    echo "[FAIL] Stress statistics missing."
    exit 1
fi

if ! grep -Fq "ROUTER_STRESS_UVM_PASS" "$SIM_LOG"; then
    echo "[FAIL] UVM stress PASS marker missing."
    exit 1
fi

# --------------------------------------------------
# 6. Verify UVM report counts
# --------------------------------------------------

if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0([[:space:]]|$)' "$SIM_LOG"; then
    echo "[FAIL] UVM errors detected."
    exit 1
fi

if ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0([[:space:]]|$)' "$SIM_LOG"; then
    echo "[FAIL] UVM fatal errors detected."
    exit 1
fi

# --------------------------------------------------
# 7. Final result
# --------------------------------------------------

echo ""
echo "============================================="
echo " ROUTER UVM STRESS VERIFICATION PASSED"
echo "============================================="
echo " Random seed: ${SEED}"
echo " Directed FIFO full test: PASS"
echo " Independent backpressure: PASS"
echo " Random traffic stress: PASS"
echo " UVM errors: 0"
echo " UVM fatals: 0"
echo "============================================="

echo "[INFO] Full simulation log: ${SIM_LOG}"