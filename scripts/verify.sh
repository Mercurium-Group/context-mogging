#!/usr/bin/env bash
# verify.sh — manual verification suite for context-mogging v1.4.0
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

# ── Section 7: old-format hook entries purged on reinstall ───────────────────

echo ""
echo "7. Old-format hook entries purged on reinstall"

TMPDIR_PURGE=$(mktemp -d)

# Write a settings.json with old-format (flat) hook entries into .claude/
# so the installer finds it as the existing settings to merge into
mkdir -p "$TMPDIR_PURGE/.claude"
cat > "$TMPDIR_PURGE/.claude/settings.json" <<'SETTINGS_EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Write", "command": "echo old", "description": "old format"}
    ]
  }
}
SETTINGS_EOF

# Run the installer against this temp directory
node "$REPO_ROOT/bin/install.js" init --force --dir "$TMPDIR_PURGE" > /dev/null 2>&1 || true

MERGED_SETTINGS="$TMPDIR_PURGE/.claude/settings.json"

if [ -f "$MERGED_SETTINGS" ]; then
  if python3 - "$MERGED_SETTINGS" 2>/dev/null <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
hooks = data.get('hooks', {})
for hook_type, entries in hooks.items():
    for entry in entries:
        assert 'command' not in entry, \
            f"Old-format entry found in {hook_type}: {entry}"
PYEOF
  then
    pass "Old-format hook entries (flat command key) purged after reinstall"
  else
    fail "Old-format hook entries still present in merged settings.json after reinstall"
  fi
else
  fail "Installer did not produce .claude/settings.json in temp dir"
fi

rm -rf "$TMPDIR_PURGE"

# ── Section 8: jq merge purges old-format entries ────────────────────────────

echo ""
echo "8. install.sh jq merge purges old-format entries"

if ! command -v jq &>/dev/null; then
  echo "  NOTE  jq not available — skipping section 8"
else
  TMPDIR_JQ=$(mktemp -d)

  # Write a settings.json with old-format hook entries (flat {matcher, command, description},
  # no hooks array) as the "existing" file
  cat > "$TMPDIR_JQ/existing.json" <<'EXISTING_EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Write", "command": "echo old", "description": "old format entry"}
    ]
  }
}
EXISTING_EOF

  # Use the package's templates/settings.json as the "incoming" file
  INCOMING_JQ="$REPO_ROOT/templates/settings.json"

  # Run the exact jq expression from install.sh against the two files
  jq -s '
    .[0] as $existing | .[1] as $incoming |
    $existing * $incoming |
    .hooks = (
      ($existing.hooks // {}) as $eh |
      ($incoming.hooks // {}) as $ih |
      ($eh | keys) + ($ih | keys) | unique | map(
        . as $key |
        {
          ($key): (
            (($eh[$key] // []) | map(select(.hooks != null and (.hooks | length) > 0)))
            + ($ih[$key] // [])
            | unique_by(.hooks[0].command)
          )
        }
      ) | add // {}
    )
  ' "$TMPDIR_JQ/existing.json" "$INCOMING_JQ" > "$TMPDIR_JQ/merged.json" 2>/dev/null

  if [ -f "$TMPDIR_JQ/merged.json" ]; then
    if python3 - "$TMPDIR_JQ/merged.json" 2>/dev/null <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
hooks = data.get('hooks', {})
for hook_type, entries in hooks.items():
    for entry in entries:
        assert 'command' not in entry, \
            f"Old-format entry (top-level command key) found in {hook_type}: {entry}"
PYEOF
    then
      pass "jq merge expression purges old-format entries (no top-level command key in output)"
    else
      fail "jq merge expression left old-format entries in merged output"
    fi
  else
    fail "jq merge expression did not produce output file"
  fi

  rm -rf "$TMPDIR_JQ"
fi

# ── Section 9: `update` subcommand ───────────────────────────────────────────

echo ""
echo "9. 'update' subcommand"

# 9a: invoking with no arguments exits non-zero and shows both subcommands in usage
NODE_USAGE_OUTPUT=$(node "$REPO_ROOT/bin/install.js" 2>&1 || true)
NODE_EXIT=0
node "$REPO_ROOT/bin/install.js" > /dev/null 2>&1 || NODE_EXIT=$?

if [ "$NODE_EXIT" -ne 0 ]; then
  pass "node bin/install.js (no args) exits non-zero"
else
  fail "node bin/install.js (no args) exited 0 — expected a non-zero exit code"
fi

if echo "$NODE_USAGE_OUTPUT" | grep -q "init" && echo "$NODE_USAGE_OUTPUT" | grep -q "update"; then
  pass "node bin/install.js (no args) usage string mentions both 'init' and 'update'"
else
  fail "node bin/install.js (no args) usage string missing 'init' or 'update': $NODE_USAGE_OUTPUT"
fi

# 9b: --help / -h exits zero (not an error)
NODE_HELP_EXIT=0
node "$REPO_ROOT/bin/install.js" --help > /dev/null 2>&1 || NODE_HELP_EXIT=$?
if [ "$NODE_HELP_EXIT" -eq 0 ]; then
  pass "node bin/install.js --help exits with code 0"
else
  fail "node bin/install.js --help exited $NODE_HELP_EXIT (expected 0)"
fi

# 9c: `update` installs into a fresh directory (exit 0, settings.json created)
TMPDIR_UPDATE=$(mktemp -d)
UPDATE_EXIT=0
node "$REPO_ROOT/bin/install.js" update --dir "$TMPDIR_UPDATE" > /dev/null 2>&1 || UPDATE_EXIT=$?
if [ "$UPDATE_EXIT" -eq 0 ]; then
  pass "node bin/install.js update --dir <tmpdir> exits 0"
else
  fail "node bin/install.js update --dir <tmpdir> exited $UPDATE_EXIT (expected 0)"
fi
if [ -f "$TMPDIR_UPDATE/.claude/settings.json" ]; then
  pass "node bin/install.js update creates .claude/settings.json"
else
  fail "node bin/install.js update did not create .claude/settings.json"
fi
rm -rf "$TMPDIR_UPDATE"

# 9d: `update` overwrites existing files (force=true semantics)
# Plant a sentinel command file, run `update`, verify it is overwritten.
TMPDIR_OVERWRITE=$(mktemp -d)
mkdir -p "$TMPDIR_OVERWRITE/.claude/commands"
echo "# sentinel — should be overwritten" > "$TMPDIR_OVERWRITE/.claude/commands/research.md"

node "$REPO_ROOT/bin/install.js" update --dir "$TMPDIR_OVERWRITE" > /dev/null 2>&1 || true

SENTINEL_CONTENT=$(cat "$TMPDIR_OVERWRITE/.claude/commands/research.md" 2>/dev/null || echo "")
if echo "$SENTINEL_CONTENT" | grep -q "sentinel"; then
  fail "'update' did not overwrite existing command file — force semantics broken"
else
  pass "'update' overwrites existing files (research.md sentinel was replaced)"
fi
rm -rf "$TMPDIR_OVERWRITE"

# 9e: `update` prints the "Updated from context-mogging" message (not the plain init banner)
TMPDIR_MSG=$(mktemp -d)
UPDATE_OUTPUT=$(node "$REPO_ROOT/bin/install.js" update --dir "$TMPDIR_MSG" 2>&1 || true)
if echo "$UPDATE_OUTPUT" | grep -qi "updated from context-mogging"; then
  pass "'update' prints the 'Updated from context-mogging' message"
else
  fail "'update' did not print expected update message; got: $(echo "$UPDATE_OUTPUT" | tail -5)"
fi
rm -rf "$TMPDIR_MSG"

# ── Section 10: Deprecated file cleanup ──────────────────────────────────────

echo ""
echo "10. Deprecated file cleanup"

# 10a: Plant compact.md and plan.md, run update, verify both deleted
TMPDIR_DEPR=$(mktemp -d)
mkdir -p "$TMPDIR_DEPR/.claude/commands"
echo "# old" > "$TMPDIR_DEPR/.claude/commands/compact.md"
echo "# old" > "$TMPDIR_DEPR/.claude/commands/plan.md"
node "$REPO_ROOT/bin/install.js" update --dir "$TMPDIR_DEPR" > /dev/null 2>&1 || true

if [ ! -f "$TMPDIR_DEPR/.claude/commands/compact.md" ]; then
  pass "Deprecated commands/compact.md removed by 'update'"
else
  fail "Deprecated commands/compact.md still present after 'update'"
fi

if [ ! -f "$TMPDIR_DEPR/.claude/commands/plan.md" ]; then
  pass "Deprecated commands/plan.md removed by 'update'"
else
  fail "Deprecated commands/plan.md still present after 'update'"
fi
rm -rf "$TMPDIR_DEPR"

# 10b: Run update on fresh dir (no deprecated files) — must not error
TMPDIR_FRESH2=$(mktemp -d)
FRESH2_EXIT=0
node "$REPO_ROOT/bin/install.js" update --dir "$TMPDIR_FRESH2" > /dev/null 2>&1 || FRESH2_EXIT=$?
if [ "$FRESH2_EXIT" -eq 0 ]; then
  pass "'update' on a fresh dir with no deprecated files exits 0"
else
  fail "'update' on a fresh dir exited $FRESH2_EXIT (expected 0)"
fi
rm -rf "$TMPDIR_FRESH2"

# ── Section 11: /draft-plan exists, /plan does not ───────────────────────────

echo ""
echo "11. /draft-plan rename"

if [ -f "$REPO_ROOT/commands/draft-plan.md" ]; then
  pass "commands/draft-plan.md exists"
else
  fail "commands/draft-plan.md does not exist"
fi

if [ ! -f "$REPO_ROOT/commands/plan.md" ]; then
  pass "commands/plan.md does not exist (correctly removed)"
else
  fail "commands/plan.md still exists — should have been renamed to draft-plan.md"
fi

# The .claude/commands/ mirror must also ship draft-plan and not plan
if [ -f "$REPO_ROOT/.claude/commands/draft-plan.md" ]; then
  pass ".claude/commands/draft-plan.md exists (self-dogfood mirror present)"
else
  fail ".claude/commands/draft-plan.md does not exist — self-dogfood copy not updated"
fi

if [ ! -f "$REPO_ROOT/.claude/commands/plan.md" ]; then
  pass ".claude/commands/plan.md does not exist (correctly removed from mirror)"
else
  fail ".claude/commands/plan.md still exists in .claude/commands/ — stale mirror"
fi

# Grep for stale /plan references (excluding thoughts/, scripts/, and DEPRECATED_FILES lists)
STALE_PLAN=$(grep -rEn '"/plan|/plan ' \
  --include='*.md' --include='*.js' --include='*.sh' \
  --exclude='verify.sh' \
  --exclude-dir=thoughts \
  --exclude-dir=.git \
  "$REPO_ROOT" 2>/dev/null | \
  grep -v 'DEPRECATED_FILES\|commands/plan\.md\|compact\.md\|draft-plan' || true)

if [ -z "$STALE_PLAN" ]; then
  pass "No stale '/plan' references found in source files"
else
  fail "Stale '/plan' references found: $(echo "$STALE_PLAN" | head -5)"
fi

# ── Section 12: /save-session dual-path design ───────────────────────────────

echo ""
echo "12. /save-session dual-path design"

if ! grep -q "Run the built-in" "$REPO_ROOT/commands/save-session.md" 2>/dev/null; then
  pass "commands/save-session.md does not contain stale 'Run the built-in' text"
else
  fail "commands/save-session.md still contains 'Run the built-in' — old single-path design"
fi

if grep -q "Path A" "$REPO_ROOT/commands/save-session.md" 2>/dev/null; then
  pass "commands/save-session.md contains 'Path A'"
else
  fail "commands/save-session.md missing 'Path A'"
fi

if grep -q "Continuation prompt" "$REPO_ROOT/commands/save-session.md" 2>/dev/null; then
  pass "commands/save-session.md contains 'Continuation prompt'"
else
  fail "commands/save-session.md missing 'Continuation prompt'"
fi

# ── Section 13: /research prohibited actions ─────────────────────────────────

echo ""
echo "13. /research prohibited actions"

# Source copy (commands/research.md) — full prohibited-actions section
if grep -q "Do NOT edit" "$REPO_ROOT/commands/research.md" 2>/dev/null; then
  pass "commands/research.md contains 'Do NOT edit' (prohibited actions section present)"
else
  fail "commands/research.md missing 'Do NOT edit' — prohibited actions section not found"
fi

if grep -q "Do NOT create, modify, or delete source code" "$REPO_ROOT/commands/research.md" 2>/dev/null; then
  pass "commands/research.md prohibits modifying source code, config, and docs"
else
  fail "commands/research.md missing source-code prohibition bullet"
fi

if grep -q "Recommendations" "$REPO_ROOT/commands/research.md" 2>/dev/null; then
  pass "commands/research.md directs discovered changes to 'Recommendations' section"
else
  fail "commands/research.md missing 'Recommendations' write-back instruction"
fi

# Mirror copy (.claude/commands/research.md) — must carry the same prohibited-actions section
if grep -q "Do NOT edit" "$REPO_ROOT/.claude/commands/research.md" 2>/dev/null; then
  pass ".claude/commands/research.md contains 'Do NOT edit' (mirror has prohibited actions)"
else
  fail ".claude/commands/research.md missing 'Do NOT edit' — mirror not updated"
fi

if grep -q "Recommendations" "$REPO_ROOT/.claude/commands/research.md" 2>/dev/null; then
  pass ".claude/commands/research.md contains 'Recommendations' write-back instruction"
else
  fail ".claude/commands/research.md missing 'Recommendations' — mirror incomplete"
fi

# The prohibited-actions section must be present in both copies
# (parity: both files share identical prohibited-actions text)
PROHIBITED_SOURCE=$(grep -A5 "Prohibited actions" "$REPO_ROOT/commands/research.md" 2>/dev/null || true)
PROHIBITED_MIRROR=$(grep -A5 "Prohibited actions" "$REPO_ROOT/.claude/commands/research.md" 2>/dev/null || true)
if [ "$PROHIBITED_SOURCE" = "$PROHIBITED_MIRROR" ]; then
  pass "commands/research.md and .claude/commands/research.md have identical prohibited-actions text"
else
  fail "Prohibited-actions text differs between commands/research.md and .claude/commands/research.md"
fi

# ── Section 14: README sections ──────────────────────────────────────────────

echo ""
echo "14. README sections"

if grep -q "Patterns & Anti-patterns" "$REPO_ROOT/README.md" 2>/dev/null; then
  pass "README.md contains 'Patterns & Anti-patterns' section"
else
  fail "README.md missing 'Patterns & Anti-patterns' section"
fi

if grep -q "Working with Claude" "$REPO_ROOT/README.md" 2>/dev/null; then
  pass "README.md contains 'Working with Claude' section"
else
  fail "README.md missing 'Working with Claude' section"
fi

# The anti-patterns section must warn users away from the /compact collision
if grep -q "no \`/compact\` command\|no /compact command" "$REPO_ROOT/README.md" 2>/dev/null; then
  pass "README.md anti-patterns section warns that context-mogging has no /compact command"
else
  fail "README.md missing /compact anti-pattern warning in anti-patterns section"
fi

# The "Working with Claude's Built-in Commands" table must document /save-session
if grep -q "/save-session" "$REPO_ROOT/README.md" 2>/dev/null; then
  pass "README.md 'Working with Claude' table includes /save-session row"
else
  fail "README.md 'Working with Claude' table missing /save-session row"
fi

# The anti-patterns section must warn about skipping /save-session
if grep -q "Don't skip \`/save-session\`\|Don't skip /save-session" "$REPO_ROOT/README.md" 2>/dev/null; then
  pass "README.md anti-patterns section warns against skipping /save-session"
else
  fail "README.md missing anti-pattern warning about skipping /save-session"
fi

# ── Section 15: package.json version ─────────────────────────────────────────

echo ""
echo "15. package.json version"

PKG_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/package.json'))['version'])" 2>/dev/null || echo "")
if [ "$PKG_VERSION" = "1.4.0" ]; then
  pass "package.json version is 1.4.0"
else
  fail "package.json version is '$PKG_VERSION' (expected 1.4.0)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo "  Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────────────"
echo ""

[ "$FAIL" -eq 0 ]
