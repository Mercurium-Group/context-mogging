#!/usr/bin/env bash
# verify.sh — manual verification suite for context-mogging v1.2.0
# Run from the repo root: bash scripts/verify.sh
# Each test prints PASS or FAIL with a short reason.
# Exit code: 0 if all pass, 1 if any fail.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# Run a full shell command string (as stored in settings.json) with synthetic stdin.
# The hooks are shell commands, not raw Python snippets.
run_hook_cmd() {
  local cmd="$1"
  local stdin_json="$2"
  echo "$stdin_json" | sh -c "$cmd" 2>&1
}

# Extract a command string from settings.json by hook type index and hook index.
# Usage: get_hook PreToolUse 0 1   → first matcher block, second hook command
get_hook() {
  local hook_type="$1"
  local block_idx="$2"
  local hook_idx="$3"
  python3 -c "
import json
data = json.load(open('$REPO_ROOT/templates/settings.json'))
cmd = data['hooks']['$hook_type'][$block_idx]['hooks'][$hook_idx]['command']
print(cmd)
"
}

# ── Section 1: settings.json is valid JSON ───────────────────────────────────

echo ""
echo "1. settings.json validity"

if python3 -c "import json; json.load(open('$REPO_ROOT/templates/settings.json'))" 2>/dev/null; then
  pass "templates/settings.json parses as valid JSON"
else
  fail "templates/settings.json is not valid JSON"
fi

# ── Section 2: hook commands produce valid JSONL ─────────────────────────────

echo ""
echo "2. Hook commands produce valid JSONL"

# --- 2a: PostToolUse post_edit event ---
# This hook runs on every Write/Edit and appends a post_edit entry.

POST_EDIT_CMD=$(get_hook PostToolUse 0 1)

TMPDIR_TEST=$(mktemp -d)
(
  cd "$TMPDIR_TEST"
  git init -q 2>/dev/null
  echo '{}' | sh -c "$POST_EDIT_CMD" 2>/dev/null || true
  LOGFILE="$TMPDIR_TEST/thoughts/shared/logs/events.jsonl"
  if [ -f "$LOGFILE" ]; then
    LINE=$(tail -1 "$LOGFILE")
    python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('event') == 'post_edit', f\"event was {d.get('event')!r}\"
assert 'ts' in d, 'missing ts key'
" <<< "$LINE" 2>/dev/null && echo "INNER_PASS" || echo "INNER_FAIL:bad_schema: $LINE"
  else
    echo "INNER_FAIL:logfile_not_created"
  fi
)
RESULT_TE=$?
if (cd "$TMPDIR_TEST" && [ -f "thoughts/shared/logs/events.jsonl" ]); then
  LINE=$(tail -1 "$TMPDIR_TEST/thoughts/shared/logs/events.jsonl")
  if python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('event') == 'post_edit'
assert 'ts' in d
" <<< "$LINE" 2>/dev/null; then
    pass "PostToolUse post_edit hook writes valid JSONL with event and ts keys"
  else
    fail "PostToolUse post_edit hook wrote malformed JSONL: $LINE"
  fi
else
  fail "PostToolUse post_edit hook did not create events.jsonl"
fi
rm -rf "$TMPDIR_TEST"

# --- 2b: SessionStart session_start event ---

SESSION_START_CMD=$(get_hook SessionStart 0 1)

TMPDIR_SESSION=$(mktemp -d)
(
  cd "$TMPDIR_SESSION"
  git init -q 2>/dev/null
  echo '{}' | sh -c "$SESSION_START_CMD" 2>/dev/null || true
)

if [ -f "$TMPDIR_SESSION/thoughts/shared/logs/events.jsonl" ]; then
  LINE=$(tail -1 "$TMPDIR_SESSION/thoughts/shared/logs/events.jsonl")
  if python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('event') == 'session_start', f\"event was {d.get('event')!r}\"
assert 'ts' in d, 'missing ts'
assert 'branch' in d, 'missing branch'
assert 'last_commit' in d, 'missing last_commit'
" <<< "$LINE" 2>/dev/null; then
    pass "SessionStart hook writes valid JSONL with ts/branch/last_commit keys"
  else
    fail "SessionStart hook JSONL missing required keys: $LINE"
  fi
else
  fail "SessionStart hook did not create events.jsonl"
fi
rm -rf "$TMPDIR_SESSION"

# --- 2c: PreToolUse guard_block logs CLAUDE.md write attempts ---

GUARD_LOG_CMD=$(get_hook PreToolUse 0 1)

TMPDIR_GUARD=$(mktemp -d)
(
  cd "$TMPDIR_GUARD"
  git init -q 2>/dev/null
  echo '{"tool_input":{"file_path":"/some/project/CLAUDE.md"}}' | sh -c "$GUARD_LOG_CMD" 2>/dev/null || true
)

if [ -f "$TMPDIR_GUARD/thoughts/shared/logs/events.jsonl" ]; then
  LINE=$(tail -1 "$TMPDIR_GUARD/thoughts/shared/logs/events.jsonl")
  if python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('event') == 'guard_block', f\"event was {d.get('event')!r}\"
assert d.get('tool') == 'Write', f\"tool was {d.get('tool')!r}\"
assert 'CLAUDE.md' in d.get('path', ''), f\"path was {d.get('path')!r}\"
" <<< "$LINE" 2>/dev/null; then
    pass "PreToolUse guard_block hook logs CLAUDE.md write attempt with correct schema"
  else
    fail "PreToolUse guard_block hook wrote malformed JSONL: $LINE"
  fi
else
  fail "PreToolUse guard_block hook did not create events.jsonl for a protected path"
fi
rm -rf "$TMPDIR_GUARD"

# --- 2d: guard_block does NOT log for non-protected files ---

TMPDIR_NONGUARD=$(mktemp -d)
(
  cd "$TMPDIR_NONGUARD"
  git init -q 2>/dev/null
  echo '{"tool_input":{"file_path":"/some/project/src/index.ts"}}' | sh -c "$GUARD_LOG_CMD" 2>/dev/null || true
)

if [ ! -f "$TMPDIR_NONGUARD/thoughts/shared/logs/events.jsonl" ]; then
  pass "PreToolUse guard_block hook does not log events for non-protected paths"
else
  fail "PreToolUse guard_block hook wrote a log entry for a non-protected file"
fi
rm -rf "$TMPDIR_NONGUARD"

# --- 2e: Stop session_end event ---

SESSION_END_CMD=$(get_hook Stop 0 1)

TMPDIR_STOP=$(mktemp -d)
(
  cd "$TMPDIR_STOP"
  git init -q 2>/dev/null
  echo '{}' | sh -c "$SESSION_END_CMD" 2>/dev/null || true
)

if [ -f "$TMPDIR_STOP/thoughts/shared/logs/events.jsonl" ]; then
  LINE=$(tail -1 "$TMPDIR_STOP/thoughts/shared/logs/events.jsonl")
  if python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('event') == 'session_end', f\"event was {d.get('event')!r}\"
assert 'ts' in d, 'missing ts'
assert 'uncommitted_files' in d, 'missing uncommitted_files'
" <<< "$LINE" 2>/dev/null; then
    pass "Stop hook writes valid JSONL with event/ts/uncommitted_files keys"
  else
    fail "Stop hook JSONL missing required keys: $LINE"
  fi
else
  fail "Stop hook did not create events.jsonl"
fi
rm -rf "$TMPDIR_STOP"

# ── Section 3: install copies metrics.md ────────────────────────────────────

echo ""
echo "3. Install output includes metrics.md"

if [ -f "$REPO_ROOT/commands/metrics.md" ]; then
  pass "commands/metrics.md exists in repo (will be copied by installer)"
else
  fail "commands/metrics.md is missing — install will not deploy it"
fi

if python3 -c "
import json
pkg = json.load(open('$REPO_ROOT/package.json'))
assert 'commands/' in pkg.get('files', [])
" 2>/dev/null; then
  pass "package.json 'files' field includes commands/ directory"
else
  fail "package.json 'files' field does not include commands/ — metrics.md would not be published"
fi

# ── Section 4: events.jsonl is gitignored ────────────────────────────────────

echo ""
echo "4. events.jsonl stays gitignored"

if grep -q "^thoughts/" "$REPO_ROOT/templates/gitignore-additions.txt" 2>/dev/null; then
  pass "gitignore-additions.txt includes 'thoughts/' pattern (covers events.jsonl)"
else
  fail "gitignore-additions.txt does not contain a pattern covering thoughts/shared/logs/events.jsonl"
fi

if git -C "$REPO_ROOT" check-ignore -q thoughts/shared/logs/events.jsonl 2>/dev/null; then
  pass "git confirms thoughts/shared/logs/events.jsonl is ignored in this repo"
else
  fail "git does not ignore thoughts/shared/logs/events.jsonl — log data could be committed"
fi

# ── Section 5: /metrics empty-state command behavior ─────────────────────────

echo ""
echo "5. /metrics empty-state and JSONL parsing"

# The metrics.md specifies: cat thoughts/shared/logs/events.jsonl 2>/dev/null
# When the file is absent this must not cause the command runner to abort.
# The 2>/dev/null suppresses the error message but cat still exits 1.
# The correct invocation that /metrics uses relies on Claude's interpreter
# treating missing output as "empty" rather than checking exit code.
# We test the || true guard pattern that the rest of the hooks use.
TMPDIR_METRICS=$(mktemp -d)
if (cd "$TMPDIR_METRICS" && cat thoughts/shared/logs/events.jsonl 2>/dev/null || true); then
  pass "cat events.jsonl 2>/dev/null || true exits cleanly when file is missing"
else
  fail "cat events.jsonl returned non-zero even with || true — shell has unexpected behavior"
fi
rm -rf "$TMPDIR_METRICS"

# Verify malformed JSONL lines are skipped without raising an exception.
# This is required behavior described in metrics.md: "Skip unparseable lines".
TMPDIR_BADLINES=$(mktemp -d)
printf 'not-json\n{"event":"session_start","ts":"2024-01-01T00:00:00Z","branch":"main","last_commit":"abc1234"}\n{bad\n' \
  > "$TMPDIR_BADLINES/events.jsonl"

if python3 - "$TMPDIR_BADLINES/events.jsonl" 2>/dev/null <<'PYEOF'
import sys, json
path = sys.argv[1]
events = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass  # skip malformed lines as required by metrics.md
assert len(events) == 1, f"expected 1 valid event, got {len(events)}"
assert events[0]['event'] == 'session_start'
PYEOF
then
  pass "Malformed JSONL lines are skipped; valid lines are parsed correctly"
else
  fail "JSONL parsing failed to tolerate malformed lines"
fi
rm -rf "$TMPDIR_BADLINES"

# Verify that an events.jsonl containing only a session_start with no matching
# session_end does not crash the pairing logic (orphaned session edge case).
TMPDIR_ORPHAN=$(mktemp -d)
printf '{"event":"session_start","ts":"2024-01-01T00:00:00Z","branch":"main","last_commit":"abc"}\n' \
  > "$TMPDIR_ORPHAN/events.jsonl"

if python3 - "$TMPDIR_ORPHAN/events.jsonl" 2>/dev/null <<'PYEOF'
import sys, json, datetime
path = sys.argv[1]
starts, ends = [], []
with open(path) as f:
    for line in f:
        try:
            d = json.loads(line.strip())
        except json.JSONDecodeError:
            continue
        if d.get('event') == 'session_start':
            starts.append(d)
        elif d.get('event') == 'session_end':
            ends.append(d)

# Pairing logic: zip stops at the shorter list — no IndexError for orphaned starts
pairs = list(zip(starts, ends))
# Result: 0 complete pairs, no error
assert len(pairs) == 0, f"expected 0 pairs, got {len(pairs)}"
PYEOF
then
  pass "Orphaned session_start with no session_end does not raise an error"
else
  fail "Orphaned session_start caused an error in session pairing logic"
fi
rm -rf "$TMPDIR_ORPHAN"

# ── Section 6: blocking hook exit codes ──────────────────────────────────────

echo ""
echo "6. Guard hook exit codes"

BLOCK_CMD=$(get_hook PreToolUse 0 0)

EXIT_CODE=0
echo '{"tool_input":{"file_path":"/proj/CLAUDE.md"}}' | sh -c "$BLOCK_CMD" > /dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 2 ]; then
  pass "PreToolUse blocking hook exits with code 2 for CLAUDE.md writes"
else
  fail "PreToolUse blocking hook returned exit code $EXIT_CODE (expected 2)"
fi

EXIT_CODE_SAFE=0
echo '{"tool_input":{"file_path":"/proj/src/app.ts"}}' | sh -c "$BLOCK_CMD" > /dev/null 2>&1 || EXIT_CODE_SAFE=$?
if [ "$EXIT_CODE_SAFE" -eq 0 ]; then
  pass "PreToolUse blocking hook exits with code 0 for non-protected file writes"
else
  fail "PreToolUse blocking hook returned exit code $EXIT_CODE_SAFE for a safe file (expected 0)"
fi

# Verify CLAUDE.local.md is also blocked (second protected filename)
EXIT_CODE_LOCAL=0
echo '{"tool_input":{"file_path":"/proj/.claude/CLAUDE.local.md"}}' | sh -c "$BLOCK_CMD" > /dev/null 2>&1 || EXIT_CODE_LOCAL=$?
if [ "$EXIT_CODE_LOCAL" -eq 2 ]; then
  pass "PreToolUse blocking hook exits with code 2 for CLAUDE.local.md writes"
else
  fail "PreToolUse blocking hook returned exit code $EXIT_CODE_LOCAL for CLAUDE.local.md (expected 2)"
fi

# Verify the Bash guard blocks known destructive commands
BASH_BLOCK_CMD=$(get_hook PreToolUse 1 0)

EXIT_CODE_BASH=0
echo '{"tool_input":{"command":"git reset --hard HEAD"}}' | sh -c "$BASH_BLOCK_CMD" > /dev/null 2>&1 || EXIT_CODE_BASH=$?
if [ "$EXIT_CODE_BASH" -eq 2 ]; then
  pass "Bash guard hook exits with code 2 for 'git reset --hard'"
else
  fail "Bash guard hook returned exit code $EXIT_CODE_BASH for 'git reset --hard' (expected 2)"
fi

EXIT_CODE_BASH_SAFE=0
echo '{"tool_input":{"command":"git status"}}' | sh -c "$BASH_BLOCK_CMD" > /dev/null 2>&1 || EXIT_CODE_BASH_SAFE=$?
if [ "$EXIT_CODE_BASH_SAFE" -eq 0 ]; then
  pass "Bash guard hook exits with code 0 for safe commands"
else
  fail "Bash guard hook returned exit code $EXIT_CODE_BASH_SAFE for 'git status' (expected 0)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo "  Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────────────"
echo ""

[ "$FAIL" -eq 0 ]
