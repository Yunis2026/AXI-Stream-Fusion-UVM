#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_apb_uvm_smoke.sh
#
# Description:
#   Compile and run the APB UVM register verification test.
#
# Reuses the proven macOS Verilator + UVM + DPI-C toolchain.

set -euo pipefail

# --------------------------------------------------
# 1. Resolve project root
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# --------------------------------------------------
# 2. Build and log directories
# --------------------------------------------------

BUILD_DIR="obj_dir/apb_uvm_smoke"

COMPILE_LOG="logs/apb_uvm_compile.log"
SIM_LOG="logs/apb_uvm_simulation.log"

mkdir -p "$BUILD_DIR" logs waves

# --------------------------------------------------
# 3. Compile APB UVM testbench
# --------------------------------------------------

echo "[INFO] Compiling APB UVM verification environment..."

verilator \
  --binary \
  --timing \
  --trace \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_apb_uvm_top \
  --Mdir "$BUILD_DIR" \
  -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
  +incdir+external/uvm/src \
  +incdir+tb/uvm \
  external/uvm/src/uvm_pkg.sv \
  tb/uvm/apb_if.sv \
  tb/uvm/apb_pkg.sv \
  rtl/apb_route_regs.sv \
  tb/uvm/tb_apb_uvm_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."

# --------------------------------------------------
# 4. Execute UVM simulation
# --------------------------------------------------

echo "[INFO] Running APB UVM directed tests..."

"./${BUILD_DIR}/Vtb_apb_uvm_top" +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# --------------------------------------------------
# 5. Verify UVM completion markers
# --------------------------------------------------

if ! grep -Fq "APB_UVM_SEQUENCE_PASS" "$SIM_LOG"; then
    echo "[FAIL] APB sequence PASS marker not found."
    exit 1
fi

if ! grep -Fq "APB_UVM_SMOKE_PASS" "$SIM_LOG"; then
    echo "[FAIL] APB UVM test PASS marker not found."
    exit 1
fi

if ! grep -Fq "[PASS] APB transactions verified: 10" "$SIM_LOG"; then
    echo "[FAIL] APB transaction count mismatch."
    exit 1
fi

# --------------------------------------------------
# 6. Verify UVM report summary
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
echo " APB UVM VERIFICATION PASSED"
echo "============================================="
echo " Checked APB transactions: 10"
echo " UVM errors              : 0"
echo " UVM fatals              : 0"
echo "============================================="

echo "[INFO] APB UVM smoke test completed successfully."