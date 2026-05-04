#!/usr/bin/env bash
# =============================================================================
# run_tests.sh — Run all three ADAG modes against the test scenarios
#
# Prerequisites:
#   1. bash setup.sh               # creates ./venv and installs adag
#   2. Edit .env (created by setup.sh) and fill in your credentials
#   3. Copy your policy files into ./policies/
#   4. For RAG tests: start RAG services first, then: export USE_RAG=true
#
# Usage:
#   bash run_tests.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Verify the venv exists ────────────────────────────────────────────────────
if [ ! -f "$REPO_DIR/venv/bin/activate" ]; then
  echo "[ERROR] No virtual environment found. Run: bash setup.sh" >&2
  exit 1
fi

# ── Activate the venv so adag and python are on PATH ─────────────────────────
# shellcheck disable=SC1091
source "$REPO_DIR/venv/bin/activate"

# ── Load .env if present (env vars already set take precedence) ──────────────
if [ -f "$REPO_DIR/.env" ]; then
  while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    # Only set if not already exported in the environment
    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$REPO_DIR/.env"
fi

# ── Always force POLICIES_DIR to the absolute path in this repo ──────────────
# Overrides any relative path set in .env (relative paths break when adag
# resolves them from a different working directory).
export POLICIES_DIR="$REPO_DIR/policies"

# ── Convenience variables for fixture paths ───────────────────────────────────
TF_DIR="$REPO_DIR/infrastructure"
MCP_PY="$REPO_DIR/venv/bin/python"

PASS=0
FAIL=0

log()  { echo "[INFO]  $*"; }
ok()   { echo "[PASS]  $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }

# ─────────────────────────────────────────────────────────────────────────────
# MODE 1: Python package — adag CLI
# ─────────────────────────────────────────────────────────────────────────────
log "═══ MODE 1: CLI (pip-installed package) ═══"

log "Test 1.1 — simple_pass.tf should exit 0 (minimal single-resource baseline)"
adag scan "$TF_DIR/simple_pass.tf" --no-rag --quiet; _ec=$?
if [ $_ec -eq 0 ]; then
  ok "simple_pass.tf → clean"
elif [ $_ec -eq 2 ]; then
  fail "simple_pass.tf → scan error (API/LLM failure, not a violation)"
else
  fail "simple_pass.tf → unexpected violations (exit $_ec)"
fi

log "Test 1.1b — all_pass.tf should exit 0 (multi-resource full coverage)"
adag scan "$TF_DIR/all_pass.tf" --no-rag --quiet; _ec=$?
if [ $_ec -eq 0 ]; then
  ok "all_pass.tf → clean"
elif [ $_ec -eq 2 ]; then
  fail "all_pass.tf → scan error (API/LLM failure, not a violation)"
else
  fail "all_pass.tf → unexpected violations (exit $_ec)"
fi

log "Test 1.2 — all_fail.tf should exit 1"
if ! adag scan "$TF_DIR/all_fail.tf" --no-rag --quiet; then
  ok "all_fail.tf → violations detected (expected)"
else
  fail "all_fail.tf → no violations found (expected failures missed)"
fi

log "Test 1.3 — mixed.tf should exit 1 (partial violations)"
if ! adag scan "$TF_DIR/mixed.tf" --no-rag --quiet; then
  ok "mixed.tf → violations on bad resources (expected)"
else
  fail "mixed.tf → no violations found (expected partial failures missed)"
fi

log "Test 1.4 — JSON output format"
adag scan "$TF_DIR/all_fail.tf" --no-rag --format json > /tmp/adag_output.json || true
if "$MCP_PY" -c "import json,sys; d=json.load(open('/tmp/adag_output.json')); d=d[0] if isinstance(d,list) else d; assert d.get('total_violations',d.get('violation_counts',{}).get('total',0)) > 0"; then
  ok "JSON output valid and contains violations"
else
  fail "JSON output missing or has no violations"
fi

log "Test 1.5 — per-policy isolation: no_delete_protection.tf"
if ! adag scan "$TF_DIR/per_policy/no_delete_protection.tf" --no-rag --quiet; then
  ok "no_delete_protection.tf → flagged (expected)"
else
  fail "no_delete_protection.tf → not flagged"
fi

log "Test 1.6 — per-policy isolation: no_encryption.tf"
if ! adag scan "$TF_DIR/per_policy/no_encryption.tf" --no-rag --quiet; then
  ok "no_encryption.tf → flagged (expected)"
else
  fail "no_encryption.tf → not flagged"
fi

log "Test 1.7 — scan entire per_policy directory"
if ! adag scan "$TF_DIR/per_policy/" --no-rag --quiet; then
  ok "per_policy/ dir scan → violations found (expected)"
else
  fail "per_policy/ dir scan → no violations found"
fi

log "Test 1.8 — edge_cases.tf (absent attr, false attr, replica)"
adag scan "$TF_DIR/edge_cases.tf" --no-rag --format json > /tmp/adag_edge.json || true
EDGE_VIOLATIONS=$("$MCP_PY" -c "import json; d=json.load(open('/tmp/adag_edge.json')); d=d[0] if isinstance(d,list) else d; print(d.get('violation_counts',{}).get('total', d.get('total_violations',0)))")
log "Edge case violations detected: $EDGE_VIOLATIONS"
if [ "$EDGE_VIOLATIONS" -gt 0 ]; then
  ok "edge_cases.tf → at least some violations caught"
else
  fail "edge_cases.tf → zero violations (missing attribute cases not caught)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# MODE 2: MCP server — smoke test (starts server and calls list_policies)
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "═══ MODE 2: MCP server ═══"
log "Test 2.1 — MCP server starts and responds to list_policies"

# Start MCP server in background, send a JSON-RPC initialize + tools/call
MCP_INPUT=$(cat <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_policies","arguments":{}}}
EOF
)

MCP_OUTPUT=$(echo "$MCP_INPUT" | timeout 60 "$MCP_PY" -m adag.mcp_server 2>/dev/null || true)
if echo "$MCP_OUTPUT" | grep -q "delete_protection"; then
  ok "MCP list_policies → returned policy list including delete_protection"
else
  fail "MCP list_policies → unexpected output or server failed to start"
  echo "  Raw output: $MCP_OUTPUT" | head -5
fi

log "Test 2.2 — MCP check_terraform_file tool"
MCP_SCAN=$(cat <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"check_terraform_file","arguments":{"path":"$TF_DIR/per_policy/no_delete_protection.tf"}}}
EOF
)
MCP_SCAN_OUT=$(echo "$MCP_SCAN" | USE_RAG=false timeout 180 "$MCP_PY" -m adag.mcp_server 2>/dev/null || true)
if echo "$MCP_SCAN_OUT" | grep -q "violations"; then
  ok "MCP check_terraform_file → returned violations"
else
  fail "MCP check_terraform_file → no violations in response"
fi

# ─────────────────────────────────────────────────────────────────────────────
# MODE 3: RAG — only runs if USE_RAG=true
# Assumes policies are already indexed in the RAG store.
# Tests only the RAG retrieval layer — no LLM agent invoked, no token cost.
# To start services: cd /home/mst/projects/rag && ./run_all_services.sh
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "═══ MODE 3: RAG ═══"

USE_RAG="${USE_RAG:-false}"
if [ "$USE_RAG" != "true" ]; then
  log "Skipping RAG tests (USE_RAG is not true)"
  log "To run: cd /home/mst/projects/rag && ./run_all_services.sh"
  log "        export USE_RAG=true && bash run_tests.sh"
else
  # Test 3.1 — context augmentation service responds and returns chunks
  log "Test 3.1 — query_rag: deletion protection policy retrieval"
  curl -s -X POST "http://localhost:8000/context-augment/archapp" \
    -H "Content-Type: application/json" \
    -d '{"question":"What are the deletion protection requirements?","metadata":{}}' \
    --max-time 30 > /tmp/adag_rag1.json 2>/dev/null || true
  CHUNK_COUNT=$("$MCP_PY" -c "import json; d=json.load(open('/tmp/adag_rag1.json')); print(len(d.get('relevant_chunks',[])))" 2>/dev/null || echo "0")
  if [ "$CHUNK_COUNT" -gt 0 ]; then
    ok "query_rag → returned $CHUNK_COUNT chunks (RAG pipeline working)"
  else
    fail "query_rag → no chunks returned (services running? policies indexed?)"
    log "  Raw: $(head -c 200 /tmp/adag_rag1.json)"
  fi

  # Test 3.2 — encryption policy retrieval
  log "Test 3.2 — query_rag: encryption at rest policy retrieval"
  curl -s -X POST "http://localhost:8000/context-augment/archapp" \
    -H "Content-Type: application/json" \
    -d '{"question":"What are the encryption at rest requirements for RDS?","metadata":{}}' \
    --max-time 30 > /tmp/adag_rag2.json 2>/dev/null || true
  CHUNK_COUNT2=$("$MCP_PY" -c "import json; d=json.load(open('/tmp/adag_rag2.json')); print(len(d.get('relevant_chunks',[])))" 2>/dev/null || echo "0")
  if [ "$CHUNK_COUNT2" -gt 0 ]; then
    ok "query_rag → returned $CHUNK_COUNT2 chunks for encryption query"
  else
    fail "query_rag → no chunks returned for encryption query"
    log "  Raw: $(head -c 200 /tmp/adag_rag2.json)"
  fi

  # Test 3.3 — MCP ingest_document tool (round-trip: ingest a policy, then query it back)
  log "Test 3.3 — ingest_document via MCP then verify retrieval"
  INGEST_INPUT=$(cat <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ingest_document","arguments":{"path":"$REPO_DIR/policies/delete_protection.md"}}}
EOF
)
  INGEST_OUT=$(echo "$INGEST_INPUT" | USE_RAG=true timeout 30 "$MCP_PY" -m adag.mcp_server 2>/dev/null || true)
  if echo "$INGEST_OUT" | grep -qi "ingested\|result\|chunk"; then
    ok "ingest_document → document accepted by RAG pipeline"
  else
    fail "ingest_document → ingestion failed or no confirmation"
    log "  Raw: $(echo "$INGEST_OUT" | head -c 200)"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
