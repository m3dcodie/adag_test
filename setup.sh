#!/usr/bin/env bash
# =============================================================================
# setup.sh — Bootstrap a self-contained environment for adag-test-infra
#
# What this does:
#   1. Creates a local Python virtual environment (./venv)
#   2. Installs the adag package from its Git repository
#   3. Copies .env.example → .env if .env does not already exist
#
# Usage:
#   bash setup.sh
#   source venv/bin/activate   # then run: bash run_tests.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Configurable: point this at the arch_agent Git repo ──────────────────────
# Override via env var if needed, e.g. for a local dev path:
#   ADAG_GIT_URL="/home/you/projects/arch_agent" bash setup.sh
ADAG_GIT_URL="${ADAG_GIT_URL:-https://github.com/m3dcodie/arch_agent.git}"
# ─────────────────────────────────────────────────────────────────────────────

log() { echo "[setup] $*"; }

# 1. Create venv
if [ ! -d "$REPO_DIR/venv" ]; then
  log "Creating virtual environment at ./venv ..."
  python3 -m venv "$REPO_DIR/venv"
else
  log "Virtual environment already exists at ./venv — skipping creation."
fi

VENV_PIP="$REPO_DIR/venv/bin/pip"
VENV_PYTHON="$REPO_DIR/venv/bin/python"

# 2. Upgrade pip silently
"$VENV_PIP" install --upgrade pip --quiet

# 3. Install adag from Git
log "Installing adag from: $ADAG_GIT_URL"
"$VENV_PIP" install "git+${ADAG_GIT_URL}" --quiet

# 4. Bootstrap .env
if [ ! -f "$REPO_DIR/.env" ]; then
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
  log "Created .env from .env.example — please edit it and fill in your credentials."
else
  log ".env already exists — skipping."
fi

log ""
log "Setup complete. Next steps:"
log "  1. Edit .env and fill in your LLM and AWS credentials."
log "  2. Copy your policy files into ./policies/ (see policies/.gitkeep for guidance)."
log "  3. Activate the environment and run the tests:"
log "       source venv/bin/activate"
log "       bash run_tests.sh"
