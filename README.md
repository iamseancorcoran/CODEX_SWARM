# Codex Swarm

Parallel Codex agent orchestration for Claude Code.

## What It Does

- Claude Code decomposes large tasks into bounded pieces
- Multiple Codex agents work in parallel
- Results merged and presented for review

## Prerequisites

- **Codex CLI installed:** `npm i -g @openai/codex`
- **Authenticated:** Run `codex` and sign in with ChatGPT
- **Git repository** (required for write mode)
- **bash 4.0+** (macOS users: `brew install bash`)

## Installation (Per Project)

1. Copy `.codex-swarm/` folder into your project root:
   ```bash
   cp -r ~/Templates/codex-swarm /path/to/project/.codex-swarm
   ```

2. Open Claude Code in the project

3. Say: "Read .codex-swarm/SETUP.md and follow the instructions"

4. Done — swarm commands available

## Commands

| Command | Description |
|---------|-------------|
| `/swarm` | Enable swarm mode |
| `/swarmkill` | Disable swarm mode |
| `/swarmstatus` | Show current state and config |
| `/swarmconfig` | Interactive configuration |
| `/swarmkillall` | Emergency kill all agents |

## Config Options

| Option | Default | Description |
|--------|---------|-------------|
| model | gpt-5.2-codex | Codex model to use |
| reasoning | medium | low/medium/high/extra-high |
| sandbox | read-only | read-only/workspace-write |
| maxAgents | default | Claude picks, or set 1-10 |
| timeout | 10 | Minutes per agent |
| logging | true | Save results to logs/ |
| dockerMode | safe | safe/none/allow |
| integratorMode | manual | automatic/manual/ask |

## Usage

Enable swarm:
```
/swarm
```

Ask Claude Code:
```
"Audit this codebase for security issues across auth, billing, and API modules"
```

Claude Code will:
1. Split into parallel tasks
2. Assign non-overlapping paths
3. Run agents
4. Present consolidated results

## Direct Script Usage

```bash
# Read-only analysis
.codex-swarm/codex-swarm.sh \
  --tasks "Audit auth module" "Review API security" \
  --paths "src/auth/**" "src/api/**" \
  --dir /path/to/project

# Write mode with worktrees
.codex-swarm/codex-swarm.sh \
  --tasks "Implement feature A" "Implement feature B" \
  --paths "src/features/a/**" "src/features/b/**" \
  --sandbox workspace-write \
  --integrator automatic \
  --dir /path/to/project

# Async mode (fire-and-forget)
.codex-swarm/codex-swarm.sh \
  --tasks "Long task 1" "Long task 2" \
  --async \
  --dir /path/to/project
```

## Write Mode

When using `workspace-write`:

1. Each agent works in an isolated git worktree
2. No file conflicts during execution
3. Integrator merges branches after completion
4. Git handles conflict detection

### Integrator Modes

- **automatic:** Codex merges all branches, runs tests, fixes conflicts
- **manual:** Returns results, leaves worktrees for you to merge
- **ask:** Prompts before running integrator

## Safeguards

**Hard blocked (always):**
- Protected paths: .env, *.pem, *.key, secrets, credentials
- Dangerous commands: rm -rf, sudo, docker prune/rm

**Write mode protections:**
- Requires explicit confirmation
- Git worktree isolation
- Lock file prevents concurrent swarms
- Integrator verification pass

## Logs

Results saved to `.codex-swarm/logs/` as timestamped markdown:
```
logs/
├── 20260116-143022_swarm.md
├── 20260116-152045_swarm.md
```

## Async Jobs

When using `--async`, job metadata saved to `.codex-swarm/jobs/`:
```
jobs/
├── swarm-20260116-143022-1.json
├── swarm-20260116-143022-2.json
```

## Troubleshooting

### "codex not found"
Install Codex CLI:
```bash
npm i -g @openai/codex
```

### "codex not authenticated"
Run `codex` and sign in with ChatGPT.

### "Requires bash 4.0+"
On macOS, install newer bash:
```bash
brew install bash
```
Then run with:
```bash
/opt/homebrew/bin/bash .codex-swarm/codex-swarm.sh ...
```

### "Another swarm is running"
Remove stale lock file:
```bash
rm -rf .codex-swarm/swarm.lock
```

### "Protected path blocked"
Task references .env or secrets. Rephrase without protected paths.

### "Merge conflicts after write mode"
Run integrator manually:
```bash
codex exec "Resolve merge conflicts, keep both changes, run tests"
```

### "Agent timeout"
Increase timeout in `/swarmconfig` or simplify the task.

### "Worktree issues"
Clean up manually:
```bash
git worktree list | grep swarm | awk '{print $1}' | xargs -I{} git worktree remove {} --force
git branch -D swarm-agent-{1..10} 2>/dev/null
```

## Validation

Run the validation script after installation:
```bash
.codex-swarm/validate.sh
```

## Principle

**Claude plans. Codex executes. Git enforces truth.**
