#!/usr/bin/env node
// maxpublish.js — npm-bin wrapper for the maxpublish skill.
// Usage: npx claude-maxpublish --eval | --guide | <topic>
// For the actual workflow, prefer invoking the skill via Claude Code (/maxpublish).
'use strict';

const { execSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const SKILL_DIR = path.dirname(require.main.filename).replace(/\/scripts\/bin$/, '');
const SIGNALS = path.join(SKILL_DIR, 'scripts', 'signals.sh');

const args = process.argv.slice(2);

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  console.log(`claude-maxpublish v${require(path.join(SKILL_DIR, 'package.json')).version}`);
  console.log('');
  console.log('A Claude skill that detects your project, fixes blockers, and ships to chosen registries.');
  console.log('');
  console.log('Usage:');
  console.log('  npx claude-maxpublish --signals     # show project signals (human)');
  console.log('  npx claude-maxpublish --signals --json   # machine-readable');
  console.log('  npx claude-maxpublish --guide       # first-run guide + confirm');
  console.log('  npx claude-maxpublish --fix-credentials <plat> [<plat>...]');
  console.log('  npx claude-maxpublish --fix-install <tool>');
  console.log('  npx claude-maxpublish --fix-version <ver> [--dry-run]');
  console.log('  npx claude-maxpublish --record <plat> <ver> <status> [note]');
  console.log('  npx claude-maxpublish --announce <ver> <name> <results-json>');
  console.log('  npx claude-maxpublish --suggest <plat> <error>');
  console.log('');
  console.log('For the full workflow, use the /maxpublish slash command in Claude Code.');
  process.exit(0);
}

function dispatch(arg) {
  switch (arg) {
    case '--signals':
      return ['scripts/signals.sh', args.includes('--json') ? '--json' : null].filter(Boolean);
    case '--guide':
      return ['scripts/signals.sh', '--guide'];
    case '--fix-install':
      return ['scripts/fix-install.sh', ...args.slice(1)];
    case '--fix-credentials':
      return ['scripts/fix-credentials.sh', ...args.slice(1)];
    case '--fix-version':
      return ['scripts/fix-version.sh', ...args.slice(1)];
    case '--suggest':
      return ['scripts/fix-suggest.sh', ...args.slice(1)];
    case '--record':
      return ['scripts/record.sh', ...args.slice(1)];
    case '--announce':
      return ['scripts/announce.sh', ...args.slice(1)];
    default:
      console.error(`Unknown flag: ${arg}`);
      console.error('Run with --help for usage.');
      process.exit(64);
  }
}

const subArgs = dispatch(args[0]);
const sub = spawnSync('bash', subArgs, { cwd: process.cwd(), stdio: 'inherit' });
process.exit(sub.status ?? 1);
