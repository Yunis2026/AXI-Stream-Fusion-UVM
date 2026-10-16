#!/usr/bin/env bash
# Project: AXI-Stream Fusion - UVM Verification Platform
# File: run_router_coverage_regression.sh
#
# Description:
#   Run multi-seed functional coverage regression
#   and generate aggregated coverage reports.
#
# Outputs:
#   - Individual simulation logs
#   - Per-seed regression execution logs
#   - Coverage regression CSV
#   - Merged functional coverage Markdown report
#
# Usage:
#   ./scripts/run_router_coverage_regression.sh
#
#   SEEDS="101 202 303" \
#       ./scripts/run_router_coverage_regression.sh
#
#   MIN_COVERAGE=90 \
#       ./scripts/run_router_coverage_regression.sh

set -euo pipefail

# --------------------------------------------------
# 1. Resolve project directories
# --------------------------------------------------

PROJECT_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

cd "$PROJECT_ROOT"

# --------------------------------------------------
# 2. Regression configuration
# --------------------------------------------------

SEEDS="${SEEDS:-12345 2026 74018 314159 271828}"

MIN_COVERAGE="${MIN_COVERAGE:-100}"

RUN_LOG_DIR="logs/coverage_regression"

REPORT_DIR="reports/coverage"

MANIFEST="${RUN_LOG_DIR}/run_manifest.tsv"

CSV_REPORT="${REPORT_DIR}/coverage_regression.csv"

MARKDOWN_REPORT="${REPORT_DIR}/coverage_regression.md"

mkdir -p "$RUN_LOG_DIR"
mkdir -p "$REPORT_DIR"

# --------------------------------------------------
# 3. Initialize regression manifest
# --------------------------------------------------

printf "seed\tstatus\tlog\n" > "$MANIFEST"

echo ""
echo "================================================="
echo " AXI-STREAM FUSION COVERAGE REGRESSION"
echo "================================================="
echo " Seeds            : ${SEEDS}"
echo " Coverage target  : ${MIN_COVERAGE}%"
echo "================================================="
echo ""

# --------------------------------------------------
# 4. Execute coverage test for every seed
# --------------------------------------------------

total=0
runner_passed=0
runner_failed=0

for seed in $SEEDS; do

    # Reject invalid seed strings.
    if [[ ! "$seed" =~ ^[0-9]+$ ]]; then

        echo "[ERROR] Invalid random seed: $seed"
        exit 2

    fi

    total=$((total + 1))

    RUN_LOG="${RUN_LOG_DIR}/seed_${seed}_runner.log"

    SIM_LOG="logs/router_coverage_seed_${seed}.log"

    echo "-------------------------------------------------"
    echo "[RUN] Seed: ${seed}"
    echo "-------------------------------------------------"

    # Each invocation uses the existing, independently
    # verified coverage test runner.
    #
    # Save all output from the runner separately.
    if SEED="$seed" ./scripts/run_router_coverage_uvm.sh \
        > "$RUN_LOG" 2>&1; then

        runner_passed=$((runner_passed + 1))

        echo "[PASS] Simulation completed: ${seed}"

        printf "%s\tPASS\t%s\n" \
            "$seed" "$SIM_LOG" >> "$MANIFEST"

        # Display the coverage summary when available.
        grep -F "COVERAGE_SUMMARY hit=" "$SIM_LOG" \
            | tail -n 1 || true

    else

        runner_failed=$((runner_failed + 1))

        echo "[FAIL] Simulation failed: ${seed}"

        printf "%s\tFAIL\t%s\n" \
            "$seed" "$SIM_LOG" >> "$MANIFEST"

        echo "[INFO] Last 15 runner log lines:"

        tail -n 15 "$RUN_LOG" || true

    fi

    echo ""

done

# --------------------------------------------------
# 5. Analyze and aggregate coverage
# --------------------------------------------------

echo "[INFO] Analyzing functional coverage bins..."

# The Python analyzer checks:
#   - Original UVM PASS markers
#   - UVM error and fatal statistics
#   - Scoreboard transaction consistency
#   - Packet and APB coverage consistency
#   - Per-seed 18-bin coverage
#   - Merged bin coverage across passing seeds
#
# Preserve the analyzer exit code so reports remain
# accessible even when coverage is incomplete.

analysis_status=0

python3 scripts/aggregate_router_coverage.py \
    --manifest "$MANIFEST" \
    --csv "$CSV_REPORT" \
    --markdown "$MARKDOWN_REPORT" \
    --min-coverage "$MIN_COVERAGE" \
    || analysis_status=$?

# --------------------------------------------------
# 6. Display output locations
# --------------------------------------------------

echo ""
echo "-------------------------------------------------"
echo " COVERAGE REGRESSION ARTIFACTS"
echo "-------------------------------------------------"
echo " Manifest:"
echo "   ${MANIFEST}"
echo ""
echo " Per-seed CSV:"
echo "   ${CSV_REPORT}"
echo ""
echo " Merged Markdown report:"
echo "   ${MARKDOWN_REPORT}"
echo ""
echo " Individual runner logs:"
echo "   ${RUN_LOG_DIR}/"
echo "-------------------------------------------------"

# --------------------------------------------------
# 7. Final regression result
# --------------------------------------------------

if [[ "$analysis_status" -ne 0 ]]; then

    echo "[FAIL] Coverage regression did not meet its goal."
    exit "$analysis_status"

fi

if [[ "$runner_failed" -ne 0 ]]; then

    echo "[FAIL] One or more simulation runners failed."
    exit 1

fi

echo ""
echo "================================================="
echo " MULTI-SEED COVERAGE REGRESSION PASSED"
echo "================================================="
echo " Total seeds       : ${total}"
echo " Passed runners    : ${runner_passed}"
echo " Failed runners    : ${runner_failed}"
echo " Coverage target   : ${MIN_COVERAGE}%"
echo "================================================="

exit 0