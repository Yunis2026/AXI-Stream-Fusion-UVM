#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# Purpose: Verify the AXI-Stream UVM transaction class.

set -euo pipefail

# Locate the repository root.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Separate this test from the original UVM smoke test.
BUILD_DIR="obj_dir/axis_item_smoke"
COMPILE_LOG="logs/axis_item_compile.log"
SIM_LOG="logs/axis_item_simulation.log"

mkdir -p "$BUILD_DIR" logs

echo "[INFO] Compiling AXI-Stream UVM transaction test..."

# Compile UVM first, followed by the AXI package
# and the transaction smoke-test top.
#
# Reuse the proven macOS UVM DPI-C and VPI settings.
verilator \
  --binary \
  --timing \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_axis_item_top \
  --Mdir "$BUILD_DIR" \
  -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
  +incdir+external/uvm/src \
  +incdir+tb/uvm \
  external/uvm/src/uvm_pkg.sv \
  tb/uvm/axis_pkg.sv \
  tb/uvm/tb_axis_item_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$COMPILE_LOG" 2>&1

echo "[INFO] Compilation successful."
echo "[INFO] Running AXI-Stream UVM transaction test..."

# Preserve the simulator exit status and save its output.
"./${BUILD_DIR}/Vtb_axis_item_top" +UVM_NO_RELNOTES \
  | tee "$SIM_LOG"

# Require an explicit PASS marker from the UVM test.
if ! grep -q "AXIS_ITEM_SMOKE_PASS" "$SIM_LOG"; then
    echo "[FAIL] UVM transaction PASS marker not found."
    exit 1
fi

echo "[INFO] AXI-Stream UVM transaction smoke test passed."
