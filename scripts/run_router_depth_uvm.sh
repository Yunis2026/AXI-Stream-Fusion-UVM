#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_depth_uvm.sh
#
# Description:
#   Parameterized FIFO depth UVM regression.
#
# Default configurations:
#   FIFO_DEPTH = 2, 4, 8
#
# Usage:
#   ./scripts/run_router_depth_uvm.sh
#
#   DEPTHS="2 8" ./scripts/run_router_depth_uvm.sh
#
# Each configuration uses an independent build
# directory and simulation log.

set -euo pipefail

# --------------------------------------------------
# 1. PROJECT CONFIGURATION
# --------------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

DEPTHS="${DEPTHS:-2 4 8}"

LOG_DIR="logs/depth_regression"

mkdir -p "$LOG_DIR" waves

# --------------------------------------------------
# 2. REGRESSION STATISTICS
# --------------------------------------------------

total=0
passed=0
failed=0

echo ""
echo "============================================="
echo " PARAMETERIZED FIFO UVM REGRESSION"
echo "============================================="
echo " FIFO depths: ${DEPTHS}"
echo "============================================="
echo ""

# --------------------------------------------------
# 3. ITERATE OVER FIFO CONFIGURATIONS
# --------------------------------------------------

for depth in $DEPTHS; do

    # Reject nonnumeric depth values.
    if [[ ! "$depth" =~ ^[0-9]+$ ]]; then

        echo "[ERROR] Invalid FIFO depth: $depth"
        exit 2

    fi

    # Supported configurations are powers of two
    # with at least two FIFO entries.
    if (( depth < 2 || (depth & (depth - 1)) != 0 )); then

        echo "[ERROR] FIFO depth must be a power of two >= 2."
        exit 2

    fi

    total=$((total + 1))

    BUILD_DIR="obj_dir/router_depth_${depth}"

    COMPILE_LOG="${LOG_DIR}/depth_${depth}_compile.log"
    SIM_LOG="${LOG_DIR}/depth_${depth}_simulation.log"

    mkdir -p "$BUILD_DIR"

    echo "---------------------------------------------"
    echo "[RUN] FIFO_DEPTH=${depth}"
    echo "---------------------------------------------"

    # ----------------------------------------------
    # Compile a DUT using the selected FIFO depth.
    # ----------------------------------------------

    echo "[INFO] Compiling depth ${depth}..."

    if ! verilator \
        --binary \
        --timing \
        --trace \
        --vpi \
        --timescale 1ns/1ps \
        -Wno-fatal \
        -j 4 \
        --top-module tb_router_depth_uvm_top \
        "-GFIFO_DEPTH=${depth}" \
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
        tb/uvm/router_depth_pkg.sv \
        rtl/sync_fifo.sv \
        rtl/apb_route_regs.sv \
        rtl/buffered_router.sv \
        tb/uvm/tb_router_depth_uvm_top.sv \
        external/uvm/src/dpi/uvm_dpi.cc \
        > "$COMPILE_LOG" 2>&1; then

        failed=$((failed + 1))

        echo "[FAIL] Compilation failed for depth ${depth}."
        tail -n 35 "$COMPILE_LOG"

        echo ""
        continue

    fi

    echo "[INFO] Compilation successful."

    # ----------------------------------------------
    # Run the parameterized UVM simulation.
    # ----------------------------------------------

    echo "[INFO] Simulating depth ${depth}..."

    if ! "./${BUILD_DIR}/Vtb_router_depth_uvm_top" \
        +UVM_NO_RELNOTES \
        > "$SIM_LOG" 2>&1; then

        failed=$((failed + 1))

        echo "[FAIL] Simulation failed for depth ${depth}."
        tail -n 35 "$SIM_LOG"

        echo ""
        continue

    fi

    # ----------------------------------------------
    # Calculate expected transaction counts.
    # ----------------------------------------------

    expected_input=$((2 * depth + 6))

    expected_output=$((depth + 3))

    expected_summary="DEPTH_SUMMARY depth=${depth} input=${expected_input} matched=${expected_input} out0=${expected_output} out1=${expected_output} apb=6 errors=1"

    # ----------------------------------------------
    # Check the UVM PASS marker.
    # ----------------------------------------------

    if ! grep -Fq "ROUTER_DEPTH_UVM_PASS" "$SIM_LOG"; then

        failed=$((failed + 1))

        echo "[FAIL] PASS marker missing for depth ${depth}."
        echo ""
        continue

    fi

    # ----------------------------------------------
    # Check expected transaction counts.
    # ----------------------------------------------

    if ! grep -Fq "$expected_summary" "$SIM_LOG"; then

        failed=$((failed + 1))

        echo "[FAIL] Scoreboard mismatch for depth ${depth}."
        tail -n 25 "$SIM_LOG"

        echo ""
        continue

    fi

    # ----------------------------------------------
    # Check the UVM report.
    # ----------------------------------------------

    if ! grep -Eq \
        'UVM_ERROR[[:space:]]*:[[:space:]]*0([[:space:]]|$)' \
        "$SIM_LOG"; then

        failed=$((failed + 1))

        echo "[FAIL] UVM errors for depth ${depth}."
        echo ""
        continue

    fi

    if ! grep -Eq \
        'UVM_FATAL[[:space:]]*:[[:space:]]*0([[:space:]]|$)' \
        "$SIM_LOG"; then

        failed=$((failed + 1))

        echo "[FAIL] UVM fatal errors for depth ${depth}."
        echo ""
        continue

    fi

    # ----------------------------------------------
    # Record a successful run.
    # ----------------------------------------------

    passed=$((passed + 1))

    echo "[PASS] FIFO_DEPTH=${depth}"

    grep -F "DEPTH_SUMMARY" "$SIM_LOG" | tail -n 1

    echo ""

done

# --------------------------------------------------
# 4. FINAL REGRESSION SUMMARY
# --------------------------------------------------

echo "============================================="
echo " FIFO DEPTH REGRESSION SUMMARY"
echo "============================================="
echo " Total configurations : ${total}"
echo " Passed               : ${passed}"
echo " Failed               : ${failed}"
echo "============================================="

echo "[INFO] Logs saved to ${LOG_DIR}/"

# --------------------------------------------------
# 5. FINAL EXIT STATUS
# --------------------------------------------------

if [[ "$failed" -ne 0 ]]; then

    echo "[FAIL] One or more FIFO depths failed."
    exit 1

fi

echo ""
echo "[PASS] ALL FIFO DEPTH CONFIGURATIONS PASSED"

exit 0