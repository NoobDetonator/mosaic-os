#!/usr/bin/env node
// Abre um app no emulador e mostra a tela (topo, e depois de rolar ate o fim).
//   node tools/debug.js os/apps/files.lua
// (execFileSync porque a saida do emulador se perde quando ele chama process.exit num pipe.)
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const emu = path.join(__dirname, 'emu', 'emu.js');
const dump = path.join(__dirname, 'emu', 'sandbox', 'dbg.txt');

// O Git Bash reescreve "/os/apps/x.lua" como caminho do Windows; recupera o trecho util.
let target = (process.argv[2] || '').split(String.fromCharCode(92)).join('/');
const m = target.match(/(?:^|[/])(os[/].*)$/);
if (m) target = '/' + m[1];
else if (target && target[0] !== '/') target = '/' + target;

let stderr = '';
try {
  execFileSync('node', [emu, '--script', ('/test/debug.lua ' + target + ' ' + process.argv.slice(3).join(' ')).trim()], { encoding: 'utf8' });
} catch (e) {
  stderr = e.stderr || '';
}
const w = (s) => fs.writeSync(1, s);
if (fs.existsSync(dump)) w(fs.readFileSync(dump, 'utf8').replace(/[ \t]+$/gm, ''));
else w('sem /dbg.txt — o emulador morreu antes de escrever\n');
if (stderr.trim()) w('--- stderr ---\n' + stderr + '\n');
