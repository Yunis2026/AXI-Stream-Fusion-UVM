#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_dynamic_uvm.sh
#
# Description:
#   Compile and run combined APB/AXI-Stream UVM tests.
#
# Verification objectives:
#   - APB-controlled route selection
#   - AXI packets sent to both outputs
#   - Packet-level route locking
#   - Mid-packet APB configuration updates
#   - Independent scoreboard comparisons

set -euo pipefail

# --------------------------------------------------
# 1. Resolve the project root
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

# --------------------------------------------------
# 2. Define build and log paths
# --------------------------------------------------

BUILD_DIR="obj_dir/router_dynamic_uvm"

COMPILE_LOG="logs/router_dynamic_uvm_compile.log"
SIM_LOG="logs/router_dynamic_uvm_simulation.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 3. Compile the combined verification environment
# --------------------------------------------------

echo "[INFO] Compiling combined APB/AXI UVM test..."

verilator \
  --binary \
  --timing \
  --trace \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_router_dynamic_uvm_top \
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
  rtl/sync_fifo.sv \
  rtl/apb_route_regs.sv \
  rtl/buffered_router.sv \
  tb/uvm/tb_router_dynamic_uvm_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 4. Execute the simulation
# --------------------------------------------------

echo "[INFO] Running combined APB/AXI UVM test..."

"./${BUILD_DIR}/Vtb_router_dynamic_uvm_top" +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# --------------------------------------------------
# 5. Check the UVM PASS marker
# --------------------------------------------------

if ! grep -Fq "ROUTER_DYNAMIC_UVM_PASS" "$SIM_LOG"; then
    echo "[FAIL] Dynamic routing PASS marker missing."
    exit 1
fi

# --------------------------------------------------
# 6. Check the complete scoreboard summary
# --------------------------------------------------

EXPECTED_SUMMARY="Summary: input=11 output0=6 output1=5 matched=11 apb=6 errors=1"

if ! grep -Fq "$EXPECTED_SUMMARY" "$SIM_LOG"; then
    echo "[FAIL] Dynamic routing scoreboard mismatch."
    exit 1
fi

echo "[PASS] Dynamic routing scoreboard counts verified."

# --------------------------------------------------
# 7. Check UVM report statistics
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
# 8. Final result
# --------------------------------------------------

echo ""
echo "============================================="
echo " DYNAMIC ROUTER UVM VERIFICATION PASSED"
echo "============================================="
echo " Input AXI beats        : 11"
echo " Output 0 AXI beats     : 6"
echo " Output 1 AXI beats     : 5"
echo " APB transactions       : 6"
echo " APB error responses    : 1"
echo " UVM errors             : 0"
echo " UVM fatals             : 0"
echo "============================================="