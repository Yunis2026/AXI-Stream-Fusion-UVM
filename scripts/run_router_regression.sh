#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_regression.sh
#
# Description:
#   Execute the Router UVM stress test across multiple
#   reproducible random seeds.
#
# Features:
#   - Multiple seed execution
#   - Independent logs for every seed
#   - Automatic PASS/FAIL classification
#   - Scoreboard summary collection
#   - Final regression statistics
#
# Usage:
#   ./scripts/run_router_regression.sh
#
#   SEEDS="101 202 303" ./scripts/run_router_regression.sh

set -euo pipefail

# --------------------------------------------------
# 1. Project configuration
# --------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Default regression seeds.
SEEDS="${SEEDS:-12345 2026 74018 314159 271828}"

REGRESSION_DIR="logs/regression"
SUMMARY_FILE="${REGRESSION_DIR}/regression_summary.txt"

mkdir -p "$REGRESSION_DIR"

# --------------------------------------------------
# 2. Initialize regression statistics
# --------------------------------------------------

total=0
passed=0
failed=0

echo "============================================="
echo " AXI-STREAM FUSION UVM REGRESSION"
echo "============================================="
echo " Seeds: ${SEEDS}"
echo "============================================="
echo ""

{
    echo "AXI-Stream Fusion UVM Regression"
    echo "Seeds: ${SEEDS}"
    echo ""
} > "$SUMMARY_FILE"

# --------------------------------------------------
# 3. Execute each seed
# --------------------------------------------------

for seed in $SEEDS; do

    # Only allow positive integer seed strings.
    if [[ ! "$seed" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid random seed: $seed"
        exit 2
    fi

    total=$((total + 1))

    LOG_FILE="${REGRESSION_DIR}/seed_${seed}.log"

    echo "---------------------------------------------"
    echo "[RUN] Seed: ${seed}"
    echo "---------------------------------------------"

    # Run the existing single-seed stress script.
    # Capture its complete output into a dedicated log.
    if SEED="$seed" ./scripts/run_router_stress_uvm.sh \
        > "$LOG_FILE" 2>&1; then

        # Require the final completion marker.
        if grep -Fq "ROUTER_STRESS_UVM_PASS" "$LOG_FILE" &&
           grep -Fq "ROUTER UVM STRESS VERIFICATION PASSED" "$LOG_FILE"; then

            passed=$((passed + 1))

            echo "[PASS] Seed ${seed}"

            # Extract the simulation scoreboard summary.
            SUMMARY_LINE="$(
                grep -F "STRESS_SUMMARY" "$LOG_FILE" | tail -n 1
            )"

            echo "$SUMMARY_LINE"

            {
                echo "[PASS] Seed ${seed}"
                echo "$SUMMARY_LINE"
                echo ""
            } >> "$SUMMARY_FILE"

        else

            failed=$((failed + 1))

            echo "[FAIL] Seed ${seed}: PASS marker missing"

            {
                echo "[FAIL] Seed ${seed}: PASS marker missing"
                echo ""
            } >> "$SUMMARY_FILE"

        fi

    else

        failed=$((failed + 1))

        echo "[FAIL] Seed ${seed}: compilation or simulation failure"

        # Show the end of the failed simulation log.
        tail -n 20 "$LOG_FILE"

        {
            echo "[FAIL] Seed ${seed}"
            echo "Log: ${LOG_FILE}"
            echo ""
        } >> "$SUMMARY_FILE"

    fi

    echo ""

done

# --------------------------------------------------
# 4. Final regression statistics
# --------------------------------------------------

echo "============================================="
echo " UVM REGRESSION SUMMARY"
echo "============================================="
echo " Total seeds : ${total}"
echo " Passed      : ${passed}"
echo " Failed      : ${failed}"
echo "============================================="

{
    echo "============================================="
    echo "Regression Results"
    echo "============================================="
    echo "Total seeds: ${total}"
    echo "Passed:      ${passed}"
    echo "Failed:      ${failed}"
} >> "$SUMMARY_FILE"

echo "[INFO] Summary saved to ${SUMMARY_FILE}"
echo "[INFO] Individual logs saved to ${REGRESSION_DIR}/"

# --------------------------------------------------
# 5. Regression exit status
# --------------------------------------------------

if [[ "$failed" -ne 0 ]]; then

    echo "[FAIL] One or more UVM regression seeds failed."
    exit 1

fi

echo ""
echo "[PASS] ALL UVM REGRESSION SEEDS PASSED"

exit 0