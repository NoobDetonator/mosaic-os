#!/usr/bin/env node
// Roda o self-check do kernel no emulador e mostra o resultado.
// (execFileSync porque a saida do emulador se perde quando o processo chama process.exit num pipe.)
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const emu = path.join(__dirname, 'emu', 'emu.js');
const extra = process.argv.slice(2);
let status = 0, stdout = '', stderr = '';
try {
  stdout = execFileSync('node', [emu, '--script', '/test/run.lua', '--show', ...extra], { encoding: 'utf8' });
} catch (e) {
  status = e.status;
  stdout = e.stdout || '';
  stderr = e.stderr || '';
}
const w = (s) => fs.writeSync(1, s);
w(stdout.replace(/[ \t]+$/gm, '') + '\n');
if (stderr.trim()) w('--- stderr ---\n' + stderr + '\n');

const crash = path.join(__dirname, 'emu', 'sandbox', 'os_var', 'log', 'crash.log');
if (fs.existsSync(crash)) {
  w('--- crash.log ---\n' + fs.readFileSync(crash, 'utf8') + '\n');
}
process.exit(status);
