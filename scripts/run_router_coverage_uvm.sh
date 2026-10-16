#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_coverage_uvm.sh
#
# Description:
#   Compile and run coverage-enabled router UVM stress.
#
# Usage:
#   ./scripts/run_router_coverage_uvm.sh
#   SEED=2026 ./scripts/run_router_coverage_uvm.sh

set -euo pipefail

# --------------------------------------------------
# 1. PROJECT PATHS AND CONFIGURATION
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_DIR="obj_dir/router_coverage_uvm"

COMPILE_LOG="logs/router_coverage_uvm_compile.log"

SEED="${SEED:-12345}"

SIM_LOG="logs/router_coverage_seed_${SEED}.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 2. COMPILE COMPLETE COVERAGE ENVIRONMENT
# --------------------------------------------------

echo "[INFO] Compiling Router UVM coverage environment..."

verilator \
  --binary \
  --timing \
  --trace \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_router_coverage_uvm_top \
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
  tb/uvm/router_coverage_pkg.sv \
  rtl/sync_fifo.sv \
  rtl/apb_route_regs.sv \
  rtl/buffered_router.sv \
  tb/uvm/tb_router_coverage_uvm_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 3. RUN COVERAGE-ENABLED UVM SIMULATION
# --------------------------------------------------

echo "[INFO] Running Router UVM coverage test..."
echo "[INFO] Random seed: ${SEED}"

"./${BUILD_DIR}/Vtb_router_coverage_uvm_top" \
  "+verilator+seed+${SEED}" \
  +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# --------------------------------------------------
# 4. VERIFY COVERAGE RESULTS
# --------------------------------------------------

if ! grep -Fq "ROUTER_COVERAGE_UVM_PASS" "$SIM_LOG"; then

    echo "[FAIL] Coverage PASS marker missing."
    exit 1

fi

if ! grep -Fq "COVERAGE_SUMMARY hit=" "$SIM_LOG"; then

    echo "[FAIL] Functional coverage summary missing."
    exit 1

fi

if ! grep -Fq "ROUTER_STRESS_UVM_PASS" "$SIM_LOG"; then

    echo "[FAIL] Inherited UVM stress test did not pass."
    exit 1

fi

# --------------------------------------------------
# 5. VERIFY UVM REPORT STATISTICS
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
# 6. DISPLAY COVERAGE SUMMARY
# --------------------------------------------------

echo ""
echo "============================================="
echo " ROUTER FUNCTIONAL COVERAGE TEST PASSED"
echo "============================================="
echo " Random seed: ${SEED}"
echo ""

grep -F "ROUTE_0_LENGTH" "$SIM_LOG" | tail -n 1
grep -F "ROUTE_1_LENGTH" "$SIM_LOG" | tail -n 1

grep -F "ROUTE_0_FINAL_KEEP" "$SIM_LOG" | tail -n 1
grep -F "ROUTE_1_FINAL_KEEP" "$SIM_LOG" | tail -n 1

grep -F "APB_COVERAGE" "$SIM_LOG" | tail -n 1
grep -F "STALL_COVERAGE" "$SIM_LOG" | tail -n 1

grep -F "COVERAGE_SUMMARY hit=" "$SIM_LOG" | tail -n 1

echo ""
echo " UVM errors: 0"
echo " UVM fatals: 0"
echo "============================================="

echo "[INFO] Full log: ${SIM_LOG}"