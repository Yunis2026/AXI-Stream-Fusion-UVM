#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_long_stall_uvm.sh
#
# Description:
#   Compile and execute long-duration AXI-Stream
#   backpressure UVM verification.
#
# Scenarios:
#   L01 - 300-cycle full FIFO stall
#   L02 - 400-cycle independent Output 1 stall
#   L03 - 250-cycle simultaneous output stall
#
# Usage:
#   ./scripts/run_router_long_stall_uvm.sh

set -euo pipefail

# --------------------------------------------------
# 1. Project configuration
# --------------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

BUILD_DIR="obj_dir/router_long_stall_uvm"

COMPILE_LOG="logs/router_long_stall_uvm_compile.log"
SIM_LOG="logs/router_long_stall_uvm_simulation.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 2. Compile the UVM test
# --------------------------------------------------

echo "[INFO] Compiling long-duration backpressure UVM test..."

if ! verilator \
    --binary \
    --timing \
    --trace \
    --vpi \
    --timescale 1ns/1ps \
    -Wno-fatal \
    -j 4 \
    --top-module tb_router_long_stall_uvm_top \
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
    tb/uvm/router_long_stall_pkg.sv \
    rtl/sync_fifo.sv \
    rtl/apb_route_regs.sv \
    rtl/buffered_router.sv \
    tb/uvm/tb_router_long_stall_uvm_top.sv \
    external/uvm/src/dpi/uvm_dpi.cc \
    > "$COMPILE_LOG" 2>&1; then

    echo "[FAIL] Long-duration UVM compilation failed."
    tail -n 80 "$COMPILE_LOG"
    exit 1

fi

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 3. Execute UVM simulation
# --------------------------------------------------

echo "[INFO] Running long-duration backpressure test..."

"./${BUILD_DIR}/Vtb_router_long_stall_uvm_top" \
    +UVM_NO_RELNOTES \
    | tee "$SIM_LOG"

# --------------------------------------------------
# 4. Check scenario completion
# --------------------------------------------------

for marker in \
    "[PASS] L01" \
    "[PASS] L02" \
    "[PASS] L03"; do

    if ! grep -Fq "$marker" "$SIM_LOG"; then

        echo "[FAIL] Missing scenario marker: $marker"
        exit 1

    fi

done

# --------------------------------------------------
# 5. Check scoreboard summary
# --------------------------------------------------

EXPECTED_SUMMARY="LONG_STALL_SUMMARY input=14 matched=14 out0=9 out1=5 apb=6 l01=300 l02=400 l03=250"

if ! grep -Fq "$EXPECTED_SUMMARY" "$SIM_LOG"; then

    echo "[FAIL] Long-duration scoreboard mismatch."
    exit 1

fi

# --------------------------------------------------
# 6. Check UVM completion
# --------------------------------------------------

if ! grep -Fq "ROUTER_LONG_STALL_UVM_PASS" "$SIM_LOG"; then

    echo "[FAIL] Long-duration UVM PASS marker missing."
    exit 1

fi

# --------------------------------------------------
# 7. Check UVM report statistics
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
echo " LONG-DURATION BACKPRESSURE UVM TEST PASSED"
echo "============================================="
echo " AXI accepted beats      : 14"
echo " AXI matched beats       : 14"
echo " Output 0 beats          : 9"
echo " Output 1 beats          : 5"
echo " APB transactions        : 6"
echo " L01 stall checks        : 300 cycles"
echo " L02 stall checks        : 400 cycles"
echo " L03 dual-output checks  : 250 cycles"
echo " UVM errors              : 0"
echo " UVM fatals              : 0"
echo "============================================="

echo "[INFO] Simulation log: ${SIM_LOG}"