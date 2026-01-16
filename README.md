# Codex Swarm

Parallel Codex agent orchestrator for Claude Code. Claude plans, Codex executes, Git enforces truth.

## What It Does

- Claude Code decomposes large tasks into bounded pieces
- Multiple Codex agents work in parallel
- Results merged and presented for review

## Prerequisites

- **Claude Code** installed
- **Codex CLI:** `npm i -g @openai/codex`
- **Codex authenticated:** Run `codex` and sign in with ChatGPT
- **Git** (required for write mode)
- **bash 4.0+** (macOS: `brew install bash`)
- **jq** (optional but recommended): `brew install jq`

## Installation

**Option A: Clone into your project**
```bash
git clone https://github.com/iamseancorcoran/CODEX_SWARM.git .codex-swarm
rm -rf .codex-swarm/.git
```

**Option B: Download and copy**
1. Download this repo
2. Copy contents into your project as `.codex-swarm/`

**Then activate:**
1. Open Claude Code in your project
2. Say: "Read .codex-swarm/SETUP.md and follow the instructions"
3. Done — swarm commands available

## Commands

| Command | Description |
|---------|-------------|
| `Enable swarm` | Enable swarm mode |
| `Disable swarm` | Disable swarm mode |
| `Swarm status` | Show current state and config |
| `Swarm config` | Interactive configuration |
| `Swarm kill all` | Emergency kill all agents |

### Quick Config

Change individual settings without the full menu:

| Command | Description |
|---------|-------------|
| `swarm model <model>` | gpt-5-codex, gpt-5.2-codex, gpt-5.1-codex-mini |
| `swarm reasoning <level>` | low, medium, high, extra-high (controls task shape) |
| `swarm read` | Set sandbox to read-only |
| `swarm write` | Set sandbox to workspace-write |
| `swarm timeout <minutes>` | 1-30 |
| `swarm logging on\|off` | Toggle logging |
| `swarm integrator <mode>` | automatic, manual, ask |

## Quick Example

```
Enable swarm
Audit this codebase for security issues across auth, billing, and API modules
```

Claude Code splits the work, runs parallel Codex agents, and presents consolidated results.

## Configuration

Say `Swarm config` to set:

- Model (gpt-5-codex, gpt-5.2-codex, gpt-5.1-codex-mini)
- Reasoning level (low, medium, high, extra-high)
- Sandbox mode (read-only, workspace-write)
- Max agents (default or manual limit)
- Timeout per agent
- Logging on/off
- Docker safety mode
- Integrator mode (automatic, manual, ask)

## Reasoning Tiers

Reasoning controls how Claude shapes tasks for Codex:

| Tier | Agents | Files/Task | Context | Planning |
|------|--------|------------|---------|----------|
| low | 4 | ≤3 | ≤4 | none |
| medium | 3 | ≤8 | ≤8 | 5-8 steps |
| high | 2 | ≤15 | ≤12 | 8-12 steps |
| extra-high | 1 | ≤25 | ≤20 | 10-15 steps |

**Use for:**
- **low:** formatting, trivial refactors, test scaffolding, docs
- **medium:** normal feature work, typical bug fixes, contained refactors
- **high:** auth/security, concurrency, tricky logic, non-obvious bugs
- **extra-high:** architecture changes, migrations, core invariants

## Write Mode

When using `workspace-write`:

1. Each agent works in an isolated git worktree
2. No file conflicts during execution
3. Integrator merges branches after completion

## Safeguards

**Hard blocked:**
- Protected paths: .env, *.pem, *.key, secrets, credentials
- Dangerous commands: rm -rf, sudo, docker prune/rm

**Write mode protections:**
- Requires explicit confirmation
- Git worktree isolation
- Integrator verification pass

## Validation

After installation, verify:
```bash
.codex-swarm/validate.sh
```

## License

MIT
