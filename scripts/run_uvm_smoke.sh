#!/usr/bin/env bash
# AXI-Stream Fusion: UVM Verification Platform
# Compile and run the UVM smoke test using Verilator.
# DPI-C and VPI are enabled for the local macOS environment.

set -euo pipefail

# Resolve the project root independently of the current directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Define build and log paths.
BUILD_DIR="obj_dir/uvm_dpi_fixed"
LOG_FILE="logs/uvm_smoke_compile.log"

mkdir -p "$BUILD_DIR" logs

echo "[INFO] Compiling UVM smoke test..."

# Compile UVM SystemVerilog and DPI-C sources.
# UVM_NO_MALLOC avoids the Linux-specific malloc.h dependency.
verilator \
  --binary \
  --timing \
  --vpi \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -j 4 \
  --top-module tb_uvm_top \
  --Mdir "$BUILD_DIR" \
  -CFLAGS "-DUVM_NO_MALLOC -I${PROJECT_ROOT}/external/uvm/src/dpi" \
  +incdir+external/uvm/src \
  +incdir+uvm/tests \
  external/uvm/src/uvm_pkg.sv \
  tb/tb_uvm_top.sv \
  external/uvm/src/dpi/uvm_dpi.cc \
  > "$LOG_FILE" 2>&1

echo "[INFO] Compilation successful."
echo "[INFO] Running UVM smoke test..."

# Execute the compiled simulation.
"./${BUILD_DIR}/Vtb_uvm_top" +UVM_NO_RELNOTES
