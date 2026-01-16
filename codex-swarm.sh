#!/usr/bin/env bash
#
# codex-swarm.sh - Parallel Codex agent orchestration
#
# Usage:
#   ./codex-swarm.sh --tasks "task1" "task2" --dir /path/to/project [options]
#
# Options:
#   --tasks "t1" "t2"    Task descriptions (required)
#   --paths "p1" "p2"    Allowed paths per task (matched by index)
#   --context "f1" "f2"  Context files per task (matched by index)
#   --dir /path          Project root directory (required)
#   --model <model>      Model to use (default: from config)
#   --reasoning <level>  low/medium/high/extra-high
#   --sandbox <mode>     read-only/workspace-write
#   --timeout <minutes>  Per-agent timeout
#   --integrator <mode>  automatic/manual/ask
#   --async              Fire-and-forget mode
#

set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
MAX_AGENTS_HARD_CAP=10

# Will be set based on --dir argument
PROJECT_DIR=""
SWARM_DIR=""
WORKTREE_DIR=""
JOBS_DIR=""
LOGS_DIR=""
LOCK_FILE=""

# ═══════════════════════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════════════════════

declare -a TASKS=()
declare -a PATHS=()
declare -a CONTEXTS=()
declare -a PIDS=()
declare -a AGENT_WORKTREES=()
declare -a OUTPUT_FILES=()
declare -a STATUSES=()
declare -a DURATIONS=()

# Config defaults (overridden by config.json and CLI args)
MODEL="gpt-5.2-codex"
REASONING="medium"
SANDBOX="read-only"
TIMEOUT=10
LOGGING="true"
INTEGRATOR="manual"
DOCKER_MODE="safe"
ASYNC="false"

# Cleanup state
declare -g CLEANUP_DONE=false

# ═══════════════════════════════════════════════════════════════════════════════
# BASH VERSION CHECK
# ═══════════════════════════════════════════════════════════════════════════════

check_bash_version() {
  if [[ -z "${BASH_VERSINFO:-}" ]] || [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: codex-swarm requires bash 4.0+" >&2
    echo "Current version: ${BASH_VERSION:-unknown}" >&2
    echo "" >&2
    echo "On macOS, install with: brew install bash" >&2
    echo "Then run with: /opt/homebrew/bin/bash $0" >&2
    exit 1
  fi
}

# Run immediately
check_bash_version

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG LOADING
# ═══════════════════════════════════════════════════════════════════════════════

load_config() {
  # Try to load from config.json if jq is available
  if command -v jq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    if jq empty "$CONFIG_FILE" 2>/dev/null; then
      MODEL=$(jq -r '.model // "gpt-5.2-codex"' "$CONFIG_FILE")
      REASONING=$(jq -r '.reasoning // "medium"' "$CONFIG_FILE")
      SANDBOX=$(jq -r '.sandbox // "read-only"' "$CONFIG_FILE")
      TIMEOUT=$(jq -r '.timeout // 10' "$CONFIG_FILE")
      LOGGING=$(jq -r '.logging // true' "$CONFIG_FILE")
      INTEGRATOR=$(jq -r '.integratorMode // "manual"' "$CONFIG_FILE")
      DOCKER_MODE=$(jq -r '.dockerMode // "safe"' "$CONFIG_FILE")
    else
      echo "WARNING: config.json is malformed, using defaults" >&2
    fi
  elif [[ ! -f "$CONFIG_FILE" ]]; then
    echo "INFO: No config.json found, using defaults" >&2
  elif ! command -v jq &>/dev/null; then
    echo "WARNING: jq not installed, using embedded defaults" >&2
    echo "Install jq for custom configuration support" >&2
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tasks)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          TASKS+=("$1")
          shift
        done
        ;;
      --paths)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          PATHS+=("$1")
          shift
        done
        ;;
      --context)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          CONTEXTS+=("$1")
          shift
        done
        ;;
      --dir)
        shift
        PROJECT_DIR="$1"
        shift
        ;;
      --model)
        shift
        MODEL="$1"
        shift
        ;;
      --reasoning)
        shift
        REASONING="$1"
        shift
        ;;
      --sandbox)
        shift
        SANDBOX="$1"
        shift
        ;;
      --timeout)
        shift
        TIMEOUT="$1"
        shift
        ;;
      --integrator)
        shift
        INTEGRATOR="$1"
        shift
        ;;
      --async)
        ASYNC="true"
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
    esac
  done

  # Set derived paths after PROJECT_DIR is known
  if [[ -n "$PROJECT_DIR" ]]; then
    SWARM_DIR="$PROJECT_DIR/.codex-swarm"
    WORKTREE_DIR="$SWARM_DIR/wt"
    JOBS_DIR="$SWARM_DIR/jobs"
    LOGS_DIR="$SWARM_DIR/logs"
    LOCK_FILE="$SWARM_DIR/swarm.lock"
  fi
}

show_help() {
  cat <<'EOF'
codex-swarm - Parallel Codex agent orchestration

USAGE:
  codex-swarm.sh --tasks "task1" "task2" --dir /path [options]

REQUIRED:
  --tasks "t1" "t2" ...   Task descriptions for each agent
  --dir /path             Project root directory

OPTIONS:
  --paths "p1" "p2" ...   Allowed paths per task (matched by index)
  --context "f1" "f2" ... Context files per task (matched by index)
  --model <model>         Model to use (default: gpt-5.2-codex)
  --reasoning <level>     low/medium/high/extra-high (default: medium)
  --sandbox <mode>        read-only/workspace-write (default: read-only)
  --timeout <minutes>     Per-agent timeout (default: 10)
  --integrator <mode>     automatic/manual/ask (default: manual)
  --async                 Fire-and-forget mode (exit after spawning)
  --help, -h              Show this help

EXAMPLES:
  # Read-only analysis
  ./codex-swarm.sh \
    --tasks "Audit auth module" "Review API security" \
    --paths "src/auth/**" "src/api/**" \
    --dir /project

  # Write mode with worktrees
  ./codex-swarm.sh \
    --tasks "Implement feature A" "Implement feature B" \
    --paths "src/features/a/**" "src/features/b/**" \
    --sandbox workspace-write \
    --integrator automatic \
    --dir /project

SAFEGUARDS:
  - Max 10 agents
  - Protected paths: .env, *.pem, *.key, secrets, credentials
  - Blocked commands: rm -rf, sudo, docker destructive commands
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

check_codex_installed() {
  if ! command -v codex &>/dev/null; then
    echo "ERROR: codex CLI not found" >&2
    echo "" >&2
    echo "Install with: npm i -g @openai/codex" >&2
    exit 1
  fi
}

check_codex_authenticated() {
  if ! codex login status &>/dev/null; then
    echo "ERROR: codex not authenticated" >&2
    echo "" >&2
    echo "Run 'codex' and sign in with ChatGPT" >&2
    exit 1
  fi
}

check_git_repo() {
  if [[ "$SANDBOX" != "workspace-write" ]]; then
    return 0
  fi

  if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Write mode requires a git repository" >&2
    echo "Initialize git or use --sandbox read-only" >&2
    exit 1
  fi

  # Check not inside a worktree
  local git_dir
  git_dir=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null)
  if [[ "$git_dir" == *".git/worktrees/"* ]]; then
    echo "ERROR: Cannot run from inside a git worktree" >&2
    echo "Run from main repository root" >&2
    exit 1
  fi
}

validate_inputs() {
  if [[ -z "$PROJECT_DIR" ]]; then
    echo "ERROR: --dir is required" >&2
    exit 1
  fi

  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "ERROR: Directory does not exist: $PROJECT_DIR" >&2
    exit 1
  fi

  local num_tasks=${#TASKS[@]}
  local num_paths=${#PATHS[@]}
  local num_contexts=${#CONTEXTS[@]}

  if [[ $num_tasks -eq 0 ]]; then
    echo "ERROR: No tasks provided" >&2
    echo "Use: --tasks \"task1\" \"task2\" ..." >&2
    exit 1
  fi

  if [[ $num_tasks -gt $MAX_AGENTS_HARD_CAP ]]; then
    echo "ERROR: Too many tasks ($num_tasks). Maximum is $MAX_AGENTS_HARD_CAP" >&2
    exit 1
  fi

  if [[ $num_paths -gt 0 && $num_paths -ne $num_tasks ]]; then
    echo "WARNING: ${num_paths} paths for ${num_tasks} tasks" >&2
    echo "Missing paths will default to '*' (all files)" >&2
  fi

  if [[ $num_contexts -gt 0 && $num_contexts -ne $num_tasks ]]; then
    echo "WARNING: ${num_contexts} context sets for ${num_tasks} tasks" >&2
    echo "Missing contexts will be empty" >&2
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SAFEGUARD CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

check_protected_paths() {
  local task="$1"
  local task_lower="${task,,}"

  local patterns=(
    ".env" "dotenv"
    ".pem" "private.key" "private key"
    "secret" "credential" "password"
    ".git/" ".git " "git directory" "git folder"
    "node_modules"
  )

  for pattern in "${patterns[@]}"; do
    if [[ "$task_lower" == *"$pattern"* ]]; then
      echo "ERROR: Task references protected path: $pattern" >&2
      echo "Task: $task" >&2
      return 1
    fi
  done
  return 0
}

check_blocked_commands() {
  local task="$1"
  local task_lower="${task,,}"

  local patterns=(
    "rm -rf" "rm  -rf" "rm -r -f" "rm -fr"
    "sudo" "as root" "with sudo"
    "chmod" "chown"
    "curl | bash" "curl|bash" "curl | sh" "wget | bash" "wget|bash"
    "docker system prune" "docker volume prune" "docker volume rm"
    "docker container prune" "docker rm -f" "docker rmi"
    "docker image prune" "docker network prune" "docker network rm"
    "docker-compose down -v" "docker-compose down --rmi"
    "docker compose down -v" "docker compose down --rmi"
    "delete all" "remove everything" "wipe" "purge"
  )

  for pattern in "${patterns[@]}"; do
    if [[ "$task_lower" == *"$pattern"* ]]; then
      echo "ERROR: Task contains blocked command pattern: $pattern" >&2
      echo "Task: $task" >&2
      return 1
    fi
  done
  return 0
}

check_docker_mode() {
  local task="$1"
  local task_lower="${task,,}"

  case "$DOCKER_MODE" in
    none)
      if [[ "$task_lower" == *"docker"* ]]; then
        echo "ERROR: Docker commands blocked (dockerMode: none)" >&2
        echo "Task: $task" >&2
        return 1
      fi
      ;;
    safe)
      # Already handled by check_blocked_commands
      ;;
    allow)
      # No restrictions
      ;;
  esac
  return 0
}

run_safeguard_checks() {
  local failed=0

  for task in "${TASKS[@]}"; do
    if ! check_protected_paths "$task"; then
      failed=1
    fi
    if ! check_blocked_commands "$task"; then
      failed=1
    fi
    if ! check_docker_mode "$task"; then
      failed=1
    fi
  done

  if [[ $failed -eq 1 ]]; then
    echo "" >&2
    echo "Safeguard checks failed. Aborting." >&2
    exit 1
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# LOCK FILE
# ═══════════════════════════════════════════════════════════════════════════════

acquire_lock() {
  mkdir -p "$SWARM_DIR" 2>/dev/null || true

  if mkdir "$LOCK_FILE" 2>/dev/null; then
    return 0
  else
    echo "ERROR: Another swarm is running in this project" >&2
    echo "" >&2
    echo "If this is stale, remove: $LOCK_FILE" >&2
    exit 1
  fi
}

release_lock() {
  rm -rf "$LOCK_FILE" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# GIT WORKTREES
# ═══════════════════════════════════════════════════════════════════════════════

cleanup_stale_worktrees() {
  if [[ ! -d "$PROJECT_DIR" ]]; then
    return
  fi

  cd "$PROJECT_DIR" || return

  if [[ -d "$WORKTREE_DIR" ]]; then
    for wt in "$WORKTREE_DIR"/agent-*; do
      if [[ -d "$wt" ]]; then
        git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
      fi
    done
  fi

  # Clean up branches
  for i in {1..10}; do
    git branch -D "swarm-agent-$i" 2>/dev/null || true
  done
}

create_worktrees() {
  local num_agents=$1

  cd "$PROJECT_DIR" || exit 1

  # Always clean first
  cleanup_stale_worktrees

  mkdir -p "$WORKTREE_DIR"

  for ((i=1; i<=num_agents; i++)); do
    local branch="swarm-agent-$i"
    local wt_path="$WORKTREE_DIR/agent-$i"

    if ! git worktree add "$wt_path" -b "$branch" 2>&1; then
      echo "ERROR: Failed to create worktree for agent $i" >&2
      cleanup_stale_worktrees
      exit 1
    fi

    # Verify creation
    if [[ ! -d "$wt_path" ]]; then
      echo "ERROR: Worktree creation failed silently for agent $i" >&2
      cleanup_stale_worktrees
      exit 1
    fi

    AGENT_WORKTREES+=("$wt_path")
  done
}

check_git_state() {
  if [[ "$SANDBOX" != "workspace-write" ]]; then
    return 0
  fi

  cd "$PROJECT_DIR" || return 0

  # Check for any dirty state (modified, staged, untracked)
  local git_status
  git_status=$(git status --porcelain 2>/dev/null)

  if [[ -n "$git_status" ]]; then
    echo "" >&2
    echo "WARNING: Your working directory is not clean" >&2
    echo "" >&2
    echo "Git worktrees branch from HEAD (last commit)." >&2
    echo "The following changes will NOT be visible to agents:" >&2
    echo "" >&2
    git status --short >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Commit your changes first: git add . && git commit -m 'WIP'" >&2
    echo "  2. Continue anyway (agents work from HEAD)" >&2
    echo "" >&2
    read -p "Continue with dirty state? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
      echo "Aborted. Commit your changes and try again." >&2
      exit 0
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# WORKER CONTRACT
# ═══════════════════════════════════════════════════════════════════════════════

build_worker_contract() {
  local task="$1"
  local allowed_paths="$2"
  local context_files="$3"

  cat <<EOF
WORKER CONTRACT:
- Execute ONE bounded task: $task
- Only read/edit files under: $allowed_paths
- Context files: $context_files
- Do NOT touch files outside allowed paths
- Do NOT refactor unrelated code
- If more context needed, STOP and report what's missing
- Output: 1) summary 2) files changed 3) verification result
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# AGENT EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

spawn_agent() {
  local contract="$1"
  local work_dir="$2"
  local output_file="$3"

  (
    cd "$work_dir" || exit 1
    codex exec "$contract" \
      -s "$SANDBOX" \
      -m "$MODEL" \
      2>&1
  ) > "$output_file" &

  echo $!
}

wait_with_timeout() {
  local pid=$1
  local timeout_seconds=$2
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [[ $elapsed -ge $timeout_seconds ]]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    ((elapsed++))
  done

  wait "$pid"
  return $?
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECRET SCRUBBING
# ═══════════════════════════════════════════════════════════════════════════════

scrub_secrets() {
  sed -E \
    -e 's/sk-[a-zA-Z0-9_-]+/[REDACTED]/g' \
    -e 's/ghp_[a-zA-Z0-9]+/[REDACTED]/g' \
    -e 's/password=[^[:space:]]*/password=[REDACTED]/gi' \
    -e 's/secret=[^[:space:]]*/secret=[REDACTED]/gi' \
    -e 's/token=[^[:space:]]*/token=[REDACTED]/gi' \
    -e 's/api_key=[^[:space:]]*/api_key=[REDACTED]/gi' \
    -e 's/apikey=[^[:space:]]*/apikey=[REDACTED]/gi'
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIMESTAMPS
# ═══════════════════════════════════════════════════════════════════════════════

get_timestamp() {
  date +%Y%m%d-%H%M%S
}

get_iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

format_duration() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local secs=$((seconds % 60))
  echo "${minutes}m ${secs}s"
}

# ═══════════════════════════════════════════════════════════════════════════════
# JOB METADATA (ASYNC MODE)
# ═══════════════════════════════════════════════════════════════════════════════

save_job_metadata() {
  local job_id="$1"
  local task="$2"
  local pid="$3"
  local worktree="$4"

  mkdir -p "$JOBS_DIR"

  cat > "$JOBS_DIR/${job_id}.json" <<EOF
{
  "id": "$job_id",
  "task": "$task",
  "pid": $pid,
  "worktree": "$worktree",
  "started": "$(get_iso_timestamp)",
  "status": "running"
}
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# INTEGRATOR
# ═══════════════════════════════════════════════════════════════════════════════

run_integrator() {
  local num_agents=${#AGENT_WORKTREES[@]}
  local branch_list=""

  for ((i=1; i<=num_agents; i++)); do
    if [[ -n "$branch_list" ]]; then
      branch_list+=", "
    fi
    branch_list+="swarm-agent-$i"
  done

  echo "" >&2
  echo "Running integrator to merge branches..." >&2

  local integrator_contract="Merge branches $branch_list into the current branch. Run tests. Fix conflicts with minimal changes. Summarize all changes."

  cd "$PROJECT_DIR" || return 1

  codex exec "$integrator_contract" \
    -s workspace-write \
    -m "$MODEL"
}

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT FORMATTING
# ═══════════════════════════════════════════════════════════════════════════════

format_results() {
  local num_tasks=${#TASKS[@]}
  local succeeded=0
  local failed=0
  local timed_out=0

  echo "# Swarm Results"
  echo ""

  for ((i=0; i<num_tasks; i++)); do
    local task="${TASKS[$i]}"
    local path="${PATHS[$i]:-*}"
    local status="${STATUSES[$i]}"
    local duration="${DURATIONS[$i]}"
    local output_file="${OUTPUT_FILES[$i]}"

    echo "## Agent $((i+1)): $task"
    echo ""
    echo "**Status:** $status"
    echo "**Duration:** $(format_duration "$duration")"
    echo "**Allowed paths:** $path"

    case "$status" in
      success) ((succeeded++)) ;;
      failed) ((failed++)) ;;
      timeout) ((timed_out++)) ;;
    esac

    if [[ -f "$output_file" ]]; then
      echo ""
      cat "$output_file" | scrub_secrets
    fi

    echo ""
    echo "---"
    echo ""
  done

  echo "## Summary"
  echo ""
  echo "- Total agents: $num_tasks"
  echo "- Succeeded: $succeeded"
  echo "- Failed: $failed"
  echo "- Timed out: $timed_out"
  echo ""

  if [[ "$SANDBOX" == "workspace-write" && "$INTEGRATOR" == "manual" ]]; then
    echo "## Merge Instructions"
    echo ""
    echo "Branches created:"
    for ((i=1; i<=num_tasks; i++)); do
      echo "- swarm-agent-$i"
    done
    echo ""
    echo "To merge: \`git merge swarm-agent-N\`"
    echo ""
  elif [[ "$SANDBOX" == "read-only" ]]; then
    echo "## Next Steps"
    echo ""
    echo "Review findings above. Use write mode to implement changes."
    echo ""
  fi
}

save_log() {
  mkdir -p "$LOGS_DIR" 2>/dev/null || true

  if [[ ! -w "$LOGS_DIR" ]]; then
    echo "WARNING: Cannot write to logs directory" >&2
    return
  fi

  local timestamp
  timestamp=$(get_timestamp)
  local log_file="$LOGS_DIR/${timestamp}_swarm.md"

  format_results > "$log_file"
  echo "Results saved to: $log_file" >&2
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

cleanup() {
  [[ "$CLEANUP_DONE" == "true" ]] && return
  CLEANUP_DONE=true

  local exit_code=$?

  echo "" >&2
  echo "Shutting down swarm..." >&2

  # Kill all spawned agents
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null
    fi
  done

  sleep 1

  # Force kill any remaining
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done

  # Clean up temp files
  for f in "${OUTPUT_FILES[@]}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done

  # Clean up worktrees (if write mode and not keeping them)
  if [[ "$SANDBOX" == "workspace-write" && "$INTEGRATOR" != "manual" ]]; then
    cleanup_stale_worktrees
  fi

  # Release lock
  release_lock

  echo "Cleanup complete" >&2
  exit $exit_code
}

trap cleanup SIGINT SIGTERM EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  load_config
  parse_args "$@"

  # Validation
  validate_inputs
  check_codex_installed
  check_codex_authenticated
  check_git_repo

  # Acquire lock
  acquire_lock

  # Safeguard checks
  run_safeguard_checks

  local num_tasks=${#TASKS[@]}

  # Write mode setup
  if [[ "$SANDBOX" == "workspace-write" ]]; then
    echo "" >&2
    echo "Write mode with $num_tasks agents." >&2
    echo "Agents will work in isolated git worktrees." >&2
    echo "" >&2
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
      echo "Aborted." >&2
      exit 0
    fi

    check_git_state
    create_worktrees "$num_tasks"
  fi

  # Spawn agents
  local timestamp
  timestamp=$(get_timestamp)

  echo "" >&2
  echo "Spawning $num_tasks agents..." >&2
  echo "" >&2

  for ((i=0; i<num_tasks; i++)); do
    local task="${TASKS[$i]}"
    local path="${PATHS[$i]:-*}"
    local context="${CONTEXTS[$i]:-}"

    local contract
    contract=$(build_worker_contract "$task" "$path" "$context")

    local output_file
    output_file=$(mktemp)
    OUTPUT_FILES+=("$output_file")

    local work_dir="$PROJECT_DIR"
    if [[ "$SANDBOX" == "workspace-write" ]]; then
      work_dir="${AGENT_WORKTREES[$i]}"
    fi

    if [[ "$ASYNC" == "true" ]]; then
      local job_id="swarm-${timestamp}-$((i+1))"
      local pid
      pid=$(spawn_agent "$contract" "$work_dir" "$output_file")
      PIDS+=("$pid")
      save_job_metadata "$job_id" "$task" "$pid" "$work_dir"
      echo "- $job_id: \"$task\""
    else
      local pid
      pid=$(spawn_agent "$contract" "$work_dir" "$output_file")
      PIDS+=("$pid")
      echo "- Agent $((i+1)): $task (PID: $pid)" >&2
    fi
  done

  # Async mode: exit immediately
  if [[ "$ASYNC" == "true" ]]; then
    echo "" >&2
    echo "Swarm started (async mode)" >&2
    echo "Job metadata saved to: $JOBS_DIR/" >&2
    echo "" >&2
    echo "To check status: ls $WORKTREE_DIR/" >&2
    echo "To get results: cat $JOBS_DIR/swarm-*.json" >&2

    # Don't cleanup in async mode
    CLEANUP_DONE=true
    release_lock
    exit 0
  fi

  # Sync mode: wait for all
  echo "" >&2
  echo "Waiting for agents to complete..." >&2

  local timeout_seconds=$((TIMEOUT * 60))

  for ((i=0; i<num_tasks; i++)); do
    local agent_start
    agent_start=$(date +%s)

    wait_with_timeout "${PIDS[$i]}" "$timeout_seconds"
    local status=$?

    local agent_end
    agent_end=$(date +%s)

    if [[ $status -eq 0 ]]; then
      STATUSES+=("success")
      echo "- Agent $((i+1)): success" >&2
    elif [[ $status -eq 124 ]]; then
      STATUSES+=("timeout")
      echo "- Agent $((i+1)): timeout (${TIMEOUT}m)" >&2
    else
      STATUSES+=("failed")
      echo "- Agent $((i+1)): failed (exit $status)" >&2
    fi

    DURATIONS+=("$((agent_end - agent_start))")
  done

  # Commit agent changes to their branches (write mode only)
  if [[ "$SANDBOX" == "workspace-write" ]]; then
    echo "" >&2
    echo "Committing agent changes..." >&2
    for ((i=0; i<num_tasks; i++)); do
      local wt="${AGENT_WORKTREES[$i]}"
      if [[ -d "$wt" ]]; then
        (
          cd "$wt" || continue
          if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            git add -A
            git commit -m "Swarm agent $((i+1)): ${TASKS[$i]}" 2>/dev/null && \
              echo "- Agent $((i+1)): committed" >&2 || \
              echo "- Agent $((i+1)): no changes to commit" >&2
          else
            echo "- Agent $((i+1)): no changes" >&2
          fi
        )
      fi
    done
  fi

  echo "" >&2

  # Format and output results
  format_results

  # Integrator handling (write mode only)
  if [[ "$SANDBOX" == "workspace-write" ]]; then
    case "$INTEGRATOR" in
      automatic)
        run_integrator
        cleanup_stale_worktrees
        ;;
      manual)
        # Worktrees kept, instructions shown in format_results
        ;;
      ask)
        echo "" >&2
        read -p "Run integrator to merge branches? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
          run_integrator
          cleanup_stale_worktrees
        fi
        ;;
    esac
  fi

  # Save log if enabled
  if [[ "$LOGGING" == "true" ]]; then
    save_log
  fi
}

main "$@"
