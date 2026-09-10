#!/usr/bin/env node
// Roda o self-check do kernel no emulador e mostra o resultado.
//
// A OUTRA suite, /test/regression.lua, NAO roda aqui: ela mora no `craftos.js test`. O
// serializador de JSON deste emulador usa `string.format("%d", ...)`, e o fengari (Lua 5.3)
// recusa float ali - o CC do jogo (5.1) aceita calado. E' limitacao do emulador, nao do
// produto, e forcar a suite a caber aqui seria dobrar o codigo bom para agradar o arreio.
//
// (execFileSync porque a saida do emulador se perde quando o processo chama process.exit num pipe.)
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const emu = path.join(__dirname, 'emu', 'emu.js');
const extra = process.argv.slice(2);
const w = (s) => fs.writeSync(1, s);

// `marca` e' a linha que prova que a suite chegou ao fim. Sem ela, o script abortou no meio
// (erro de sintaxe, arquivo faltando, assert estourado) e isso NAO e' sucesso, mesmo que o
// emulador saia com 0.
function roda(script, marca) {
  let status = 0, stdout = '', stderr = '';
  try {
    stdout = execFileSync('node', [emu, '--script', script, '--show', ...extra], { encoding: 'utf8' });
  } catch (e) {
    status = e.status === undefined ? 1 : e.status;
    stdout = e.stdout || '';
    stderr = e.stderr || '';
  }
  w(stdout.replace(/[ \t]+$/gm, '') + '\n');
  if (stderr.trim()) w('--- stderr ---\n' + stderr + '\n');
  if (!stdout.includes(marca)) {
    w(`(a suite ${script} nao chegou ao resultado)\n`);
    return 1;
  }
  return status;
}

const falhou = roda('/test/run.lua', 'Kernel self-check:');

const crash = path.join(__dirname, 'emu', 'sandbox', 'os_var', 'log', 'crash.log');
if (fs.existsSync(crash)) {
  w('--- crash.log ---\n' + fs.readFileSync(crash, 'utf8') + '\n');
}
process.exit(falhou);
