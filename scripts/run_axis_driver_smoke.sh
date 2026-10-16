#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_axis_driver_smoke.sh
#
# Description:
#   Compile and execute the AXI-Stream UVM integration test.
#
# Verification:
#   - UVM Sequence and Sequencer
#   - AXI-Stream Source Driver
#   - Input Monitor
#   - Output 0 and Output 1 Monitors
#   - Router Reference Model and Scoreboard
#   - Three-beat packet verification
#
# The script checks the UVM scoreboard results and
# rejects simulations with UVM errors or fatal reports.

set -euo pipefail

# --------------------------------------------------
# 1. Resolve project root
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

# --------------------------------------------------
# 2. Define build and log paths
# --------------------------------------------------

BUILD_DIR="obj_dir/axis_driver_smoke"

COMPILE_LOG="logs/axis_driver_compile.log"

SIM_LOG="logs/axis_driver_simulation.log"

# Create all required output directories.
mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 3. Compile UVM verification environment
# --------------------------------------------------

echo "[INFO] Compiling AXI-Stream UVM integration test..."

verilator \
  --binary \
  --timing \
  --trace \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_axis_driver_top \
  --Mdir "$BUILD_DIR" \
  -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
  +incdir+external/uvm/src \
  +incdir+tb/uvm \
  external/uvm/src/uvm_pkg.sv \
  tb/uvm/axis_if.sv \
  tb/uvm/axis_pkg.sv \
  rtl/sync_fifo.sv \
  rtl/apb_route_regs.sv \
  rtl/buffered_router.sv \
  tb/uvm/tb_axis_driver_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 4. Run UVM simulation
# --------------------------------------------------

echo "[INFO] Running UVM integration test..."

"./${BUILD_DIR}/Vtb_axis_driver_top" +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# --------------------------------------------------
# 5. Verify UVM test completion
# --------------------------------------------------

# The UVM test must reach its explicit PASS marker.
if ! grep -q "AXIS_DRIVER_SMOKE_PASS" "$SIM_LOG"; then

    echo "[FAIL] UVM test PASS marker not found."

    exit 1

fi

# --------------------------------------------------
# 6. Verify scoreboard transaction counts
# --------------------------------------------------

# Expected smoke-test behavior:
#   Input accepted beats : 3
#   Output 0 beats       : 3
#   Output 1 beats       : 0
#   Matched transactions : 3

EXPECTED_SUMMARY="Summary: input=3 output0=3 output1=0 matched=3"

if ! grep -Fq "$EXPECTED_SUMMARY" "$SIM_LOG"; then

    echo "[FAIL] UVM scoreboard transaction counts mismatch."

    exit 1

fi

echo "[PASS] UVM scoreboard transaction counts verified."

# --------------------------------------------------
# 7. Verify successful UVM report summary
# --------------------------------------------------

# UVM must report zero errors and zero fatal messages.
if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0([[:space:]]|$)' "$SIM_LOG"; then

    echo "[FAIL] UVM reported errors or missing error summary."

    exit 1

fi

if ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0([[:space:]]|$)' "$SIM_LOG"; then

    echo "[FAIL] UVM reported fatal errors or missing fatal summary."

    exit 1

fi

echo "[PASS] UVM report: zero errors and zero fatals."

# --------------------------------------------------
# 8. Final verification result
# --------------------------------------------------

echo ""
echo "============================================="
echo " AXI-STREAM UVM INTEGRATION TEST PASSED"
echo "============================================="
echo " Input transactions   : 3"
echo " Output 0 transactions: 3"
echo " Output 1 transactions: 0"
echo " Scoreboard matches   : 3"
echo " UVM errors           : 0"
echo " UVM fatals           : 0"
echo "============================================="

echo "[INFO] UVM integration completed successfully."