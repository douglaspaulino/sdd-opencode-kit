#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const os = require('os');

const HOME_DIR = os.homedir();
const GLOBAL_TARGET = path.join(HOME_DIR, '.config', 'opencode');
const SCRIPT_DIR = __dirname;
const TEMPLATE_DIR = path.join(SCRIPT_DIR, '..', 'template');

const SDD_AGENTS_CONFIG = {
  'sdd-implementer':   { hidden: true },
  'sdd-code-reviewer': { hidden: true },
  'sdd-task-reviewer': { hidden: true },
  'sdd-fixer':         { hidden: true },
  'sdd-verifier':      { hidden: true },
  'sdd-debugger':      { hidden: true },
  'sdd-quickfix':      { hidden: true }
};

function showUsage() {
  console.log(`
Usage: sdd-install [options] [target]

Options:
  --global, -g     Install globally into ~/.config/opencode/
  --track-state    Version the .sdd/runs/ state (skip adding to .gitignore)
  --help, -h       Show this help message

Examples:
  sdd-install --global          Install for all projects
  sdd-install /path/to/repo     Install into a specific repository
  sdd-install /path/to/repo --track-state
  sdd-install                   Interactive mode
`);
}

function findTemplateDir() {
  const candidates = [
    TEMPLATE_DIR,
    path.join(SCRIPT_DIR, '..', 'template'),
    path.join(process.cwd(), 'template'),
  ];

  for (const dir of candidates) {
    if (fs.existsSync(path.join(dir, '.opencode'))) {
      return path.join(dir, '.opencode');
    }
  }

  console.error('Error: template/.opencode/ directory not found.');
  console.error('Make sure the package is correctly installed.');
  process.exit(1);
}

function copyFiles(srcDir, dstDir) {
  let copied = 0;
  let updated = 0;

  function walk(currentSrc, currentDst) {
    const entries = fs.readdirSync(currentSrc, { withFileTypes: true });

    for (const entry of entries) {
      const srcPath = path.join(currentSrc, entry.name);
      const dstPath = path.join(currentDst, entry.name);

      if (entry.isDirectory()) {
        if (!fs.existsSync(dstPath)) {
          fs.mkdirSync(dstPath, { recursive: true });
        }
        walk(srcPath, dstPath);
      } else if (entry.isFile()) {
        const parentDir = path.dirname(dstPath);
        if (!fs.existsSync(parentDir)) {
          fs.mkdirSync(parentDir, { recursive: true });
        }

        const exists = fs.existsSync(dstPath);
        fs.copyFileSync(srcPath, dstPath);

        if (exists) {
          console.log(`  UPDATE: ${path.relative(TEMPLATE_DIR, srcPath)}`);
          updated++;
        } else {
          console.log(`  COPY:   ${path.relative(TEMPLATE_DIR, srcPath)}`);
          copied++;
        }
      }
    }
  }

  walk(srcDir, dstDir);
  return { copied, updated };
}

function addToGitignore(repoDir) {
  const gitignorePath = path.join(repoDir, '.gitignore');
  const entry = '.sdd/runs/';

  try {
    const content = fs.readFileSync(gitignorePath, 'utf-8');
    const lines = content.split('\n').map(l => l.trim());

    if (lines.includes(entry)) {
      console.log('==> .sdd/runs/ already in .gitignore');
      return;
    }
  } catch {
  }

  fs.appendFileSync(gitignorePath, entry + '\n');
  console.log('==> Added .sdd/runs/ to .gitignore');
}

function mergeOpencodeConfig(targetDir) {
  const jsonPath = path.join(targetDir, 'opencode.json');
  const jsoncPath = path.join(targetDir, 'opencode.jsonc');
  
  let configPath = null;
  let isJsonc = false;
  
  if (fs.existsSync(jsonPath)) {
    configPath = jsonPath;
  } else if (fs.existsSync(jsoncPath)) {
    configPath = jsoncPath;
    isJsonc = true;
  }
  
  let config = {};
  
  if (configPath) {
    try {
      let content = fs.readFileSync(configPath, 'utf-8');
      // Strip line comments (// ...) but not inside strings
      // Simple approach: only strip // that are not inside quoted strings
      content = content.replace(/(^|[^:"\w])\/\/.*$/gm, '$1').replace(/\/\*[\s\S]*?\*\//g, '');
      config = JSON.parse(content);
    } catch (err) {
      console.error(`Warning: Could not parse ${configPath}: ${err.message}`);
      console.log('==> Skipping opencode.json merge');
      return;
    }
  } else {
    configPath = jsonPath;
  }
  
  // Ensure agent object exists
  if (!config.agent) {
    config.agent = {};
  }
  
  // Merge SDD agents config
  for (const [agentName, agentConfig] of Object.entries(SDD_AGENTS_CONFIG)) {
    if (!config.agent[agentName]) {
      config.agent[agentName] = {};
    }
    config.agent[agentName].hidden = agentConfig.hidden;
  }
  
  // Add schema if not present
  if (!config.$schema) {
    config.$schema = 'https://opencode.ai/config.json';
  }
  
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
  console.log(`==> Updated ${path.relative(targetDir, configPath)} with SDD agents hidden config`);
}

function installGlobal() {
  console.log('==> Installing SDD kit globally...\n');

  if (!fs.existsSync(GLOBAL_TARGET)) {
    fs.mkdirSync(GLOBAL_TARGET, { recursive: true });
  }

  const srcDir = findTemplateDir();
  const { copied, updated } = copyFiles(srcDir, GLOBAL_TARGET);

  console.log(`\n==> ${copied} new, ${updated} updated`);
  
  mergeOpencodeConfig(GLOBAL_TARGET);
  
  console.log('==> Installed to ' + GLOBAL_TARGET);
  console.log('    Restart opencode to use /sdd in any repository.');
}

function installLocal(repoDir, trackState) {
  const targetDir = path.resolve(repoDir);

  if (!fs.existsSync(targetDir)) {
    console.error(`Error: target directory does not exist: ${targetDir}`);
    process.exit(1);
  }

  console.log(`==> Installing SDD kit into ${targetDir}\n`);

  const srcDir = findTemplateDir();
  const dstDir = path.join(targetDir, '.opencode');
  const { copied, updated } = copyFiles(srcDir, dstDir);

  console.log(`\n==> ${copied} new, ${updated} updated`);

  mergeOpencodeConfig(targetDir);

  if (trackState) {
    console.log('==> --track-state: .sdd/runs/ will NOT be added to .gitignore');
  } else {
    addToGitignore(targetDir);
  }

  console.log('\nDone. Restart opencode in ' + targetDir + ' and use /sdd <path>.');
}

function interactiveMode() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log('SDD Opencode Kit - Installer\n');

  rl.question('Install globally (for all projects)? [Y/n]: ', (answer) => {
    const global = answer.trim().toLowerCase() !== 'n';

    if (global) {
      rl.close();
      installGlobal();
    } else {
      rl.question('Enter target repository path: ', (repoPath) => {
        rl.question('Track execution state in git? [y/N]: ', (track) => {
          rl.close();

          const trackState = track.trim().toLowerCase() === 'y';

          if (!repoPath.trim()) {
            console.error('Error: target repository path is required.');
            process.exit(1);
          }

          installLocal(repoPath.trim(), trackState);
        });
      });
    }
  });
}

function main() {
  const args = process.argv.slice(2);
  let isGlobal = false;
  let trackState = false;
  let targetRepo = null;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--global' || arg === '-g') {
      isGlobal = true;
    } else if (arg === '--track-state') {
      trackState = true;
    } else if (arg === '--help' || arg === '-h') {
      showUsage();
      process.exit(0);
    } else if (!arg.startsWith('-')) {
      targetRepo = arg;
    } else {
      console.error(`Unknown option: ${arg}`);
      showUsage();
      process.exit(1);
    }
  }

  if (isGlobal) {
    installGlobal();
  } else if (targetRepo) {
    installLocal(targetRepo, trackState);
  } else if (process.stdin.isTTY && !process.env.CI) {
    interactiveMode();
  } else {
    showUsage();
    process.exit(1);
  }
}

main();
