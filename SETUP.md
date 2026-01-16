# Codex Swarm Setup

Read this file and add the following to this project's CLAUDE.md (create if it doesn't exist).

---

## Add to CLAUDE.md:

### Codex Swarm

Parallel Codex agent orchestration tool.

**Tool location:** .codex-swarm/codex-swarm.sh
**Config:** .codex-swarm/config.json

#### Commands

- `Enable swarm` — Enable swarm mode
- `Disable swarm` — Disable swarm mode
- `Swarm status` — Show current state and config
- `Swarm config` — Interactive configuration menu
- `Swarm kill all` — Emergency kill all running agents

---

#### Enable swarm
Enable swarm mode. Respond:
```
Swarm mode enabled ([model], [reasoning], [sandbox])
```

#### Disable swarm
Disable swarm mode. Respond:
```
Swarm mode disabled
```

#### Swarm status
Show:
```
Swarm Status: ON/OFF

Config:
  model: gpt-5.2-codex
  reasoning: medium
  sandbox: read-only
  max agents: default
  timeout: 10 min
  logging: yes
  docker mode: safe
  integrator: manual
```

#### Swarm config
Interactive menu. Ask each question, wait for response:

1. Select model:
   - 1. gpt-5-codex
   - 2. gpt-5.2-codex (default)
   - 3. gpt-5.1-codex-mini

2. Select reasoning level for [selected model]:
   - 1. low — Fast responses with lighter reasoning
   - 2. medium — Balances speed and reasoning depth (default)
   - 3. high — Greater reasoning depth for complex problems
   - 4. extra high — Maximum reasoning depth

3. Select sandbox mode:
   - 1. read-only (default)
   - 2. workspace-write

4. Max agents:
   - 1. default — Claude picks based on task (default)
   - 2. manual — (then ask: Enter max 1-10)

5. Timeout per agent (minutes):
   - Show current (default 10), ask for 1-30

6. Save results to log:
   - 1. yes (default)
   - 2. no

7. Docker mode:
   - 1. safe — Block destructive, warn unknown (default)
   - 2. none — Block all docker commands
   - 3. allow — Allow docker (not recommended)

8. Integrator mode:
   - 1. automatic — Run integrator after workers
   - 2. manual — Return results, you merge (default)
   - 3. ask — Ask each time

Save to .codex-swarm/config.json. Confirm: "Config saved"

#### Swarm kill all
Kill all running Codex agents immediately. For emergencies.
Run: `pkill -f "codex exec"` and clean up any worktrees with:
```bash
cd [project] && git worktree list | grep swarm | awk '{print $1}' | xargs -I{} git worktree remove {} --force
git branch -D swarm-agent-{1..10} 2>/dev/null
rm -rf .codex-swarm/swarm.lock
```

---

#### When Swarm Mode is ON

For tasks that can be parallelized:

1. **Plan the work:**
   - Decompose into independent bounded tasks
   - Assign non-overlapping allowed paths to each
   - Select up to 6 context files per task
   - Check maxAgents config — don't exceed

2. **If sandbox is workspace-write AND multiple agents:**
   - Warn: "Write mode with N agents. Agents will work in isolated git worktrees to prevent conflicts."
   - Require explicit "yes" before proceeding

3. **Run the swarm:**
```bash
.codex-swarm/codex-swarm.sh \
  --tasks "task1" "task2" "task3" \
  --paths "src/auth/**" "src/billing/**" "src/api/**" \
  --context "auth/service.ts,auth/types.ts" "billing/service.ts" "api/routes.ts" \
  --dir $(pwd) \
  --model [config] \
  --reasoning [config] \
  --sandbox [config] \
  --timeout [config] \
  --integrator [config]
```

4. **Present results to user**

5. **Handle integrator:**
   - If automatic: already merged, show summary
   - If manual: show merge instructions
   - If ask: "Run integrator to merge branches? (yes/no)"

6. **Always ask before taking further action on findings**

---

#### When NOT to Use Swarm
- Swarm mode is OFF
- Sequential tasks where order matters
- Small focused tasks
- Tasks that can't be cleanly split into non-overlapping paths

---

#### Worker Contract Template
Each agent receives:
```
WORKER CONTRACT:
- Execute ONE bounded task: {task}
- Only edit files under: {allowed_paths}
- Context files provided: {context_files}
- Do NOT touch files outside allowed paths
- Do NOT refactor unrelated code
- If more context needed, STOP and report what's missing
- Output: 1) summary 2) files changed 3) verification result
```

---

#### Safeguards (always enforced)
- Max 10 agents hard cap
- Protected paths: .env, keys, secrets, credentials — HARD BLOCK
- Blocked commands: rm -rf, sudo, docker destructive — HARD BLOCK
- Write mode requires explicit confirmation
- Write mode uses git worktrees for isolation
- Results scrubbed of secrets before logging
- Always review with user before acting on findings

---

#### Principle
Claude plans. Codex executes. Git enforces truth.

---

## After Setup

Delete this SETUP.md or keep for reference.
