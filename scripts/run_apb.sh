#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# Purpose: Compile and run APB register directed tests.

set -euo pipefail

# Locate the project root directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create simulation output directories.
mkdir -p obj_dir/apb waves logs

echo "[INFO] Compiling APB testbench..."

# Compile the APB RTL and self-checking testbench.
verilator \
    --binary \
    --timing \
    --trace \
    -Wall \
    -Wno-fatal \
    -j 4 \
    --top-module tb_apb_regs \
    --Mdir obj_dir/apb \
    rtl/apb_route_regs.sv \
    tb/tb_apb_regs.sv \
    > logs/apb_compile.log 2>&1

echo "[INFO] Running APB directed tests..."

# Execute the generated simulation binary.
./obj_dir/apb/Vtb_apb_regs

echo "[INFO] APB simulation completed."
