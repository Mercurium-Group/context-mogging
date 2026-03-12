'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ── Helpers ──────────────────────────────────────────────────────────────────

function readFile(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

function readJSON(filePath) {
  const raw = readFile(filePath);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/** Minimal line-by-line TOML section parser — extracts key = "value" pairs from a named section. */
function parseTomlSection(content, sectionName) {
  const result = {};
  let inSection = false;
  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (line.startsWith('[')) {
      inSection = line === `[${sectionName}]`;
      continue;
    }
    if (!inSection) continue;
    const match = line.match(/^(\w+)\s*=\s*"([^"]*)"$/);
    if (match) result[match[1]] = match[2];
  }
  return result;
}

function exec(cmd, cwd) {
  try {
    return execSync(cmd, { cwd, stdio: ['pipe', 'pipe', 'pipe'] }).toString().trim();
  } catch {
    return null;
  }
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function truncate(str, max) {
  if (!str) return str;
  return str.length > max ? str.slice(0, max - 1) + '…' : str;
}

/** Normalize git SSH URL or npm-style git+https URL to plain HTTPS. */
function normalizeGitUrl(url) {
  if (!url) return null;
  // Strip npm git+ prefix: git+https://... → https://...
  url = url.replace(/^git\+/, '');
  // git@github.com:user/repo.git → https://github.com/user/repo
  const sshMatch = url.match(/^git@([^:]+):(.+?)(?:\.git)?$/);
  if (sshMatch) return `https://${sshMatch[1]}/${sshMatch[2]}`;
  // Strip trailing .git
  return url.replace(/\.git$/, '');
}

// ── Detection sources ────────────────────────────────────────────────────────

function detectFromPackageJson(targetDir) {
  const pkg = readJSON(path.join(targetDir, 'package.json'));
  if (!pkg) return {};

  const result = {};

  if (pkg.name) result.PROJECT_NAME = pkg.name;
  if (pkg.description) result.SHORT_DESCRIPTION = truncate(pkg.description, 100);

  // Repo URL from package.json
  if (pkg.repository) {
    const repoUrl = typeof pkg.repository === 'string'
      ? pkg.repository
      : pkg.repository.url || null;
    if (repoUrl) result.REPO_URL = normalizeGitUrl(repoUrl);
  }

  // Package manager from lockfile
  let pkgManager = 'npm';
  if (exists(path.join(targetDir, 'bun.lockb')) || exists(path.join(targetDir, 'bun.lock'))) {
    pkgManager = 'bun';
  } else if (exists(path.join(targetDir, 'pnpm-lock.yaml'))) {
    pkgManager = 'pnpm';
  } else if (exists(path.join(targetDir, 'yarn.lock'))) {
    pkgManager = 'yarn';
  }
  result.INSTALL_CMD = `${pkgManager} install`;

  const scripts = pkg.scripts || {};
  const scriptFor = (names) => {
    for (const name of names) {
      if (scripts[name]) return `${pkgManager} run ${name}`;
    }
    return null;
  };

  result.DEV_CMD = scriptFor(['dev', 'start', 'serve', 'preview']);
  result.TEST_CMD = scriptFor(['test', 'test:run', 'vitest', 'jest']);
  result.LINT_CMD = scriptFor(['lint', 'lint:check', 'eslint']);
  result.BUILD_CMD = scriptFor(['build', 'compile', 'bundle']);

  return result;
}

function detectFromPyproject(targetDir) {
  const raw = readFile(path.join(targetDir, 'pyproject.toml'));
  if (!raw) return {};

  const project = parseTomlSection(raw, 'project');
  const result = {};

  if (project.name) result.PROJECT_NAME = project.name;
  if (project.description) result.SHORT_DESCRIPTION = truncate(project.description, 100);

  result.INSTALL_CMD = exists(path.join(targetDir, 'poetry.lock'))
    ? 'poetry install'
    : 'pip install -e .';
  result.TEST_CMD = 'pytest';
  result.LINT_CMD = 'ruff check .';
  result.BUILD_CMD = 'python -m build';

  return result;
}

function detectFromCargo(targetDir) {
  const raw = readFile(path.join(targetDir, 'Cargo.toml'));
  if (!raw) return {};

  const pkg = parseTomlSection(raw, 'package');
  const result = {};

  if (pkg.name) result.PROJECT_NAME = pkg.name;
  if (pkg.description) result.SHORT_DESCRIPTION = truncate(pkg.description, 100);

  result.INSTALL_CMD = 'cargo build';
  result.DEV_CMD = 'cargo run';
  result.TEST_CMD = 'cargo test';
  result.LINT_CMD = 'cargo clippy';
  result.BUILD_CMD = 'cargo build --release';

  return result;
}

function detectFromGoMod(targetDir) {
  const raw = readFile(path.join(targetDir, 'go.mod'));
  if (!raw) return {};

  const moduleLine = raw.split('\n').find(l => l.startsWith('module '));
  const result = {};

  if (moduleLine) {
    const modulePath = moduleLine.replace('module ', '').trim();
    result.PROJECT_NAME = path.basename(modulePath);
  }

  result.INSTALL_CMD = 'go mod download';
  result.DEV_CMD = 'go run .';
  result.TEST_CMD = 'go test ./...';
  result.LINT_CMD = 'go vet ./...';
  result.BUILD_CMD = 'go build ./...';

  return result;
}

function detectFromGit(targetDir) {
  const url = exec('git remote get-url origin', targetDir);
  if (!url) return {};
  return { REPO_URL: normalizeGitUrl(url) };
}

/** Detect frameworks and tools from config file presence. Returns list of found labels. */
function detectFrameworks(targetDir) {
  const fw = [];
  const tools = [];
  const testFw = [];
  const ormFw = [];
  const infraFw = [];

  // Frontend frameworks
  if (exists(path.join(targetDir, 'next.config.js')) ||
      exists(path.join(targetDir, 'next.config.ts')) ||
      exists(path.join(targetDir, 'next.config.mjs'))) fw.push('Next.js');
  else if (exists(path.join(targetDir, 'nuxt.config.ts')) ||
           exists(path.join(targetDir, 'nuxt.config.js'))) fw.push('Nuxt');
  else if (exists(path.join(targetDir, 'vite.config.ts')) ||
           exists(path.join(targetDir, 'vite.config.js'))) fw.push('Vite');
  else if (exists(path.join(targetDir, 'svelte.config.js')) ||
           exists(path.join(targetDir, 'svelte.config.ts'))) fw.push('SvelteKit');
  else if (exists(path.join(targetDir, 'astro.config.mjs')) ||
           exists(path.join(targetDir, 'astro.config.ts'))) fw.push('Astro');

  // Backend frameworks (check package.json dependencies)
  const pkg = readJSON(path.join(targetDir, 'package.json'));
  const deps = Object.assign({}, pkg && pkg.dependencies, pkg && pkg.devDependencies);
  if (deps['fastapi'] || exists(path.join(targetDir, 'manage.py'))) {
    fw.push(exists(path.join(targetDir, 'manage.py')) ? 'Django' : 'FastAPI');
  }
  if (deps['express']) fw.push('Express');
  if (deps['hono']) fw.push('Hono');
  if (deps['fastify']) fw.push('Fastify');

  // Language / type tools
  if (exists(path.join(targetDir, 'tsconfig.json'))) tools.push('TypeScript');

  // CSS
  if (exists(path.join(targetDir, 'tailwind.config.js')) ||
      exists(path.join(targetDir, 'tailwind.config.ts'))) tools.push('Tailwind CSS');

  // Linters / formatters
  const hasEslint = exists(path.join(targetDir, '.eslintrc.json')) ||
    exists(path.join(targetDir, '.eslintrc.js')) ||
    exists(path.join(targetDir, '.eslintrc.yaml')) ||
    exists(path.join(targetDir, 'eslint.config.js')) ||
    exists(path.join(targetDir, 'eslint.config.mjs')) ||
    (pkg && (deps['eslint'] !== undefined));
  if (hasEslint) tools.push('ESLint');

  const hasPrettier = exists(path.join(targetDir, '.prettierrc')) ||
    exists(path.join(targetDir, '.prettierrc.json')) ||
    exists(path.join(targetDir, 'prettier.config.js')) ||
    (pkg && deps['prettier'] !== undefined);
  if (hasPrettier) tools.push('Prettier');

  // Test frameworks
  if (exists(path.join(targetDir, 'vitest.config.ts')) ||
      exists(path.join(targetDir, 'vitest.config.js')) ||
      (pkg && deps['vitest'] !== undefined)) testFw.push('Vitest');
  else if (exists(path.join(targetDir, 'jest.config.js')) ||
           exists(path.join(targetDir, 'jest.config.ts')) ||
           (pkg && deps['jest'] !== undefined)) testFw.push('Jest');
  else if (exists(path.join(targetDir, 'playwright.config.ts')) ||
           (pkg && deps['@playwright/test'] !== undefined)) testFw.push('Playwright');

  // ORM / database
  if (exists(path.join(targetDir, 'prisma', 'schema.prisma'))) ormFw.push('PostgreSQL (Prisma)');
  else if (deps && deps['drizzle-orm']) ormFw.push('Drizzle ORM');

  // Infra
  if (exists(path.join(targetDir, 'docker-compose.yml')) ||
      exists(path.join(targetDir, 'docker-compose.yaml'))) {
    const compose = readFile(path.join(targetDir, 'docker-compose.yml')) ||
                    readFile(path.join(targetDir, 'docker-compose.yaml')) || '';
    if (compose.includes('postgres')) infraFw.push('PostgreSQL');
    if (compose.includes('redis')) infraFw.push('Redis');
    if (compose.includes('mysql')) infraFw.push('MySQL');
    if (compose.includes('mongodb')) infraFw.push('MongoDB');
  }

  return { fw, tools, testFw, ormFw, infraFw };
}

function deriveFields(targetDir, base, detected) {
  const { fw, tools, testFw, ormFw } = detectFrameworks(targetDir);

  const archParts = [...fw, ...tools.filter(t => t === 'TypeScript'), ...ormFw];
  if (archParts.length > 0 && !detected.ARCHITECTURE) {
    detected.ARCHITECTURE = archParts.join(' + ');
  }
  if (!detected.STACK) {
    detected.STACK = detected.ARCHITECTURE || detected.PROJECT_NAME || null;
  }

  // Language conventions
  if (!detected.LANGUAGE_CONVENTIONS) {
    const parts = [];
    if (tools.includes('TypeScript')) parts.push('TypeScript strict mode');
    if (tools.includes('ESLint') && tools.includes('Prettier')) parts.push('ESLint + Prettier');
    else if (tools.includes('ESLint')) parts.push('ESLint');
    else if (tools.includes('Prettier')) parts.push('Prettier');
    if (fw.includes('Next.js')) parts.push('Next.js App Router conventions');
    if (parts.length > 0) detected.LANGUAGE_CONVENTIONS = parts.join(', ');
  }

  // File structure
  if (!detected.FILE_STRUCTURE) {
    if (exists(path.join(targetDir, 'src', 'app'))) detected.FILE_STRUCTURE = 'Next.js App Router under src/app/';
    else if (exists(path.join(targetDir, 'src', 'pages'))) detected.FILE_STRUCTURE = 'Pages Router under src/pages/';
    else if (exists(path.join(targetDir, 'src', 'features'))) detected.FILE_STRUCTURE = 'Feature-based folders under src/features/';
    else if (exists(path.join(targetDir, 'src'))) detected.FILE_STRUCTURE = 'Source files under src/';
    else if (exists(path.join(targetDir, 'app'))) detected.FILE_STRUCTURE = 'Application code under app/';
  }

  // Test conventions
  if (!detected.TEST_CONVENTIONS && testFw.length > 0) {
    const tf = testFw[0];
    detected.TEST_CONVENTIONS = `${tf} — colocated .test.ts files`;
  }
}

// ── Main export ──────────────────────────────────────────────────────────────

/**
 * Detect project properties from the given directory.
 * Returns an object where keys are template tokens (e.g. PROJECT_NAME)
 * and values are detected strings or null.
 */
function detect(targetDir) {
  const detected = {};

  // Run detection sources in priority order, later values win
  const sources = [
    detectFromGoMod(targetDir),
    detectFromCargo(targetDir),
    detectFromPyproject(targetDir),
    detectFromPackageJson(targetDir),  // highest priority for JS/TS projects
  ];

  for (const source of sources) {
    for (const [key, val] of Object.entries(source)) {
      if (val !== null && val !== undefined) detected[key] = val;
    }
  }

  // Git remote as fallback for REPO_URL
  if (!detected.REPO_URL) {
    const gitResult = detectFromGit(targetDir);
    if (gitResult.REPO_URL) detected.REPO_URL = gitResult.REPO_URL;
  }

  // PROJECT_NAME fallback: directory name
  if (!detected.PROJECT_NAME) {
    detected.PROJECT_NAME = path.basename(targetDir);
  }

  // Derive composite fields
  deriveFields(targetDir, targetDir, detected);

  // Always set DATE
  detected.DATE = new Date().toISOString().split('T')[0];

  return detected;
}

module.exports = { detect };
