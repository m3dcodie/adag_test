#!/usr/bin/env python3
"""
benchmark/run_benchmark.py — Multi-model accuracy and cost comparison for adag.

For each model defined in models.yaml, runs `adag scan` against every test case
in test_cases/, then computes TP, FP, FN, TN, Recall, Precision, F1, and
estimated cost per scan.

Usage:
    # From repo root (venv must be active):
    python benchmark/run_benchmark.py

    # With custom paths:
    python benchmark/run_benchmark.py \\
        --models benchmark/models.yaml \\
        --test-cases test_cases/ \\
        --output benchmark/results/

    # Dry run (print plan, no API calls):
    python benchmark/run_benchmark.py --dry-run

Metrics:
    Recall    = TP / (TP + FN)   — most important: did we catch violations?
    Precision = TP / (TP + FP)   — did we flag things correctly?
    F1        = harmonic mean of Recall and Precision
    Accuracy  = (TP + TN) / total

Classification per test case:
    TP — expected FAIL, model found the expected policy violation
    FN — expected FAIL, model missed the expected policy violation  ← dangerous
    TN — expected PASS, model reported no violations
    FP — expected PASS, model flagged a spurious violation

Cost estimation:
    Parsed from stderr log lines emitted by core.cost_tracker:
        [COST] provider=X model=Y agent=Z input_tokens=N output_tokens=N estimated_cost_usd=$N
    All [COST] lines for a scan are summed (intake + auditor agents).
    No arch_agent changes required — the cost tracker already emits these.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("PyYAML required. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

def load_models(path: Path) -> list[dict]:
    with open(path) as f:
        config = yaml.safe_load(f)
    return config["models"]


def load_test_cases(test_cases_dir: Path) -> list[dict]:
    cases = []
    for tc_dir in sorted(p for p in test_cases_dir.iterdir() if p.is_dir()):
        expected_path = tc_dir / "expected.json"
        main_tf = tc_dir / "main.tf"
        if not expected_path.exists() or not main_tf.exists():
            continue
        with open(expected_path) as f:
            expected = json.load(f)
        cases.append({
            "name": tc_dir.name,
            "dir": tc_dir,
            "main_tf": main_tf,
            "expected": expected,
        })
    return cases


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_adag_scan(
    main_tf: Path,
    model_env: dict[str, str],
    adag_exe: str = "adag",
    timeout: int = 120,
) -> tuple[dict | None, float, str, str]:
    """
    Invoke `adag scan <main_tf> --no-rag --format json`.

    Returns (parsed_output_dict, elapsed_seconds, raw_stdout_or_error_msg, stderr).
    parsed_output_dict is None on scan error or timeout.
    stderr is captured but not printed — used for cost parsing.
    --quiet is intentionally omitted so core.cost_tracker [COST] lines appear in stderr.
    """
    env = {**os.environ, **model_env}
    t0 = time.monotonic()

    try:
        proc = subprocess.run(
            [adag_exe, "scan", str(main_tf), "--no-rag", "--format", "json"],
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, time.monotonic() - t0, "TIMEOUT", ""
    except FileNotFoundError:
        return None, time.monotonic() - t0, f"executable not found: {adag_exe}", ""

    elapsed = time.monotonic() - t0
    raw = proc.stdout.strip()
    stderr = proc.stderr

    if not raw:
        stderr_snippet = stderr[:300].strip()
        return None, elapsed, f"empty output (stderr: {stderr_snippet})", stderr

    try:
        parsed = json.loads(raw)
        # adag may return a list (one entry per file) or a single dict
        if isinstance(parsed, list):
            parsed = parsed[0]
        return parsed, elapsed, raw, stderr
    except json.JSONDecodeError as exc:
        return None, elapsed, f"JSON parse error: {exc} — raw: {raw[:200]}", stderr


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

def evaluate(expected: dict, actual: dict | None) -> dict:
    """
    Compare expected outcome with actual adag scan output.

    Classification logic:
        expected_outcome == "fail":
            TP if expected policy_ref(s) appear in actual violations
            FN if any expected policy_ref is absent from actual violations
        expected_outcome == "pass":
            TN if actual has no violations
            FP if actual has any violations
    """
    if actual is None:
        return {
            "scan_error": True,
            "classification": None,
            "correct": False,
            "policy_hits": [],
            "policy_misses": [],
            "false_positives": [],
            "actual_policy_refs": [],
            "actual_violation_count": 0,
        }

    actual_violations: list[dict] = actual.get("violations", [])
    actual_policy_refs: set[str] = {v.get("policy_ref", "") for v in actual_violations}
    actual_status: str = actual.get("status", "")

    result: dict[str, Any] = {
        "scan_error": False,
        "actual_status": actual_status,
        "actual_violation_count": len(actual_violations),
        "actual_policy_refs": sorted(actual_policy_refs),
        "policy_hits": [],
        "policy_misses": [],
        "false_positives": [],
    }

    expected_outcome = expected["expected_outcome"]
    expected_violations = expected.get("expected_violations", [])

    if expected_outcome == "fail":
        for ev in expected_violations:
            pr = ev["policy_ref"]
            if pr in actual_policy_refs:
                result["policy_hits"].append(pr)
            else:
                result["policy_misses"].append(pr)

        # TP requires ALL expected violations to be caught
        if result["policy_hits"] and not result["policy_misses"]:
            result["classification"] = "TP"
            result["correct"] = True
        else:
            result["classification"] = "FN"
            result["correct"] = False

    elif expected_outcome == "pass":
        if actual_violations:
            result["classification"] = "FP"
            result["correct"] = False
            result["false_positives"] = sorted(actual_policy_refs)
        else:
            result["classification"] = "TN"
            result["correct"] = True

    return result


# ---------------------------------------------------------------------------
# Cost parsing — reads core.cost_tracker log lines from stderr
# ---------------------------------------------------------------------------

import re

# Matches lines like:
# INFO     core.cost_tracker: [COST] provider=openai model=gpt-4.1 agent=auditor
#   input_tokens=4117 output_tokens=6 total_tokens=4123 estimated_cost_usd=$0.008282 ...
_COST_LINE_RE = re.compile(
    r"\[COST\](?!\s+COMPARISON).*?"
    r"model=(\S+).*?"
    r"agent=(\S+).*?"
    r"input_tokens=(\d+).*?"
    r"output_tokens=(\d+).*?"
    r"estimated_cost_usd=\$([0-9.]+)",
    re.DOTALL,
)


def parse_cost_from_stderr(stderr: str) -> dict:
    """
    Extract and sum all [COST] entries from adag stderr log output.

    core.cost_tracker emits one [COST] line per agent call (e.g. intake, auditor).
    We sum them to get the total cost and token counts for the full scan.
    [COST COMPARISON] lines are ignored — they list hypothetical costs for other models.
    """
    total_input = 0
    total_output = 0
    total_cost = 0.0
    matches = 0
    auditor_models: list[str] = []

    for line in stderr.splitlines():
        if "[COST]" not in line or "[COST COMPARISON]" in line:
            continue
        m = _COST_LINE_RE.search(line)
        if m:
            model_used = m.group(1)
            agent_name = m.group(2)
            total_input  += int(m.group(3))
            total_output += int(m.group(4))
            total_cost   += float(m.group(5))
            matches += 1
            if agent_name == "auditor":
                auditor_models.append(model_used)

    if matches == 0:
        return {"input_tokens": None, "output_tokens": None, "estimated_usd": None,
                "auditor_model_used": None,
                "auditor_model_used": None,
                "note": "no [COST] lines found in stderr"}

    auditor_model_used = auditor_models[0] if auditor_models else None
    return {
        "input_tokens":  total_input,
        "output_tokens": total_output,
        "estimated_usd": round(total_cost, 6),
        "agent_calls":   matches,
        "auditor_model_used": auditor_model_used,
    }


def estimate_cost(stderr: str) -> dict:
    """Public wrapper used by the main loop."""
    return parse_cost_from_stderr(stderr)


# ---------------------------------------------------------------------------
# Metrics aggregation
# ---------------------------------------------------------------------------

def compute_model_metrics(evaluations: list[dict]) -> dict:
    tp = sum(1 for e in evaluations if e["result"]["classification"] == "TP")
    fp = sum(1 for e in evaluations if e["result"]["classification"] == "FP")
    fn = sum(1 for e in evaluations if e["result"]["classification"] == "FN")
    tn = sum(1 for e in evaluations if e["result"]["classification"] == "TN")
    errors = sum(1 for e in evaluations if e["result"].get("scan_error"))

    recall    = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    f1        = (2 * precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0
    accuracy  = (tp + tn) / (tp + fp + fn + tn) if (tp + fp + fn + tn) > 0 else 0.0

    latencies = [e["elapsed_s"] for e in evaluations]
    avg_latency = sum(latencies) / len(latencies) if latencies else 0.0

    # Cost — only meaningful when token_usage is present
    costs = [e["cost"]["estimated_usd"] for e in evaluations
             if e["cost"].get("estimated_usd") is not None]
    total_cost = round(sum(costs), 4) if costs else None

    return {
        "tp": tp, "fp": fp, "fn": fn, "tn": tn, "errors": errors,
        "recall":    round(recall, 4),
        "precision": round(precision, 4),
        "f1":        round(f1, 4),
        "accuracy":  round(accuracy, 4),
        "avg_latency_s": round(avg_latency, 2),
        "total_cost_usd": total_cost,
    }


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

_CLASS_ICON = {"TP": "✅ TP", "TN": "✅ TN", "FP": "⚠️ FP", "FN": "❌ FN"}


def render_markdown(all_results: list[dict], timestamp: str) -> str:
    lines: list[str] = []
    lines.append("# ADAG Model Benchmark Results")
    lines.append(f"\n_Generated: {timestamp}Z_\n")

    # ── Summary table ────────────────────────────────────────────────────────
    lines.append("## Summary\n")
    header = ("| Model | Tier | In $/1M | Out $/1M | Included | Recall | Precision | F1 | Accuracy "
              "| TP | FP | FN | TN | Errors | Avg Latency | Total Cost |")
    sep    = ("|-------|------|---------|----------|----------|"
              "--------|-----------|----|---------|"
              "----|----|----|----|----|-------------|------------|")
    lines.append(header)
    lines.append(sep)

    for r in all_results:
        m = r["metrics"]
        p = r.get("pricing", {})
        tier = p.get("tier") or "—"
        inc  = "✅" if p.get("included") else ""
        inp  = f"${p['input_usd_per_1m']:.2f}" if p.get("input_usd_per_1m") is not None else "—"
        out  = f"${p['output_usd_per_1m']:.2f}" if p.get("output_usd_per_1m") is not None else "—"
        cost_str = f"${m['total_cost_usd']:.4f}" if m["total_cost_usd"] is not None else "N/A"
        lines.append(
            f"| {r['model_display_name']} "
            f"| {tier} "
            f"| {inp} "
            f"| {out} "
            f"| {inc} "
            f"| {m['recall']:.0%} "
            f"| {m['precision']:.0%} "
            f"| {m['f1']:.0%} "
            f"| {m['accuracy']:.0%} "
            f"| {m['tp']} | {m['fp']} | {m['fn']} | {m['tn']} | {m['errors']} "
            f"| {m['avg_latency_s']}s "
            f"| {cost_str} |"
        )

    lines.append("\n> Pricing from [GitHub Copilot models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing) (effective June 1, 2026). Per 1M tokens, 1 AI credit = $0.01 USD.")
    lines.append("> **Included** ✅ = within plan allowance. **Total Cost** parsed from `core.cost_tracker` [COST] lines in adag stderr.\n")

    # ── Per-test-case breakdown ───────────────────────────────────────────────
    lines.append("## Per-Test-Case Breakdown\n")
    model_names = [r["model_display_name"] for r in all_results]
    header = "| Test Case | Expected | " + " | ".join(model_names) + " |"
    sep    = "|-----------|----------| " + " | ".join("---" for _ in all_results) + " |"
    lines.append(header)
    lines.append(sep)

    tc_names = [e["test_case"] for e in all_results[0]["evaluations"]] if all_results else []
    for tc_name in tc_names:
        first_ev = next((e for e in all_results[0]["evaluations"] if e["test_case"] == tc_name), None)
        expected_label = (first_ev["expected_outcome"].upper() if first_ev else "?")

        cells = [f"| `{tc_name}`", expected_label]
        for r in all_results:
            ev = next((e for e in r["evaluations"] if e["test_case"] == tc_name), None)
            if ev is None:
                cells.append("N/A")
            elif ev["result"].get("scan_error"):
                cells.append("🔴 ERROR")
            else:
                cls = ev["result"].get("classification", "?")
                cells.append(_CLASS_ICON.get(cls, cls))

        lines.append(" | ".join(cells) + " |")

    # ── Recall highlight ─────────────────────────────────────────────────────
    lines.append("\n## Recall Ranking\n")
    lines.append("Recall = TP / (TP + FN). "
                 "For compliance tooling, target ≥ 95%. "
                 "A model with 60% recall misses 40% of real violations.\n")

    ranked = sorted(all_results, key=lambda r: r["metrics"]["recall"], reverse=True)
    lines.append("| Rank | Model | Tier | In $/1M | Out $/1M | Recall | Status |")
    lines.append("|------|-------|------|---------|----------|--------|--------|")
    for i, r in enumerate(ranked, 1):
        recall = r["metrics"]["recall"]
        p = r.get("pricing", {})
        tier = p.get("tier") or "—"
        inc  = " ✅" if p.get("included") else ""
        inp  = f"${p['input_usd_per_1m']:.2f}" if p.get("input_usd_per_1m") is not None else "—"
        out  = f"${p['output_usd_per_1m']:.2f}" if p.get("output_usd_per_1m") is not None else "—"
        status = "✅ Acceptable" if recall >= 0.95 else "❌ Below threshold"
        lines.append(f"| {i} | {r['model_display_name']}{inc} | {tier} | {inp} | {out} | {recall:.0%} | {status} |")

    return "\n".join(lines)


def print_summary_table(all_results: list[dict]) -> None:
    col_w = max(len(r["model_display_name"]) for r in all_results) + 2
    header = f"{'Model':<{col_w}} {'Recall':>8} {'Precision':>10} {'F1':>6} {'TP':>4} {'FP':>4} {'FN':>4} {'TN':>4} {'Latency':>10}"
    print("\n" + header)
    print("─" * len(header))
    for r in all_results:
        m = r["metrics"]
        print(
            f"{r['model_display_name']:<{col_w}}"
            f" {m['recall']:>7.0%}"
            f" {m['precision']:>9.0%}"
            f" {m['f1']:>6.0%}"
            f" {m['tp']:>4}"
            f" {m['fp']:>4}"
            f" {m['fn']:>4}"
            f" {m['tn']:>4}"
            f" {m['avg_latency_s']:>9.1f}s"
        )
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser(
        description="Run adag against a golden dataset with multiple models.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--models",     default="benchmark/models.yaml",
                        help="Path to models config YAML (default: benchmark/models.yaml)")
    parser.add_argument("--test-cases", default="test_cases",
                        help="Path to test_cases directory (default: test_cases/)")
    parser.add_argument("--output",     default="benchmark/results",
                        help="Directory for result files (default: benchmark/results/)")
    parser.add_argument("--adag",       default="adag",
                        help="adag executable (default: 'adag' on PATH)")
    parser.add_argument("--timeout",    type=int, default=120,
                        help="Per-scan timeout in seconds (default: 120)")
    parser.add_argument("--dry-run",    action="store_true",
                        help="Print plan without making any API calls")
    parser.add_argument("--recall-threshold", type=float, default=0.95,
                        help="Minimum acceptable recall (default: 0.95). "
                             "Exit 1 if any model is below this.")
    args = parser.parse_args()

    models_path    = repo_root / args.models
    test_cases_dir = repo_root / args.test_cases
    output_dir     = repo_root / args.output

    if not models_path.exists():
        print(f"[ERROR] Models file not found: {models_path}", file=sys.stderr)
        sys.exit(1)
    if not test_cases_dir.exists():
        print(f"[ERROR] Test cases directory not found: {test_cases_dir}", file=sys.stderr)
        sys.exit(1)

    models     = load_models(models_path)
    test_cases = load_test_cases(test_cases_dir)

    print(f"[INFO] Models: {len(models)}  |  Test cases: {len(test_cases)}")
    print(f"[INFO] Total evaluations: {len(models) * len(test_cases)}")

    if args.dry_run:
        print("\n[DRY RUN] Planned evaluations:")
        for m in models:
            for tc in test_cases:
                exp = tc["expected"]["expected_outcome"].upper()
                print(f"  {m['name']:<30}  ×  {tc['name']:<35}  (expect: {exp})")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    all_results: list[dict] = []

    for model in models:
        display_name = model.get("display_name", model["name"])
        model_env = {k: str(v) for k, v in model.get("env", {}).items()}
        expected_auditor = model_env.get("AUDITOR_MODEL", model_env.get("GITHUB_COPILOT_MODEL", "?"))
        print(f"\n[INFO] ═══ {display_name} ═══  (AUDITOR_MODEL={expected_auditor!r})")

        identity_warned = False
        evaluations: list[dict] = []

        for tc in test_cases:
            print(f"[INFO]   {tc['name']:<40}", end=" ", flush=True)

            actual, elapsed, raw, stderr = run_adag_scan(
                tc["main_tf"], model_env, args.adag, args.timeout
            )
            result = evaluate(tc["expected"], actual)
            cost   = estimate_cost(stderr)

            cls = result.get("classification") or "ERROR"
            icon = _CLASS_ICON.get(cls, cls)
            print(f"{icon}  ({elapsed:.1f}s)")

            # Model identity check — warn once per model if the auditor used
            # doesn't match what was configured (e.g. .env override in effect)
            auditor_used = cost.get("auditor_model_used")
            if auditor_used and not identity_warned and auditor_used != expected_auditor:
                print(f"[WARN]  ⚠️  model mismatch: configured={expected_auditor!r} "
                      f"but auditor ran as {auditor_used!r} — check .env overrides")
                identity_warned = True

            if result.get("policy_misses"):
                print(f"[WARN]     missed: {result['policy_misses']}")
                if result.get("actual_policy_refs"):
                    print(f"[WARN]     actual: {result['actual_policy_refs']}")
                else:
                    print(f"[WARN]     actual: (no violations returned)")
            if result.get("false_positives"):
                print(f"[WARN]     spurious: {result['false_positives']}")
            if result.get("scan_error"):
                print(f"[ERROR]    scan failed: {raw[:120]}")

            evaluations.append({
                "test_case":        tc["name"],
                "expected_outcome": tc["expected"]["expected_outcome"],
                "expected_violations": tc["expected"].get("expected_violations", []),
                "result":           result,
                "elapsed_s":        round(elapsed, 2),
                "cost":             cost,
            })

        metrics = compute_model_metrics(evaluations)
        print(
            f"[INFO]   Recall {metrics['recall']:.0%}  "
            f"Precision {metrics['precision']:.0%}  "
            f"F1 {metrics['f1']:.0%}  "
            f"TP={metrics['tp']} FP={metrics['fp']} FN={metrics['fn']} TN={metrics['tn']}"
        )

        all_results.append({
            "model_id":           model["name"],
            "model_display_name": display_name,
            "pricing":            model.get("pricing", {}),
            "metrics":            metrics,
            "evaluations":        evaluations,
        })

    # ── Save results ─────────────────────────────────────────────────────────
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    json_path = output_dir / f"benchmark_{timestamp}.json"
    md_path   = output_dir / f"benchmark_{timestamp}.md"

    payload = {"timestamp": timestamp, "results": all_results}
    with open(json_path, "w") as f:
        json.dump(payload, f, indent=2)

    md_content = render_markdown(all_results, timestamp)
    with open(md_path, "w") as f:
        f.write(md_content)

    print_summary_table(all_results)
    print(f"[INFO] Results → {json_path}")
    print(f"[INFO] Report  → {md_path}")

    # ── Threshold check ───────────────────────────────────────────────────────
    failing = [r for r in all_results if r["metrics"]["recall"] < args.recall_threshold]
    if failing:
        names = ", ".join(r["model_display_name"] for r in failing)
        print(f"\n[WARN] Below {args.recall_threshold:.0%} recall threshold: {names}")
        sys.exit(1)


if __name__ == "__main__":
    main()
