#!/usr/bin/env bash
set -euo pipefail

# ── context-mogging bash installer ──────────────────────────────────────────
# Mirrors bin/install.js logic for systems without Node.js.
# Usage: bash install.sh [--dir <path>] [--force]

# ── Parse args ──────────────────────────────────────────────────────────────

TARGET_DIR="$(pwd)"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   TARGET_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --help|-h)
      echo "Usage: bash install.sh [--dir <path>] [--force]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Resolve source directory ────────────────────────────────────────────────
# BASH_SOURCE[0] is unbound when the script is piped via `curl | bash`.
# Temporarily disable -u to read it safely, then restore.
set +u
_self="${BASH_SOURCE[0]:-$0}"
set -u

SCRIPT_DIR=""
if [[ -n "$_self" && "$_self" != "bash" && "$_self" != "-bash" && -f "$_self" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
fi

# If sibling files are absent (curl | bash mode), download the archive from GitHub.
if [[ ! -f "${SCRIPT_DIR}/templates/CLAUDE.md" ]]; then
  echo "  Downloading context-mogging from GitHub..."
  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_tmpdir"' EXIT
  if ! curl -fsSL \
      "https://github.com/Mercurium-Group/context-mogging/archive/refs/heads/main.tar.gz" \
      | tar -xz -C "$_tmpdir" --strip-components=1; then
    echo ""
    echo "  ✗ Download failed. Install manually:"
    echo "    git clone https://github.com/Mercurium-Group/context-mogging.git"
    echo "    cd context-mogging && bash install.sh"
    exit 1
  fi
  SCRIPT_DIR="$_tmpdir"
fi

CLAUDE_DIR="${TARGET_DIR}/.claude"

# ── Helpers ─────────────────────────────────────────────────────────────────

log()     { echo "  $1"; }
warn()    { echo "  ⚠ $1"; }
success() { echo "  ✓ $1"; }

copy_if_missing() {
  local src="$1" dest="$2"
  if [[ -f "$dest" && "$FORCE" != "true" ]]; then
    warn "Skipped (exists): ${dest#$TARGET_DIR/}"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  success "${dest#$TARGET_DIR/}"
}

copy_dir_recursive() {
  local src_dir="$1" dest_dir="$2"
  [[ -d "$src_dir" ]] || return 0
  mkdir -p "$dest_dir"
  find "$src_dir" -type f | while read -r src_file; do
    local rel="${src_file#$src_dir/}"
    copy_if_missing "$src_file" "${dest_dir}/${rel}"
  done
}

# ── Main ────────────────────────────────────────────────────────────────────

echo ""
echo "🧠 context-mogging installer"
echo ""

# Check for existing install
MARKER="${CLAUDE_DIR}/commands/research.md"
if [[ -f "$MARKER" && "$FORCE" != "true" ]]; then
  echo "  Existing installation detected."
  echo "  Run with --force to overwrite."
  echo ""
  exit 0
fi

# 1. Copy commands, agents, skills → .claude/
echo "Copying commands, agents, and skills..."
for dir in commands agents skills; do
  copy_dir_recursive "${SCRIPT_DIR}/${dir}" "${CLAUDE_DIR}/${dir}"
done

# 2. Merge settings.json (simplified — concatenates hooks if jq available)
echo ""
echo "Configuring hooks..."
SETTINGS_SRC="${SCRIPT_DIR}/templates/settings.json"
SETTINGS_DEST="${CLAUDE_DIR}/settings.json"
if [[ -f "$SETTINGS_SRC" ]]; then
  mkdir -p "$CLAUDE_DIR"
  if [[ -f "$SETTINGS_DEST" ]] && command -v jq &>/dev/null; then
    # Deep merge with jq: combine hooks arrays
    jq -s '
      .[0] as $existing | .[1] as $incoming |
      $existing * $incoming |
      .hooks = (
        ($existing.hooks // {}) as $eh |
        ($incoming.hooks // {}) as $ih |
        ($eh | keys) + ($ih | keys) | unique | map(
          . as $key |
          { ($key): (($eh[$key] // []) + ($ih[$key] // []) | unique_by(.description)) }
        ) | add // {}
      )
    ' "$SETTINGS_DEST" "$SETTINGS_SRC" > "${SETTINGS_DEST}.tmp"
    mv "${SETTINGS_DEST}.tmp" "$SETTINGS_DEST"
    success ".claude/settings.json (merged)"
  elif [[ -f "$SETTINGS_DEST" ]]; then
    warn ".claude/settings.json exists — install jq for smart merge, or merge manually"
    warn "Template at: ${SETTINGS_SRC}"
  else
    cp "$SETTINGS_SRC" "$SETTINGS_DEST"
    success ".claude/settings.json"
  fi
fi

# 3. Copy CLAUDE.md templates
echo ""
echo "Setting up governance templates..."
copy_if_missing "${SCRIPT_DIR}/templates/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"
copy_if_missing "${SCRIPT_DIR}/templates/CLAUDE.local.md" "${CLAUDE_DIR}/CLAUDE.md"

# 4. Create thoughts directories
echo ""
echo "Creating thoughts directories..."
for dir in thoughts/shared/research thoughts/shared/plans thoughts/shared/logs; do
  mkdir -p "${TARGET_DIR}/${dir}"
  touch "${TARGET_DIR}/${dir}/.gitkeep"
done
success "thoughts/shared/{research,plans,logs}/"

# 5. Create memory structure
echo ""
echo "Creating memory structure..."
mkdir -p "${TARGET_DIR}/memory/topics" "${TARGET_DIR}/memory/sessions"
copy_if_missing "${SCRIPT_DIR}/templates/memory-core.md" "${TARGET_DIR}/memory/core.md"
touch "${TARGET_DIR}/memory/topics/.gitkeep" "${TARGET_DIR}/memory/sessions/.gitkeep"
success "memory/{core.md,topics/,sessions/}"

# 6. Update .gitignore
echo ""
echo "Updating .gitignore..."
GITIGNORE="${TARGET_DIR}/.gitignore"
ADDITIONS="${SCRIPT_DIR}/templates/gitignore-additions.txt"
if [[ -f "$ADDITIONS" ]]; then
  NEEDS_UPDATE=false
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -qxF "$line" "$GITIGNORE" 2>/dev/null; then
      NEEDS_UPDATE=true
      break
    fi
  done < "$ADDITIONS"

  if [[ "$NEEDS_UPDATE" == "true" ]]; then
    echo "" >> "$GITIGNORE"
    echo "# context-mogging" >> "$GITIGNORE"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      grep -qxF "$line" "$GITIGNORE" 2>/dev/null || echo "$line" >> "$GITIGNORE"
    done < "$ADDITIONS"
    success ".gitignore updated"
  else
    warn ".gitignore already has all needed entries"
  fi
fi

# 7. Print quickstart
cat << 'QUICKSTART'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✅ context-mogging installed!

  Quick start:
    1. Edit CLAUDE.md — fill in [PROJECT_NAME] and other placeholders
    2. Open Claude Code in this project
    3. Run /research to explore your codebase
    4. Run /plan to create an implementation plan
    5. Run /implement to execute the plan

  Pipeline: /research → /plan → /implement → /checkpoint

  Docs: https://github.com/Mercurium-Group/context-mogging

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QUICKSTART
