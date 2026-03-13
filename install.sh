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

DEPRECATED_FILES=(
  "commands/compact.md"
  "commands/plan.md"
)

clean_deprecated() {
  for rel in "${DEPRECATED_FILES[@]}"; do
    local full="${CLAUDE_DIR}/${rel}"
    if [[ -f "$full" ]]; then
      if rm "$full" 2>/dev/null; then
        success "Removed deprecated: ${rel}"
      else
        warn "Could not remove deprecated: ${rel} (skipping)"
      fi
    fi
  done
}

# ── Detection ────────────────────────────────────────────────────────────────
# Bash 3 compatible: individual variables, not associative arrays.

DETECT_PROJECT_NAME=""
DETECT_SHORT_DESCRIPTION=""
DETECT_REPO_URL=""
DETECT_INSTALL_CMD=""
DETECT_DEV_CMD=""
DETECT_TEST_CMD=""
DETECT_LINT_CMD=""
DETECT_BUILD_CMD=""
DETECT_ARCHITECTURE=""
DETECT_STACK=""
DETECT_LANGUAGE_CONVENTIONS=""
DETECT_FILE_STRUCTURE=""
DETECT_TEST_CONVENTIONS=""
DETECT_DATE=""

DETECT_DATE="$(date +%Y-%m-%d)"

detect_project() {
  # --- package.json (Node/JS/TS) ---
  if [[ -f "${TARGET_DIR}/package.json" ]]; then
    # name (strip quotes)
    local name
    name=$(grep '"name"' "${TARGET_DIR}/package.json" 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    [[ -n "$name" ]] && DETECT_PROJECT_NAME="$name"

    # description
    local desc
    desc=$(grep '"description"' "${TARGET_DIR}/package.json" 2>/dev/null | head -1 | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    [[ -n "$desc" ]] && DETECT_SHORT_DESCRIPTION="$desc"

    # Package manager from lockfile
    local pm="npm"
    [[ -f "${TARGET_DIR}/bun.lockb" || -f "${TARGET_DIR}/bun.lock" ]] && pm="bun"
    [[ -f "${TARGET_DIR}/pnpm-lock.yaml" ]] && pm="pnpm"
    [[ -f "${TARGET_DIR}/yarn.lock" ]] && pm="yarn"
    DETECT_INSTALL_CMD="${pm} install"

    # Scripts
    local dev_script
    for s in dev start serve preview; do
      dev_script=$(grep "\"${s}\"" "${TARGET_DIR}/package.json" 2>/dev/null | head -1 || true)
      if [[ -n "$dev_script" ]]; then DETECT_DEV_CMD="${pm} run ${s}"; break; fi
    done
    for s in test "test:run" vitest jest; do
      local ts
      ts=$(grep "\"${s}\"" "${TARGET_DIR}/package.json" 2>/dev/null | head -1 || true)
      if [[ -n "$ts" ]]; then DETECT_TEST_CMD="${pm} run ${s}"; break; fi
    done
    for s in lint "lint:check" eslint; do
      local ls
      ls=$(grep "\"${s}\"" "${TARGET_DIR}/package.json" 2>/dev/null | head -1 || true)
      if [[ -n "$ls" ]]; then DETECT_LINT_CMD="${pm} run ${s}"; break; fi
    done
    for s in build compile bundle; do
      local bs
      bs=$(grep "\"${s}\"" "${TARGET_DIR}/package.json" 2>/dev/null | head -1 || true)
      if [[ -n "$bs" ]]; then DETECT_BUILD_CMD="${pm} run ${s}"; break; fi
    done
  fi

  # --- Cargo.toml (Rust) ---
  if [[ -f "${TARGET_DIR}/Cargo.toml" && -z "$DETECT_PROJECT_NAME" ]]; then
    local cname
    cname=$(grep '^name' "${TARGET_DIR}/Cargo.toml" 2>/dev/null | head -1 | sed 's/name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/')
    [[ -n "$cname" ]] && DETECT_PROJECT_NAME="$cname"
    DETECT_INSTALL_CMD="cargo build"
    DETECT_DEV_CMD="cargo run"
    DETECT_TEST_CMD="cargo test"
    DETECT_LINT_CMD="cargo clippy"
    DETECT_BUILD_CMD="cargo build --release"
  fi

  # --- go.mod (Go) ---
  if [[ -f "${TARGET_DIR}/go.mod" && -z "$DETECT_PROJECT_NAME" ]]; then
    local gomod
    gomod=$(head -1 "${TARGET_DIR}/go.mod" 2>/dev/null | sed 's/^module //')
    [[ -n "$gomod" ]] && DETECT_PROJECT_NAME="${gomod##*/}"
    DETECT_INSTALL_CMD="go mod download"
    DETECT_DEV_CMD="go run ."
    DETECT_TEST_CMD="go test ./..."
    DETECT_LINT_CMD="go vet ./..."
    DETECT_BUILD_CMD="go build ./..."
  fi

  # --- pyproject.toml (Python) ---
  if [[ -f "${TARGET_DIR}/pyproject.toml" && -z "$DETECT_PROJECT_NAME" ]]; then
    # Read name from [project] section
    local in_project=0 pyname="" pydesc=""
    while IFS= read -r line; do
      [[ "$line" =~ ^\[project\] ]] && in_project=1 && continue
      [[ "$line" =~ ^\[ && "$in_project" -eq 1 ]] && break
      if [[ "$in_project" -eq 1 ]]; then
        if [[ -z "$pyname" && "$line" =~ ^name ]]; then
          pyname=$(echo "$line" | sed 's/name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if [[ -z "$pydesc" && "$line" =~ ^description ]]; then
          pydesc=$(echo "$line" | sed 's/description[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/')
        fi
      fi
    done < "${TARGET_DIR}/pyproject.toml"
    [[ -n "$pyname" ]] && DETECT_PROJECT_NAME="$pyname"
    [[ -n "$pydesc" ]] && DETECT_SHORT_DESCRIPTION="$pydesc"
    DETECT_INSTALL_CMD="pip install -e ."
    [[ -f "${TARGET_DIR}/poetry.lock" ]] && DETECT_INSTALL_CMD="poetry install"
    DETECT_TEST_CMD="pytest"
    DETECT_LINT_CMD="ruff check ."
    DETECT_BUILD_CMD="python -m build"
  fi

  # --- Directory name fallback ---
  [[ -z "$DETECT_PROJECT_NAME" ]] && DETECT_PROJECT_NAME="$(basename "$TARGET_DIR")"

  # --- Git remote for REPO_URL ---
  if [[ -z "$DETECT_REPO_URL" ]] && command -v git &>/dev/null; then
    local raw_url
    raw_url=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)
    if [[ -n "$raw_url" ]]; then
      # Normalize SSH to HTTPS
      if [[ "$raw_url" =~ ^git@ ]]; then
        raw_url=$(echo "$raw_url" | sed 's|^git@\([^:]*\):\(.*\)\.git$|https://\1/\2|' | sed 's|^git@\([^:]*\):\(.*\)$|https://\1/\2|')
      else
        raw_url="${raw_url%.git}"
      fi
      DETECT_REPO_URL="$raw_url"
    fi
  fi

  # --- Framework detection ---
  local arch_parts="" lang_parts=""

  # Next.js
  if [[ -f "${TARGET_DIR}/next.config.js" || -f "${TARGET_DIR}/next.config.ts" || -f "${TARGET_DIR}/next.config.mjs" ]]; then
    arch_parts="${arch_parts}Next.js + "
    lang_parts="${lang_parts}Next.js App Router conventions, "
  fi

  # TypeScript
  if [[ -f "${TARGET_DIR}/tsconfig.json" ]]; then
    arch_parts="${arch_parts}TypeScript + "
    lang_parts="${lang_parts}TypeScript strict mode, "
  fi

  # ESLint + Prettier
  local has_eslint=false has_prettier=false
  [[ -f "${TARGET_DIR}/.eslintrc.json" || -f "${TARGET_DIR}/.eslintrc.js" || -f "${TARGET_DIR}/eslint.config.js" || -f "${TARGET_DIR}/eslint.config.mjs" ]] && has_eslint=true
  [[ -f "${TARGET_DIR}/.prettierrc" || -f "${TARGET_DIR}/.prettierrc.json" || -f "${TARGET_DIR}/prettier.config.js" ]] && has_prettier=true
  if $has_eslint && $has_prettier; then
    lang_parts="${lang_parts}ESLint + Prettier, "
  elif $has_eslint; then
    lang_parts="${lang_parts}ESLint, "
  fi

  # Prisma
  if [[ -f "${TARGET_DIR}/prisma/schema.prisma" ]]; then
    arch_parts="${arch_parts}PostgreSQL (Prisma) + "
  fi

  # Tailwind
  if [[ -f "${TARGET_DIR}/tailwind.config.js" || -f "${TARGET_DIR}/tailwind.config.ts" ]]; then
    arch_parts="${arch_parts}Tailwind CSS + "
  fi

  # Trim trailing " + " or ", "
  arch_parts="${arch_parts% + }"
  lang_parts="${lang_parts%, }"
  [[ -n "$arch_parts" ]] && DETECT_ARCHITECTURE="$arch_parts"
  [[ -n "$lang_parts" ]] && DETECT_LANGUAGE_CONVENTIONS="$lang_parts"
  [[ -n "$arch_parts" ]] && DETECT_STACK="$arch_parts"

  # File structure
  if [[ -d "${TARGET_DIR}/src/app" ]]; then
    DETECT_FILE_STRUCTURE="Next.js App Router under src/app/"
  elif [[ -d "${TARGET_DIR}/src/pages" ]]; then
    DETECT_FILE_STRUCTURE="Pages Router under src/pages/"
  elif [[ -d "${TARGET_DIR}/src/features" ]]; then
    DETECT_FILE_STRUCTURE="Feature-based folders under src/features/"
  elif [[ -d "${TARGET_DIR}/src" ]]; then
    DETECT_FILE_STRUCTURE="Source files under src/"
  elif [[ -d "${TARGET_DIR}/app" ]]; then
    DETECT_FILE_STRUCTURE="Application code under app/"
  fi

  # Test conventions
  if [[ -f "${TARGET_DIR}/vitest.config.ts" || -f "${TARGET_DIR}/vitest.config.js" ]]; then
    DETECT_TEST_CONVENTIONS="Vitest — colocated .test.ts files"
  elif [[ -f "${TARGET_DIR}/jest.config.js" || -f "${TARGET_DIR}/jest.config.ts" ]]; then
    DETECT_TEST_CONVENTIONS="Jest — colocated .test.ts files"
  elif [[ -f "${TARGET_DIR}/playwright.config.ts" ]]; then
    DETECT_TEST_CONVENTIONS="Playwright — e2e tests in tests/"
  fi
}

# ── Template application ─────────────────────────────────────────────────────

# apply_template: reads template, substitutes {{TOKEN}} with detected values,
# replaces remaining {{TOKEN}} with TODO: fallbacks.
# Uses | as sed delimiter to handle URLs safely.
apply_template() {
  local template_file="$1"
  local output_file="$2"
  local content
  content="$(cat "$template_file")"

  # Helper: sed-replace all occurrences of a token in $content
  sub() {
    local token="$1" value="$2"
    # Escape & for sed replacement
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\\]/\\&/g')
    content=$(printf '%s\n' "$content" | sed "s|{{${token}}}|${escaped_value}|g")
  }

  [[ -n "$DETECT_PROJECT_NAME" ]]        && sub "PROJECT_NAME"        "$DETECT_PROJECT_NAME"
  [[ -n "$DETECT_SHORT_DESCRIPTION" ]]   && sub "SHORT_DESCRIPTION"   "$DETECT_SHORT_DESCRIPTION"
  [[ -n "$DETECT_ARCHITECTURE" ]]        && sub "ARCHITECTURE"        "$DETECT_ARCHITECTURE"
  [[ -n "$DETECT_REPO_URL" ]]            && sub "REPO_URL"            "$DETECT_REPO_URL"
  [[ -n "$DETECT_INSTALL_CMD" ]]         && sub "INSTALL_CMD"         "$DETECT_INSTALL_CMD"
  [[ -n "$DETECT_DEV_CMD" ]]             && sub "DEV_CMD"             "$DETECT_DEV_CMD"
  [[ -n "$DETECT_TEST_CMD" ]]            && sub "TEST_CMD"            "$DETECT_TEST_CMD"
  [[ -n "$DETECT_LINT_CMD" ]]            && sub "LINT_CMD"            "$DETECT_LINT_CMD"
  [[ -n "$DETECT_BUILD_CMD" ]]           && sub "BUILD_CMD"           "$DETECT_BUILD_CMD"
  [[ -n "$DETECT_LANGUAGE_CONVENTIONS" ]] && sub "LANGUAGE_CONVENTIONS" "$DETECT_LANGUAGE_CONVENTIONS"
  [[ -n "$DETECT_FILE_STRUCTURE" ]]      && sub "FILE_STRUCTURE"      "$DETECT_FILE_STRUCTURE"
  [[ -n "$DETECT_TEST_CONVENTIONS" ]]    && sub "TEST_CONVENTIONS"    "$DETECT_TEST_CONVENTIONS"
  [[ -n "$DETECT_STACK" ]]               && sub "STACK"               "$DETECT_STACK"
  sub "DATE" "$DETECT_DATE"

  # Replace remaining {{TOKEN}} with TODO: fallbacks
  content=$(printf '%s\n' "$content" | sed 's|{{PROJECT_NAME}}|TODO: project name|g')
  content=$(printf '%s\n' "$content" | sed 's|{{SHORT_DESCRIPTION}}|TODO: one-line project description|g')
  content=$(printf '%s\n' "$content" | sed 's|{{ARCHITECTURE}}|TODO: describe your architecture|g')
  content=$(printf '%s\n' "$content" | sed 's|{{REPO_URL}}|TODO: repository URL|g')
  content=$(printf '%s\n' "$content" | sed 's|{{INSTALL_CMD}}|TODO: install command|g')
  content=$(printf '%s\n' "$content" | sed 's|{{DEV_CMD}}|TODO: dev server command|g')
  content=$(printf '%s\n' "$content" | sed 's|{{TEST_CMD}}|TODO: test command|g')
  content=$(printf '%s\n' "$content" | sed 's|{{LINT_CMD}}|TODO: lint command|g')
  content=$(printf '%s\n' "$content" | sed 's|{{BUILD_CMD}}|TODO: build command|g')
  content=$(printf '%s\n' "$content" | sed 's|{{LANGUAGE_CONVENTIONS}}|TODO: language and framework conventions|g')
  content=$(printf '%s\n' "$content" | sed 's|{{NAMING_CONVENTIONS}}|TODO: naming conventions|g')
  content=$(printf '%s\n' "$content" | sed 's|{{FILE_STRUCTURE}}|TODO: file structure conventions|g')
  content=$(printf '%s\n' "$content" | sed 's|{{TEST_CONVENTIONS}}|TODO: testing conventions|g')
  content=$(printf '%s\n' "$content" | sed 's|{{PROTECTED_FILES}}|TODO: add project-specific protected files|g')
  content=$(printf '%s\n' "$content" | sed 's|{{ARCHITECTURE_BOUNDARIES}}|- TODO: define architecture boundaries|g')
  content=$(printf '%s\n' "$content" | sed 's|{{ERROR_TYPES}}|TODO: project error types|g')
  content=$(printf '%s\n' "$content" | sed 's|{{STACK}}|TODO: tech stack|g')

  printf '%s\n' "$content" > "$output_file"
}

write_template_if_missing() {
  local template_file="$1" dest="$2"
  if [[ -f "$dest" && "$FORCE" != "true" ]]; then
    warn "Skipped (exists): ${dest#$TARGET_DIR/}"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  apply_template "$template_file" "$dest"
  success "${dest#$TARGET_DIR/}"
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

# Detect project properties
echo "Detecting project properties..."
detect_project
log "Project: ${DETECT_PROJECT_NAME}"

# 1. Copy commands, agents, skills → .claude/
echo ""
echo "Copying commands, agents, and skills..."
for dir in commands agents skills; do
  copy_dir_recursive "${SCRIPT_DIR}/${dir}" "${CLAUDE_DIR}/${dir}"
done


echo ""
echo "Cleaning up deprecated files..."
clean_deprecated

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
          {
            ($key): (
              (($eh[$key] // []) | map(select(.hooks != null and (.hooks | length) > 0)))
              + ($ih[$key] // [])
              | unique_by(.hooks[0].command)
            )
          }
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

# 3. Write CLAUDE.md templates with substitution
echo ""
echo "Setting up governance templates..."
write_template_if_missing "${SCRIPT_DIR}/templates/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"
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
write_template_if_missing "${SCRIPT_DIR}/templates/memory-core.md" "${TARGET_DIR}/memory/core.md"
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
    1. Review CLAUDE.md — search for TODO: to finish setup
    2. Open Claude Code in this project
    3. Run /research to explore your codebase
    4. Run /draft-plan to create an implementation plan
    5. Run /implement to execute the plan

  Pipeline: /research → /draft-plan → /implement → /checkpoint

  Docs: https://github.com/Mercurium-Group/context-mogging

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QUICKSTART
