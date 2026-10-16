#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_reset_uvm.sh
#
# Description:
#   Compile and execute the reset-during-traffic
#   advanced UVM verification test.
#
# Verification objectives:
#   - Reset with outstanding buffered beats
#   - Clear packet-lock reference state
#   - Clear buffered data without false mismatches
#   - Verify APB reset value
#   - Verify clean post-reset routing
#
# Usage:
#   ./scripts/run_router_reset_uvm.sh

set -euo pipefail

# --------------------------------------------------
# 1. Project configuration
# --------------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

BUILD_DIR="obj_dir/router_reset_uvm"

COMPILE_LOG="logs/router_reset_uvm_compile.log"
SIM_LOG="logs/router_reset_uvm_simulation.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 2. Compile reset-aware UVM environment
# --------------------------------------------------

echo "[INFO] Compiling Router reset UVM test..."

if ! verilator \
    --binary \
    --timing \
    --trace \
    --vpi \
    --timescale 1ns/1ps \
    -Wno-fatal \
    -j 4 \
    --top-module tb_router_reset_uvm_top \
    --Mdir "$BUILD_DIR" \
    -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
    +incdir+external/uvm/src \
    +incdir+tb/uvm \
    external/uvm/src/uvm_pkg.sv \
    tb/uvm/axis_if.sv \
    tb/uvm/apb_if.sv \
    tb/uvm/router_reset_if.sv \
    tb/uvm/axis_pkg.sv \
    tb/uvm/apb_pkg.sv \
    tb/uvm/router_dynamic_pkg.sv \
    tb/uvm/router_reset_pkg.sv \
    rtl/sync_fifo.sv \
    rtl/apb_route_regs.sv \
    rtl/buffered_router.sv \
    tb/uvm/tb_router_reset_uvm_top.sv \
    external/uvm/src/dpi/uvm_dpi.cc \
    > "$COMPILE_LOG" 2>&1; then

    echo "[FAIL] Reset UVM compilation failed."
    tail -n 60 "$COMPILE_LOG"
    exit 1

fi

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 3. Execute reset verification
# --------------------------------------------------

echo "[INFO] Running reset-during-traffic UVM test..."

"./${BUILD_DIR}/Vtb_router_reset_uvm_top" \
    +UVM_NO_RELNOTES \
    | tee "$SIM_LOG"

# --------------------------------------------------
# 4. Check directed reset scenarios
# --------------------------------------------------

for marker in \
    "[PASS] RST01" \
    "[PASS] RST02" \
    "[PASS] RST03" \
    "[PASS] RST04" \
    "[PASS] RST05"; do

    if ! grep -Fq "$marker" "$SIM_LOG"; then

        echo "[FAIL] Missing reset scenario: $marker"
        exit 1

    fi

done

# --------------------------------------------------
# 5. Verify reset-aware scoreboard accounting
# --------------------------------------------------

EXPECTED_SUMMARY="RESET_SUMMARY input=6 matched=3 discarded=3 output0=2 output1=1 apb=4 resets=1"

if ! grep -Fq "$EXPECTED_SUMMARY" "$SIM_LOG"; then

    echo "[FAIL] Reset scoreboard accounting mismatch."
    exit 1

fi

# --------------------------------------------------
# 6. Verify UVM completion marker
# --------------------------------------------------

if ! grep -Fq "ROUTER_RESET_UVM_PASS" "$SIM_LOG"; then

    echo "[FAIL] Reset UVM completion marker missing."
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
echo " ROUTER RESET UVM VERIFICATION PASSED"
echo "============================================="
echo " Accepted AXI beats    : 6"
echo " Matched AXI beats     : 3"
echo " Reset-discarded beats : 3"
echo " Output 0 beats        : 2"
echo " Output 1 beats        : 1"
echo " APB transactions      : 4"
echo " Runtime resets        : 1"
echo " UVM errors            : 0"
echo " UVM fatals            : 0"
echo "============================================="

echo "[INFO] Full simulation log: ${SIM_LOG}"