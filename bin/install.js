#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { detect } = require('./detect');

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

const FALLBACKS = {
  PROJECT_NAME: 'TODO: project name',
  SHORT_DESCRIPTION: 'TODO: one-line project description',
  ARCHITECTURE: 'TODO: describe your architecture (e.g., Next.js + TypeScript + PostgreSQL)',
  REPO_URL: 'TODO: repository URL',
  INSTALL_CMD: 'TODO: install command',
  DEV_CMD: 'TODO: dev server command',
  TEST_CMD: 'TODO: test command',
  LINT_CMD: 'TODO: lint command',
  BUILD_CMD: 'TODO: build command',
  LANGUAGE_CONVENTIONS: 'TODO: language and framework conventions',
  NAMING_CONVENTIONS: 'TODO: naming conventions (e.g., camelCase for variables, PascalCase for components)',
  FILE_STRUCTURE: 'TODO: file structure conventions',
  TEST_CONVENTIONS: 'TODO: testing conventions',
  PROTECTED_FILES: 'TODO: add project-specific protected files',
  ARCHITECTURE_BOUNDARIES: '- TODO: define architecture boundaries',
  ERROR_TYPES: 'TODO: project error types (e.g., AppError, ValidationError)',
  STACK: 'TODO: tech stack',
  DATE: new Date().toISOString().split('T')[0],
};

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
        // Add hook entries that don't already exist (match by first command in hooks array)
        const existingCmds = new Set(
          merged.hooks[hookType].map(h =>
            (h.hooks && h.hooks[0] && h.hooks[0].command) || ''
          )
        );
        for (const hook of hookArray) {
          const cmd = (hook.hooks && hook.hooks[0] && hook.hooks[0].command) || '';
          if (!existingCmds.has(cmd)) {
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

/**
 * Read template file, replace {{TOKEN}} placeholders with detected values.
 * Any token not detected falls back to FALLBACKS, then to a generic TODO.
 */
function applyTemplate(templatePath, detected) {
  let content = fs.readFileSync(templatePath, 'utf8');
  const allValues = Object.assign({}, FALLBACKS, detected);

  for (const [key, value] of Object.entries(allValues)) {
    if (value !== null && value !== undefined) {
      // Use split+join to avoid RegExp issues with special chars in values
      content = content.split(`{{${key}}}`).join(String(value));
    }
  }

  // Catch any remaining unreplaced tokens and set generic fallback
  content = content.replace(/\{\{[A-Z_]+\}\}/g, (match) => {
    const key = match.slice(2, -2);
    return `TODO: ${key.toLowerCase().replace(/_/g, ' ')}`;
  });

  return content;
}

/**
 * Like copyFileIfMissing, but applies template substitution before writing.
 */
function writeTemplateIfMissing(templatePath, destPath, detected, force) {
  if (fs.existsSync(destPath) && !force) {
    warn(`Skipped (exists): ${path.relative(process.cwd(), destPath)}`);
    return false;
  }
  ensureDir(path.dirname(destPath));
  const content = applyTemplate(templatePath, detected);
  fs.writeFileSync(destPath, content);
  success(path.relative(process.cwd(), destPath));
  return true;
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

  // Detect repo properties
  console.log('Detecting project properties...');
  const detected = detect(targetDir);
  const templateKeys = Object.keys(FALLBACKS);
  const detectedCount = templateKeys.filter(k => detected[k] != null).length;
  const todoCount = templateKeys.length - detectedCount;
  log(`Auto-detected ${detectedCount}/${templateKeys.length} fields${todoCount > 0 ? ` — ${todoCount} will be TODO: markers` : ' — no manual setup needed'}`);

  // 1. Copy commands, agents, skills → .claude/
  console.log('\nCopying commands, agents, and skills...');
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

  // 3. Write CLAUDE.md templates with substitution
  console.log('\nSetting up governance templates...');
  writeTemplateIfMissing(
    path.join(pkgRoot, 'templates', 'CLAUDE.md'),
    path.join(targetDir, 'CLAUDE.md'),
    detected,
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
  writeTemplateIfMissing(
    path.join(pkgRoot, 'templates', 'memory-core.md'),
    path.join(targetDir, 'memory', 'core.md'),
    detected,
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
  const hasTodos = Object.values(detected).some(v => v === null || String(v).startsWith('TODO'));
  console.log(`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✅ context-mogging installed!

  Quick start:
    1. Review CLAUDE.md — search for TODO: to finish setup${hasTodos ? '\n       (a few fields need manual input)' : ''}
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
