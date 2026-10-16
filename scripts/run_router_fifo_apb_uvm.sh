#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_fifo_apb_uvm.sh
#
# Description:
#   Compile and run FIFO-full plus APB route-update
#   UVM verification.
#
# Verification scenarios:
#   S04A - Full four-entry FIFO, fifth beat stalled
#   S04B - APB update while AXI beat is stalled
#   S04C - Drain current packet through locked route
#   S04D - New packet follows updated APB route
#
# Usage:
#   ./scripts/run_router_fifo_apb_uvm.sh

set -euo pipefail

# --------------------------------------------------
# 1. Resolve project root
# --------------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

# --------------------------------------------------
# 2. Output directories
# --------------------------------------------------

BUILD_DIR="obj_dir/router_fifo_apb_uvm"

COMPILE_LOG="logs/router_fifo_apb_uvm_compile.log"
SIM_LOG="logs/router_fifo_apb_uvm_simulation.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 3. Compile the UVM verification environment
# --------------------------------------------------

echo "[INFO] Compiling FIFO-full/APB-update UVM test..."

if ! verilator \
    --binary \
    --timing \
    --trace \
    --vpi \
    --timescale 1ns/1ps \
    -Wno-fatal \
    -j 4 \
    --top-module tb_router_fifo_apb_uvm_top \
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
    tb/uvm/router_fifo_apb_pkg.sv \
    rtl/sync_fifo.sv \
    rtl/apb_route_regs.sv \
    rtl/buffered_router.sv \
    tb/uvm/tb_router_fifo_apb_uvm_top.sv \
    external/uvm/src/dpi/uvm_dpi.cc \
    > "$COMPILE_LOG" 2>&1; then

    echo "[FAIL] FIFO/APB UVM compilation failed."
    tail -n 80 "$COMPILE_LOG"
    exit 1

fi

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 4. Execute simulation
# --------------------------------------------------

echo "[INFO] Running FIFO-full/APB-update UVM test..."

"./${BUILD_DIR}/Vtb_router_fifo_apb_uvm_top" \
    +UVM_NO_RELNOTES \
    | tee "$SIM_LOG"

# --------------------------------------------------
# 5. Verify directed scenarios
# --------------------------------------------------

for marker in \
    "[PASS] S04A" \
    "[PASS] S04B" \
    "[PASS] S04C" \
    "[PASS] S04D"; do

    if ! grep -Fq "$marker" "$SIM_LOG"; then

        echo "[FAIL] Missing scenario marker: $marker"
        exit 1

    fi

done

# --------------------------------------------------
# 6. Verify complete scoreboard accounting
# --------------------------------------------------

EXPECTED_SUMMARY="FIFO_APB_SUMMARY input=7 matched=7 out0=5 out1=2 apb=4 errors=1"

if ! grep -Fq "$EXPECTED_SUMMARY" "$SIM_LOG"; then

    echo "[FAIL] FIFO/APB scoreboard summary mismatch."
    exit 1

fi

if ! grep -Fq "ROUTER_FIFO_APB_UVM_PASS" "$SIM_LOG"; then

    echo "[FAIL] FIFO/APB UVM PASS marker missing."
    exit 1

fi

# --------------------------------------------------
# 7. Verify UVM report statistics
# --------------------------------------------------

if ! grep -Eq \
    'UVM_ERROR[[:space:]]*:[[:space:]]*0([[:space:]]|$)' \
    "$SIM_LOG"; then

    echo "[FAIL] UVM errors detected."
    exit 1

fi

if ! grep -Eq \
    'UVM_FATAL[[:space:]]*:[[:space:]]*0([[:space:]]|$)' \
    "$SIM_LOG"; then

    echo "[FAIL] UVM fatal errors detected."
    exit 1

fi

# --------------------------------------------------
# 8. Final result
# --------------------------------------------------

echo ""
echo "============================================="
echo " FIFO FULL + APB UPDATE UVM TEST PASSED"
echo "============================================="
echo " AXI accepted beats    : 7"
echo " AXI matched beats     : 7"
echo " Output 0 beats        : 5"
echo " Output 1 beats        : 2"
echo " APB transactions      : 4"
echo " APB error responses   : 1"
echo " UVM errors            : 0"
echo " UVM fatals            : 0"
echo "============================================="

echo "[INFO] Simulation log: ${SIM_LOG}"