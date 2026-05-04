# adag-test-infra

Test scenarios for the **adag** (AI-Driven Architecture Guardrail) tool.

This repo is self-contained: it creates its own Python environment and installs
`adag` from the `arch_agent` Git repository. No manual venv activation from
another repo is required.

---

## Quick start

```bash
# 1. Clone this repo
git clone https://github.com/your-org/adag-test-infra.git
cd adag-test-infra

# 2. Bootstrap: creates ./venv and installs adag
bash setup.sh

# 3. Edit credentials
#    .env was created automatically; fill in your LLM/AWS values
nano .env

# 4. Add your policy files
#    Copy the .md policy files into ./policies/
cp /path/to/arch_agent/policies/*.md ./policies/

# 5. Activate and run
source venv/bin/activate
bash run_tests.sh
```

---

## Repo layout

```
adag-test-infra/
├── setup.sh              # Bootstrap: creates venv, installs adag
├── run_tests.sh          # Test runner for all three modes
├── requirements.txt      # adag git dependency (used by setup.sh)
├── .env.example          # Credential/config template (copied to .env by setup.sh)
├── mcp_config.json       # Claude Desktop MCP server config snippet
├── policies/             # Your policy .md files go here
├── all_pass.tf           # All resources compliant
├── all_fail.tf           # All resources violating all policies
├── mixed.tf              # Mix of compliant and non-compliant
├── edge_cases.tf         # Tricky/edge-case scenarios
└── per_policy/           # One .tf file per policy, isolates single violations
```

---

## Prerequisites

- Python 3.10+
- Git (to install `adag` from its repository)
- AWS credentials configured (profile or env vars) — required for Bedrock mode
- `adag` source repo accessible at the URL set in `setup.sh`

---

## Configuration (`.env`)

### Core LLM Configuration

| Variable | Description |
|---|---|
| `LLM_PROVIDER` | Provider to use: `bedrock`, `github-copilot`, `openai`, `huggingface`, or `ollama` |
| `BEDROCK_MODEL` | Model for Bedrock (e.g., `claude-3-haiku-20250514`; replaces deprecated `ANTHROPIC_MODEL`) |
| `GITHUB_COPILOT_TOKEN` | GitHub Copilot API token (required when `LLM_PROVIDER=github-copilot`) |
| `GITHUB_COPILOT_MODEL` | Model for GitHub Copilot (e.g., `claude-opus-4.1`) |
| `OPENAI_API_KEY` | OpenAI API key (required when `LLM_PROVIDER=openai`) |
| `OPENAI_MODEL` | Model for OpenAI (e.g., `gpt-4o`) |
| `HF_TOKEN` | HuggingFace token (required when `LLM_PROVIDER=huggingface`) |
| `HF_MODEL` | Model for HuggingFace (e.g., `Qwen/Qwen2.5-72B-Instruct`) |
| `OLLAMA_BASE_URL` | Ollama server URL (default: `http://localhost:11434`) |
| `OLLAMA_MODEL` | Model for Ollama (e.g., `llama2`) |

### Per-Agent Model Selection (Optional)

All LLM providers now support per-agent overrides:

| Variable | Description |
|---|---|
| `INTAKE_MODEL` | Override model for Intake agent (resource discovery); uses provider default if not set |
| `AUDITOR_MODEL` | Override model for Auditor agent (policy evaluation); uses provider default if not set |

**Example**: Use a faster model for Intake, a more capable one for Auditor:
```bash
LLM_PROVIDER=bedrock
BEDROCK_MODEL=claude-3-haiku-20250514  # Default
INTAKE_MODEL=claude-3-haiku-20250514   # Fast resource discovery
AUDITOR_MODEL=claude-3-sonnet-20250219 # Powerful policy analysis
```

### Other Configuration

| Variable | Description |
|---|---|
| `POLICIES_DIR` | Path to policy `.md` files (defaults to `./policies`); read by Intake agent for dynamic resource discovery |
| `USE_RAG` | Set `true` to enable Mode 3 (RAG services must be running) |
| `ADAG_APPID` | App namespace in the RAG store |

---

## Dynamic Resource Discovery

The **Intake agent** automatically discovers auditable resource types from policies in `POLICIES_DIR`. You don't need to edit code to add custom resources — just create new policy files and the Intake agent will find them at startup.

Each policy should have a `## Scope` section listing the resource types it applies to:

```markdown
## Scope

- `aws_db_instance`
- `aws_rds_cluster`
- `aws_elasticache_cluster`
```

The Intake agent will:
1. Load all `.md` policies from `POLICIES_DIR`
2. Extract resource types from each policy's `Scope` section  
3. Use the combined list when scanning Terraform files

**Adding custom resources**: Simply add a new policy markdown file to `./policies/` with a `Scope` section — no code changes needed.

---

## Three modes

### Mode 1 — CLI (Python package)

The `adag` CLI is installed into `./venv` by `setup.sh`.

```bash
source venv/bin/activate
adag scan all_fail.tf --no-rag
adag scan all_pass.tf --no-rag --format json
adag scan per_policy/ --no-rag --quiet
```

`run_tests.sh` exercises 8 CLI scenarios covering all test fixtures.

### Mode 2 — MCP Server

`adag` exposes an MCP server that Claude Desktop (or any MCP client) can use.

1. Run `bash setup.sh` — the venv Python is at `./venv/bin/python`.
2. Edit `mcp_config.json`: replace every `/absolute/path/to/adag-test-infra`
   with the real absolute path to this repo.
3. Merge the `mcpServers` block into `~/.config/claude/claude_desktop_config.json`.
4. Restart Claude Desktop.

`run_tests.sh` smoke-tests the MCP server by sending JSON-RPC messages directly
to `python -m adag.mcp_server` via stdin.

### Mode 3 — RAG (Advanced)

Requires the RAG microservices to be running first.

```bash
# In the RAG services repo:
./run_all_services.sh

# Then, back here:
export USE_RAG=true
bash run_tests.sh
```

RAG tests are automatically skipped when `USE_RAG` is not `true`.

---

## Pointing setup.sh at the arch_agent repo

Open `setup.sh` and set `ADAG_GIT_URL` to the real Git URL:

```bash
ADAG_GIT_URL="https://github.com/your-org/arch_agent.git"
```

Or override it without editing the file:

```bash
ADAG_GIT_URL="https://github.com/your-org/arch_agent.git" bash setup.sh
```

For local development, use a local path:

```bash
ADAG_GIT_URL="/home/you/projects/arch_agent" bash setup.sh
```
