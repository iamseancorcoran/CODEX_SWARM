#!/usr/bin/env bash
#
# validate.sh - Verify codex-swarm installation
#
# Run after copying template to a project to verify everything is set up correctly.
#

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Validating codex-swarm installation..."
echo ""

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "[PASS] $name"
    ((PASS++)) || true
  else
    echo "[FAIL] $name"
    ((FAIL++)) || true
  fi
}

warn() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "[PASS] $name"
    ((PASS++)) || true
  else
    echo "[WARN] $name (optional)"
    ((WARN++)) || true
  fi
}

echo "=== File Structure ==="
check "codex-swarm.sh exists" "[[ -f '$SCRIPT_DIR/codex-swarm.sh' ]]"
check "codex-swarm.sh executable" "[[ -x '$SCRIPT_DIR/codex-swarm.sh' ]]"
check "config.json exists" "[[ -f '$SCRIPT_DIR/config.json' ]]"
check "SETUP.md exists" "[[ -f '$SCRIPT_DIR/SETUP.md' ]]"
check "README.md exists" "[[ -f '$SCRIPT_DIR/README.md' ]]"
check "logs/ directory exists" "[[ -d '$SCRIPT_DIR/logs' ]]"
check "jobs/ directory exists" "[[ -d '$SCRIPT_DIR/jobs' ]]"

echo ""
echo "=== System Dependencies ==="
check "bash 4.0+" "[[ \${BASH_VERSINFO[0]} -ge 4 ]]"
warn "jq installed" "command -v jq"
check "git installed" "command -v git"
warn "codex installed" "command -v codex"

echo ""
echo "=== Script Syntax ==="
check "codex-swarm.sh parses" "bash -n '$SCRIPT_DIR/codex-swarm.sh'"
check "validate.sh parses" "bash -n '$SCRIPT_DIR/validate.sh'"

# Only run config checks if jq is available
if command -v jq &>/dev/null; then
  echo ""
  echo "=== Config Validation ==="
  check "config.json valid JSON" "jq empty '$SCRIPT_DIR/config.json'"
  check "model is gpt-5.2-codex" "[[ \$(jq -r .model '$SCRIPT_DIR/config.json') == 'gpt-5.2-codex' ]]"
  check "sandbox is read-only" "[[ \$(jq -r .sandbox '$SCRIPT_DIR/config.json') == 'read-only' ]]"
  check "timeout is 10" "[[ \$(jq -r .timeout '$SCRIPT_DIR/config.json') == '10' ]]"
  check "reasoning is medium" "[[ \$(jq -r .reasoning '$SCRIPT_DIR/config.json') == 'medium' ]]"
  check "logging is true" "[[ \$(jq -r .logging '$SCRIPT_DIR/config.json') == 'true' ]]"
  check "integratorMode is manual" "[[ \$(jq -r .integratorMode '$SCRIPT_DIR/config.json') == 'manual' ]]"
  check "dockerMode is safe" "[[ \$(jq -r .dockerMode '$SCRIPT_DIR/config.json') == 'safe' ]]"

  echo ""
  echo "=== Safeguards ==="
  check "blockedCommands array exists" "jq -e '.blockedCommands | length > 0' '$SCRIPT_DIR/config.json'"
  check "protectedPaths array exists" "jq -e '.protectedPaths | length > 0' '$SCRIPT_DIR/config.json'"
  check "blockedCommands has rm -rf" "jq -e '.blockedCommands | index(\"rm -rf\")' '$SCRIPT_DIR/config.json'"
  check "blockedCommands has sudo" "jq -e '.blockedCommands | index(\"sudo\")' '$SCRIPT_DIR/config.json'"
  check "protectedPaths has .env" "jq -e '.protectedPaths | index(\".env\")' '$SCRIPT_DIR/config.json'"
else
  echo ""
  echo "=== Config Validation ==="
  echo "[SKIP] jq not installed - skipping JSON validation"
fi

echo ""
echo "================================"
echo "Results:"
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
echo "  Warned:  $WARN"
echo "================================"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "VALIDATION FAILED"
  echo "Fix the issues above before using codex-swarm."
  exit 1
else
  echo ""
  echo "VALIDATION PASSED"
  if [[ $WARN -gt 0 ]]; then
    echo "Some optional dependencies are missing (see warnings above)."
  fi
  exit 0
fi
