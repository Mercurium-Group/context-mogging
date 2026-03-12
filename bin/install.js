#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');

// ── Config ──────────────────────────────────────────────────────────────────

const MARKER_FILE = 'commands/research.md';

const COPY_DIRS = ['commands', 'agents', 'skills'];

const MEMORY_DIRS = [
  'memory',
  'memory/topics',
  'memory/sessions',
];

const THOUGHTS_DIRS = [
  'thoughts/shared/research',
  'thoughts/shared/plans',
  'thoughts/shared/logs',
];

// ── Helpers ─────────────────────────────────────────────────────────────────

function log(msg) { console.log(`  ${msg}`); }
function warn(msg) { console.log(`  ⚠ ${msg}`); }
function success(msg) { console.log(`  ✓ ${msg}`); }

function resolvePackageRoot() {
  // Works whether run from node_modules/.bin or directly
  return path.resolve(__dirname, '..');
}

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function copyFileIfMissing(src, dest, force) {
  if (fs.existsSync(dest) && !force) {
    warn(`Skipped (exists): ${path.relative(process.cwd(), dest)}`);
    return false;
  }
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
  success(path.relative(process.cwd(), dest));
  return true;
}

function copyDirRecursive(srcDir, destDir, force) {
  if (!fs.existsSync(srcDir)) return;
  ensureDir(destDir);
  const entries = fs.readdirSync(srcDir, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath, force);
    } else {
      copyFileIfMissing(srcPath, destPath, force);
    }
  }
}

function deepMergeSettings(existing, incoming) {
  const merged = JSON.parse(JSON.stringify(existing));

  // Merge hooks: combine arrays per hook type
  if (incoming.hooks) {
    if (!merged.hooks) merged.hooks = {};
    for (const [hookType, hookArray] of Object.entries(incoming.hooks)) {
      if (!merged.hooks[hookType]) {
        merged.hooks[hookType] = hookArray;
      } else {
        // Add hooks that don't already exist (match by description)
        const existingDescs = new Set(merged.hooks[hookType].map(h => h.description));
        for (const hook of hookArray) {
          if (!existingDescs.has(hook.description)) {
            merged.hooks[hookType].push(hook);
          }
        }
      }
    }
  }

  return merged;
}

function appendGitignoreLines(targetGitignore, additionsFile) {
  let existing = '';
  if (fs.existsSync(targetGitignore)) {
    existing = fs.readFileSync(targetGitignore, 'utf8');
  }
  const existingLines = new Set(existing.split('\n').map(l => l.trim()));
  const additions = fs.readFileSync(additionsFile, 'utf8')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !existingLines.has(l));

  if (additions.length > 0) {
    const separator = existing.endsWith('\n') || existing === '' ? '' : '\n';
    const block = `\n# context-mogging\n${additions.join('\n')}\n`;
    fs.appendFileSync(targetGitignore, separator + block);
    success('.gitignore updated');
  } else {
    warn('.gitignore already has all needed entries');
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command !== 'init') {
    console.log('\nUsage: npx context-mogging init [--dir <path>] [--force]\n');
    console.log('Options:');
    console.log('  --dir <path>  Target directory (default: current directory)');
    console.log('  --force       Overwrite existing files');
    process.exit(command === '--help' || command === '-h' ? 0 : 1);
  }

  const force = args.includes('--force');
  const dirIdx = args.indexOf('--dir');
  const targetDir = dirIdx !== -1 && args[dirIdx + 1]
    ? path.resolve(args[dirIdx + 1])
    : process.cwd();

  const pkgRoot = resolvePackageRoot();
  const claudeDir = path.join(targetDir, '.claude');

  console.log('\n🧠 context-mogging installer\n');

  // Check for existing install
  const markerPath = path.join(claudeDir, MARKER_FILE);
  if (fs.existsSync(markerPath) && !force) {
    console.log('  Existing installation detected.');
    console.log('  Run with --force to overwrite.\n');
    process.exit(0);
  }

  // 1. Copy commands, agents, skills → .claude/
  console.log('Copying commands, agents, and skills...');
  for (const dir of COPY_DIRS) {
    const src = path.join(pkgRoot, dir);
    const dest = path.join(claudeDir, dir);
    copyDirRecursive(src, dest, force);
  }

  // 2. Merge settings.json
  console.log('\nConfiguring hooks...');
  const settingsSrc = path.join(pkgRoot, 'templates', 'settings.json');
  const settingsDest = path.join(claudeDir, 'settings.json');
  if (fs.existsSync(settingsSrc)) {
    const incoming = JSON.parse(fs.readFileSync(settingsSrc, 'utf8'));
    let existing = {};
    if (fs.existsSync(settingsDest)) {
      existing = JSON.parse(fs.readFileSync(settingsDest, 'utf8'));
    }
    const merged = deepMergeSettings(existing, incoming);
    ensureDir(claudeDir);
    fs.writeFileSync(settingsDest, JSON.stringify(merged, null, 2) + '\n');
    success('.claude/settings.json (merged)');
  }

  // 3. Copy CLAUDE.md templates
  console.log('\nSetting up governance templates...');
  copyFileIfMissing(
    path.join(pkgRoot, 'templates', 'CLAUDE.md'),
    path.join(targetDir, 'CLAUDE.md'),
    false // never force-overwrite root CLAUDE.md
  );
  copyFileIfMissing(
    path.join(pkgRoot, 'templates', 'CLAUDE.local.md'),
    path.join(claudeDir, 'CLAUDE.md'),
    false
  );

  // 4. Create thoughts directories
  console.log('\nCreating thoughts directories...');
  for (const dir of THOUGHTS_DIRS) {
    const dirPath = path.join(targetDir, dir);
    ensureDir(dirPath);
    // Add .gitkeep so empty dirs are tracked
    const gitkeep = path.join(dirPath, '.gitkeep');
    if (!fs.existsSync(gitkeep)) {
      fs.writeFileSync(gitkeep, '');
    }
  }
  success('thoughts/shared/{research,plans,logs}/');

  // 5. Create memory structure
  console.log('\nCreating memory structure...');
  for (const dir of MEMORY_DIRS) {
    ensureDir(path.join(targetDir, dir));
  }
  copyFileIfMissing(
    path.join(pkgRoot, 'templates', 'memory-core.md'),
    path.join(targetDir, 'memory', 'core.md'),
    force
  );
  // Add .gitkeep to empty dirs
  for (const dir of ['memory/topics', 'memory/sessions']) {
    const gitkeep = path.join(targetDir, dir, '.gitkeep');
    if (!fs.existsSync(gitkeep)) {
      fs.writeFileSync(gitkeep, '');
    }
  }
  success('memory/{core.md,topics/,sessions/}');

  // 6. Update .gitignore
  console.log('\nUpdating .gitignore...');
  const additionsFile = path.join(pkgRoot, 'templates', 'gitignore-additions.txt');
  if (fs.existsSync(additionsFile)) {
    appendGitignoreLines(path.join(targetDir, '.gitignore'), additionsFile);
  }

  // 7. Print quickstart
  console.log(`
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
`);
}

main();
