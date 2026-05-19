# ADAG Model Benchmark Results

_Generated: 20260519_023207 (report updated with estimated costs)Z_

## Summary

| Model | Tier | In $/1M | Out $/1M | Included | Recall | Precision | F1 | Accuracy | TP | FP | FN | TN | Errors | Avg Latency | Total Cost |
|-------|------|---------|----------|----------|--------|-----------|----|---------|----|----|----|----|----|-------------|------------|
| GPT-4.1 (Copilot) | Versatile | $2.00 | $8.00 | ✅ | 80% | 100% | 89% | 86% | 4 | 0 | 1 | 2 | 0 | 5.36s | $0.0673 |
| GPT-4o (Copilot) | Versatile | — | — |  | 80% | 100% | 89% | 86% | 4 | 0 | 1 | 2 | 0 | 5.8s | $0.0838 |
| GPT-5 mini (Copilot) | Lightweight | $0.25 | $2.00 | ✅ | 80% | 80% | 80% | 71% | 4 | 1 | 1 | 1 | 0 | 19.0s | ~$0.0088 |
| Claude Haiku 4.5 (Copilot) | Versatile | $1.00 | $5.00 |  | 100% | 100% | 100% | 100% | 5 | 0 | 0 | 2 | 0 | 6.32s | $0.0391 |
| GPT-5.2 (Copilot) | Versatile | $1.75 | $14.00 |  | 100% | 100% | 100% | 100% | 5 | 0 | 0 | 2 | 0 | 7.06s | ~$0.0619 |
| GPT-5.2-Codex (Copilot) | Powerful | $1.75 | $14.00 |  | 100% | 100% | 100% | 100% | 5 | 0 | 0 | 2 | 0 | 8.21s | ~$0.0619 |
| GPT-5.3-Codex (Copilot) | Powerful | $1.75 | $14.00 |  | 80% | 100% | 89% | 86% | 4 | 0 | 1 | 2 | 0 | 6.57s | ~$0.0619 |
| GPT-5.4 (Copilot) | Versatile | $2.50 | $15.00 |  | 80% | 100% | 89% | 86% | 4 | 0 | 1 | 2 | 0 | 6.89s | ~$0.0862 |
| Claude Sonnet 4.5 (Copilot) | Versatile | $3.00 | $15.00 |  | 100% | 100% | 100% | 100% | 5 | 0 | 0 | 2 | 0 | 8.11s | $0.1442 |
| Claude Sonnet 4.6 (Copilot) | Versatile | $3.00 | $15.00 |  | 80% | 100% | 89% | 86% | 4 | 0 | 1 | 2 | 0 | 8.77s | ~$0.1455 |
| Gemini 2.5 Pro (Copilot) | Powerful | $1.25 | $10.00 |  | 100% | 100% | 100% | 100% | 5 | 0 | 0 | 2 | 0 | 15.23s | ~$0.0442 |

> Pricing from [GitHub Copilot models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing) (effective June 1, 2026). Per 1M tokens, 1 AI credit = $0.01 USD.
> **Included** ✅ = within plan allowance. **Total Cost** parsed from `core.cost_tracker` [COST] lines in adag stderr.

## Per-Test-Case Breakdown

| Test Case | Expected | GPT-4.1 (Copilot) | GPT-4o (Copilot) | GPT-5 mini (Copilot) | Claude Haiku 4.5 (Copilot) | GPT-5.2 (Copilot) | GPT-5.2-Codex (Copilot) | GPT-5.3-Codex (Copilot) | GPT-5.4 (Copilot) | Claude Sonnet 4.5 (Copilot) | Claude Sonnet 4.6 (Copilot) | Gemini 2.5 Pro (Copilot) |
|-----------|----------| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `iam_wildcard_resource` | FAIL | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP |
| `rds_compliant` | PASS | ✅ TN | ✅ TN | ⚠️ FP | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN |
| `rds_no_deletion_protection` | FAIL | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP |
| `rds_public_access` | FAIL | ✅ TP | ✅ TP | ❌ FN | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP |
| `s3_compliant` | PASS | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN | ✅ TN |
| `s3_no_encryption` | FAIL | ❌ FN | ❌ FN | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ❌ FN | ✅ TP | ✅ TP | ❌ FN | ✅ TP |
| `sg_ssh_open_world` | FAIL | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ✅ TP | ❌ FN | ✅ TP | ✅ TP | ✅ TP |

## Recall Ranking

Recall = TP / (TP + FN). For compliance tooling, target ≥ 95%. A model with 60% recall misses 40% of real violations.

| Rank | Model | Tier | In $/1M | Out $/1M | Recall | Status |
|------|-------|------|---------|----------|--------|--------|
| 1 | Claude Haiku 4.5 (Copilot) | Versatile | $1.00 | $5.00 | 100% | ✅ Acceptable |
| 2 | GPT-5.2 (Copilot) | Versatile | $1.75 | $14.00 | 100% | ✅ Acceptable |
| 3 | GPT-5.2-Codex (Copilot) | Powerful | $1.75 | $14.00 | 100% | ✅ Acceptable |
| 4 | Claude Sonnet 4.5 (Copilot) | Versatile | $3.00 | $15.00 | 100% | ✅ Acceptable |
| 5 | Gemini 2.5 Pro (Copilot) | Powerful | $1.25 | $10.00 | 100% | ✅ Acceptable |
| 6 | GPT-4.1 (Copilot) ✅ | Versatile | $2.00 | $8.00 | 80% | ❌ Below threshold |
| 7 | GPT-4o (Copilot) | Versatile | — | — | 80% | ❌ Below threshold |
| 8 | GPT-5 mini (Copilot) ✅ | Lightweight | $0.25 | $2.00 | 80% | ❌ Below threshold |
| 9 | GPT-5.3-Codex (Copilot) | Powerful | $1.75 | $14.00 | 80% | ❌ Below threshold |
| 10 | GPT-5.4 (Copilot) | Versatile | $2.50 | $15.00 | 80% | ❌ Below threshold |
| 11 | Claude Sonnet 4.6 (Copilot) | Versatile | $3.00 | $15.00 | 80% | ❌ Below threshold |