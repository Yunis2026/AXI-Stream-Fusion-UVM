#!/usr/bin/env python3
"""
Project : AXI-Stream Fusion - UVM Verification Platform
File    : aggregate_router_coverage.py

Description:
    Parse UVM functional coverage logs and aggregate
    coverage bins across multiple random seeds.

Outputs:
    - Per-seed coverage CSV
    - Merged coverage Markdown report

Requirements:
    Python 3.9+ standard library only.
"""

import argparse
import csv
import re
import sys
from pathlib import Path


# --------------------------------------------------
# 1. Functional coverage bin definitions
# --------------------------------------------------

BIN_DEFINITIONS = [
    ("Route 0 packet", "route0_packets"),
    ("Route 1 packet", "route1_packets"),

    ("Route 0 x short packet", "route0_short"),
    ("Route 0 x medium packet", "route0_medium"),
    ("Route 0 x long packet", "route0_long"),

    ("Route 1 x short packet", "route1_short"),
    ("Route 1 x medium packet", "route1_medium"),
    ("Route 1 x long packet", "route1_long"),

    ("Route 0 x full final TKEEP", "route0_full"),
    ("Route 0 x partial final TKEEP", "route0_partial"),

    ("Route 1 x full final TKEEP", "route1_full"),
    ("Route 1 x partial final TKEEP", "route1_partial"),

    ("Invalid APB access", "invalid_apb"),
    ("Mid-packet APB route update", "midpacket_update"),

    ("Source backpressure", "source_stall"),
    ("Output 0 backpressure", "output0_stall"),
    ("Output 1 backpressure", "output1_stall"),

    ("Simultaneous output pending", "dual_pending"),
]

TOTAL_BINS = len(BIN_DEFINITIONS)


# --------------------------------------------------
# 2. Regular expression helpers
# --------------------------------------------------

def extract_last(pattern, text, description):
    """Return the last match for a required log entry."""

    matches = list(re.finditer(pattern, text, re.MULTILINE))

    if not matches:
        raise ValueError(
            f"Missing required log entry: {description}"
        )

    return matches[-1]


def extract_numbers(pattern, text, description):
    """Extract all numeric capture groups as integers."""

    match = extract_last(pattern, text, description)

    return tuple(int(value) for value in match.groups())


# --------------------------------------------------
# 3. Parse one successful UVM coverage log
# --------------------------------------------------

def parse_coverage_log(log_path):
    """Validate a coverage run and collect bin counts."""

    path = Path(log_path)

    if not path.is_file():
        raise ValueError(f"Log file not found: {path}")

    text = path.read_text(
        encoding="utf-8",
        errors="replace"
    )

    # Require the complete inherited stress test.
    if "ROUTER_STRESS_UVM_PASS" not in text:
        raise ValueError("Stress test PASS marker missing")

    # Require the coverage test completion marker.
    if "ROUTER_COVERAGE_UVM_PASS" not in text:
        raise ValueError("Coverage test PASS marker missing")

    # Reject logs without clean UVM report statistics.
    if not re.search(
        r"^UVM_ERROR\s*:\s*0\s*$",
        text,
        re.MULTILINE
    ):
        raise ValueError("UVM_ERROR is not zero")

    if not re.search(
        r"^UVM_FATAL\s*:\s*0\s*$",
        text,
        re.MULTILINE
    ):
        raise ValueError("UVM_FATAL is not zero")

    # ----------------------------------------------
    # Packet counters
    # ----------------------------------------------

    route0, route1, total_packets = extract_numbers(
        r"Packets: route0=(\d+) route1=(\d+) total=(\d+)",
        text,
        "Packet coverage"
    )

    if route0 + route1 != total_packets:
        raise ValueError("Packet coverage total mismatch")

    # The current inherited stress test generates:
    # 1 FIFO-full packet + 2 independent-output
    # packets + 30 random packets.
    if total_packets != 33:
        raise ValueError(
            f"Expected 33 packets, got {total_packets}"
        )

    # ----------------------------------------------
    # Route x length cross coverage
    # ----------------------------------------------

    r0_short, r0_medium, r0_long = extract_numbers(
        r"ROUTE_0_LENGTH short=(\d+) medium=(\d+) long=(\d+)",
        text,
        "Route 0 packet length coverage"
    )

    r1_short, r1_medium, r1_long = extract_numbers(
        r"ROUTE_1_LENGTH short=(\d+) medium=(\d+) long=(\d+)",
        text,
        "Route 1 packet length coverage"
    )

    if r0_short + r0_medium + r0_long != route0:
        raise ValueError("Route 0 length totals mismatch")

    if r1_short + r1_medium + r1_long != route1:
        raise ValueError("Route 1 length totals mismatch")

    # ----------------------------------------------
    # Route x final TKEEP cross coverage
    # ----------------------------------------------

    r0_full, r0_partial = extract_numbers(
        r"ROUTE_0_FINAL_KEEP full=(\d+) partial=(\d+)",
        text,
        "Route 0 final TKEEP coverage"
    )

    r1_full, r1_partial = extract_numbers(
        r"ROUTE_1_FINAL_KEEP full=(\d+) partial=(\d+)",
        text,
        "Route 1 final TKEEP coverage"
    )

    if r0_full + r0_partial != route0:
        raise ValueError("Route 0 TKEEP totals mismatch")

    if r1_full + r1_partial != route1:
        raise ValueError("Route 1 TKEEP totals mismatch")

    # ----------------------------------------------
    # APB coverage
    # ----------------------------------------------

    (
        apb_total,
        valid_writes,
        invalid_apb,
        midpacket_update
    ) = extract_numbers(
        r"APB_COVERAGE total=(\d+) valid_writes=(\d+) "
        r"invalid_accesses=(\d+) midpacket_updates=(\d+)",
        text,
        "APB coverage"
    )

    # ----------------------------------------------
    # Backpressure coverage
    # ----------------------------------------------

    (
        source_stall,
        output0_stall,
        output1_stall,
        dual_pending
    ) = extract_numbers(
        r"STALL_COVERAGE source=(\d+) out0=(\d+) "
        r"out1=(\d+) dual_pending=(\d+)",
        text,
        "Stall coverage"
    )

    # ----------------------------------------------
    # Parse the original scoreboard summary
    # ----------------------------------------------

    (
        input_beats,
        output0_beats,
        output1_beats,
        matched_beats,
        scoreboard_apb,
        scoreboard_errors
    ) = extract_numbers(
        r"Summary: input=(\d+) output0=(\d+) "
        r"output1=(\d+) matched=(\d+) "
        r"apb=(\d+) errors=(\d+)",
        text,
        "Dynamic router scoreboard summary"
    )

    if input_beats != matched_beats:
        raise ValueError("Input/matched beat count mismatch")

    if output0_beats + output1_beats != input_beats:
        raise ValueError("Output beat totals mismatch")

    if scoreboard_apb != apb_total:
        raise ValueError("APB transaction totals mismatch")

    if scoreboard_errors != invalid_apb:
        raise ValueError("APB error coverage mismatch")

    # ----------------------------------------------
    # Construct the complete set of 18 bins
    # ----------------------------------------------

    bins = {
        "route0_packets": route0,
        "route1_packets": route1,

        "route0_short": r0_short,
        "route0_medium": r0_medium,
        "route0_long": r0_long,

        "route1_short": r1_short,
        "route1_medium": r1_medium,
        "route1_long": r1_long,

        "route0_full": r0_full,
        "route0_partial": r0_partial,

        "route1_full": r1_full,
        "route1_partial": r1_partial,

        "invalid_apb": invalid_apb,
        "midpacket_update": midpacket_update,

        "source_stall": source_stall,
        "output0_stall": output0_stall,
        "output1_stall": output1_stall,

        "dual_pending": dual_pending,
    }

    # ----------------------------------------------
    # Verify the reported coverage percentage
    # ----------------------------------------------

    coverage_match = extract_last(
        r"COVERAGE_SUMMARY hit=(\d+) total=(\d+) "
        r"percentage=([0-9.]+)",
        text,
        "Coverage summary"
    )

    reported_hits = int(coverage_match.group(1))
    reported_total = int(coverage_match.group(2))
    reported_percentage = float(coverage_match.group(3))

    calculated_hits = sum(
        1 for count in bins.values() if count > 0
    )

    calculated_percentage = (
        100.0 * calculated_hits / TOTAL_BINS
    )

    if reported_total != TOTAL_BINS:
        raise ValueError("Coverage bin definition mismatch")

    if reported_hits != calculated_hits:
        raise ValueError("Coverage hit count mismatch")

    if abs(
        reported_percentage - calculated_percentage
    ) > 0.02:
        raise ValueError("Coverage percentage mismatch")

    return {
        "bins": bins,
        "hits": calculated_hits,
        "percentage": calculated_percentage,
        "packets": total_packets,
        "axi_beats": input_beats,
        "output0_beats": output0_beats,
        "output1_beats": output1_beats,
        "apb_transfers": apb_total,
        "apb_errors": invalid_apb,
        "valid_writes": valid_writes,
    }


# --------------------------------------------------
# 4. Read regression manifest
# --------------------------------------------------

def read_manifest(manifest_path):
    """Read seed status and log paths from TSV."""

    with Path(manifest_path).open(
        "r",
        encoding="utf-8",
        newline=""
    ) as handle:

        reader = csv.DictReader(
            handle,
            delimiter="\t"
        )

        required = {"seed", "status", "log"}

        if not required.issubset(reader.fieldnames or []):
            raise ValueError(
                "Manifest requires seed, status and log columns"
            )

        rows = list(reader)

    if not rows:
        raise ValueError("Regression manifest is empty")

    seeds = [row["seed"] for row in rows]

    if len(seeds) != len(set(seeds)):
        raise ValueError("Duplicate seeds in manifest")

    return rows


# --------------------------------------------------
# 5. Execute log analysis
# --------------------------------------------------

def analyze_runs(manifest_rows):
    """Analyze every seed without hiding failed runs."""

    results = []

    for row in manifest_rows:

        seed = row["seed"]
        status = row["status"]
        log_path = row["log"]

        result = {
            "seed": seed,
            "status": "FAIL",
            "log": log_path,
            "error": "",
            "data": None,
        }

        if status != "PASS":
            result["error"] = (
                "Simulation or runner returned failure"
            )

        else:
            try:
                result["data"] = parse_coverage_log(
                    log_path
                )

                result["status"] = "PASS"

            except (OSError, ValueError) as error:
                result["error"] = str(error)

        results.append(result)

    return results


# --------------------------------------------------
# 6. Merge functional coverage bins
# --------------------------------------------------

def merge_coverage(results):
    """Sum bin hits across successfully verified runs."""

    merged = {
        key: 0
        for _, key in BIN_DEFINITIONS
    }

    for result in results:

        if result["status"] != "PASS":
            continue

        bins = result["data"]["bins"]

        for key in merged:
            merged[key] += bins[key]

    hits = sum(
        1 for value in merged.values() if value > 0
    )

    percentage = 100.0 * hits / TOTAL_BINS

    return merged, hits, percentage


# --------------------------------------------------
# 7. Export per-seed CSV
# --------------------------------------------------

def write_csv(results, output_path):
    """Generate a machine-readable regression summary."""

    output = Path(output_path)

    output.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    fields = [
        "seed",
        "status",
        "coverage_hits",
        "coverage_total",
        "coverage_percent",
        "packets",
        "axi_beats",
        "output0_beats",
        "output1_beats",
        "apb_transfers",
        "apb_errors",
        "log",
        "error",
    ]

    with output.open(
        "w",
        encoding="utf-8",
        newline=""
    ) as handle:

        writer = csv.DictWriter(
            handle,
            fieldnames=fields
        )

        writer.writeheader()

        for result in results:

            data = result["data"]

            csv_row = {
                "seed": result["seed"],
                "status": result["status"],
                "log": result["log"],
                "error": result["error"],
            }

            if data is not None:

                csv_row.update({
                    "coverage_hits": data["hits"],
                    "coverage_total": TOTAL_BINS,
                    "coverage_percent": (
                        f"{data['percentage']:.2f}"
                    ),
                    "packets": data["packets"],
                    "axi_beats": data["axi_beats"],
                    "output0_beats": data["output0_beats"],
                    "output1_beats": data["output1_beats"],
                    "apb_transfers": data["apb_transfers"],
                    "apb_errors": data["apb_errors"],
                })

            writer.writerow(csv_row)


# --------------------------------------------------
# 8. Export Markdown verification report
# --------------------------------------------------

def write_markdown(
    results,
    merged,
    merged_hits,
    merged_percentage,
    output_path
):
    """Generate a human-readable coverage report."""

    output = Path(output_path)

    output.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    passed = sum(
        1 for row in results if row["status"] == "PASS"
    )

    failed = len(results) - passed

    lines = [
        "# AXI-Stream Fusion: Coverage Regression Report",
        "",
        "## Regression Summary",
        "",
        f"- Total seeds: **{len(results)}**",
        f"- Passed: **{passed}**",
        f"- Failed: **{failed}**",
        (
            f"- Merged functional coverage: "
            f"**{merged_hits}/{TOTAL_BINS} "
            f"({merged_percentage:.2f}%)**"
        ),
        "",
        "## Per-Seed Results",
        "",
        (
            "| Seed | Status | Coverage | "
            "AXI Beats | Packets | APB |"
        ),
        "|---|---|---:|---:|---:|---:|",
    ]

    for result in results:

        data = result["data"]

        if data is None:

            lines.append(
                f"| {result['seed']} | FAIL | N/A | "
                "N/A | N/A | N/A |"
            )

        else:

            lines.append(
                f"| {result['seed']} | PASS | "
                f"{data['hits']}/{TOTAL_BINS} "
                f"({data['percentage']:.2f}%) | "
                f"{data['axi_beats']} | "
                f"{data['packets']} | "
                f"{data['apb_transfers']} |"
            )

    lines.extend([
        "",
        "## Merged Functional Coverage Matrix",
        "",
        "| Functional Bin | Total Hits | Status |",
        "|---|---:|---|",
    ])

    for name, key in BIN_DEFINITIONS:

        hit_count = merged[key]

        status = (
            "HIT" if hit_count > 0 else "MISS"
        )

        lines.append(
            f"| {name} | {hit_count} | {status} |"
        )

    lines.extend([
        "",
        "## Coverage Holes",
        "",
    ])

    missing = [
        name
        for name, key in BIN_DEFINITIONS
        if merged[key] == 0
    ]

    if missing:

        for name in missing:
            lines.append(f"- {name}")

    else:

        lines.append(
            "No uncovered bins within the "
            "defined 18-bin functional coverage model."
        )

    failures = [
        row
        for row in results
        if row["status"] != "PASS"
    ]

    lines.extend([
        "",
        "## Failed Runs",
        "",
    ])

    if failures:

        for row in failures:

            lines.append(
                f"- Seed {row['seed']}: "
                f"{row['error']} "
                f"(log: `{row['log']}`)"
            )

    else:

        lines.append(
            "All requested regression seeds passed."
        )

    lines.extend([
        "",
        "## Methodology and Limitations",
        "",
        (
            "- Per-seed functional coverage is computed "
            "from 18 explicitly defined transaction-level bins."
        ),
        (
            "- Merged coverage uses a logical union: "
            "a bin is covered if at least one passing run hits it."
        ),
        (
            "- Total Hits is the sum of observed bin counts "
            "across passing runs, not the number of unique bins."
        ),
        (
            "- Failed runs are excluded from merged coverage "
            "and remain visible in the regression results."
        ),
        (
            "- This report does not represent RTL code coverage, "
            "native SV covergroups, UCIS, or exhaustive verification."
        ),
        "",
    ])

    output.write_text(
        "\n".join(lines),
        encoding="utf-8"
    )


# --------------------------------------------------
# 9. Command-line entry point
# --------------------------------------------------

def main():
    """Generate regression results and enforce the goal."""

    parser = argparse.ArgumentParser(
        description=(
            "Aggregate AXI-Stream Fusion UVM "
            "functional coverage across seeds."
        )
    )

    parser.add_argument(
        "--manifest",
        required=True
    )

    parser.add_argument(
        "--csv",
        required=True
    )

    parser.add_argument(
        "--markdown",
        required=True
    )

    parser.add_argument(
        "--min-coverage",
        type=float,
        default=100.0
    )

    args = parser.parse_args()

    if not 0.0 <= args.min_coverage <= 100.0:
        parser.error(
            "--min-coverage must be between 0 and 100"
        )

    try:
        manifest = read_manifest(args.manifest)

        results = analyze_runs(manifest)

        merged, hits, percentage = merge_coverage(
            results
        )

        write_csv(
            results,
            args.csv
        )

        write_markdown(
            results,
            merged,
            hits,
            percentage,
            args.markdown
        )

    except (OSError, ValueError) as error:

        print(
            f"[ERROR] Coverage aggregation: {error}",
            file=sys.stderr
        )

        return 2

    passed = sum(
        1 for row in results if row["status"] == "PASS"
    )

    failed = len(results) - passed

    print()
    print("=" * 57)
    print(" AXI-STREAM FUSION COVERAGE REGRESSION")
    print("=" * 57)

    for result in results:

        if result["status"] == "PASS":

            data = result["data"]

            print(
                f"[PASS] Seed {result['seed']}: "
                f"{data['hits']}/{TOTAL_BINS} "
                f"({data['percentage']:.2f}%)"
            )

        else:

            print(
                f"[FAIL] Seed {result['seed']}: "
                f"{result['error']}"
            )

    print("-" * 57)
    print(f" Total seeds          : {len(results)}")
    print(f" Passed               : {passed}")
    print(f" Failed               : {failed}")
    print(
        f" Merged coverage      : "
        f"{hits}/{TOTAL_BINS} ({percentage:.2f}%)"
    )
    print(
        f" Required coverage    : "
        f"{args.min_coverage:.2f}%"
    )
    print("=" * 57)

    print(f"[INFO] CSV report: {args.csv}")
    print(f"[INFO] Markdown report: {args.markdown}")

    if failed > 0:

        print(
            "[FAIL] One or more coverage runs failed."
        )

        return 1

    if percentage + 1e-9 < args.min_coverage:

        print(
            "[FAIL] Merged functional coverage "
            "is below the required threshold."
        )

        return 1

    print(
        "[PASS] COVERAGE_REGRESSION_COMPLETE"
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())