#!/usr/bin/env node
// Roda o Mosaic OS dentro do CraftOS-PC (implementacao real do CC:Tweaked), sem abrir janela.
//
//   node tools/craftos.js test          self-check do kernel na ROM de verdade
//   node tools/craftos.js boot [segs]   liga o OS de verdade e mostra a tela final
//   node tools/craftos.js exec "<lua>"  roda um trecho de Lua e mostra a tela
//   node tools/craftos.js run <arquivo> roda um .lua do host dentro do computador
//
// Diferenca para tools/test.js (emulador proprio em JS): aqui rodam a ROM, o shell,
// o edit/paint e a API window originais. Em troca, o CraftOS-PC 2.8+ traz uma ROM mais
// nova que a do alvo (Minecraft 1.16.5 / CC:T ~1.101), entao ele NAO acusa uso de API
// nova demais nem sintaxe de Lua 5.2 — quem cuida disso e o tools/lint.js.
// Para testar na ROM exata do jogo, use --rom com a pasta lua/ extraida do jar do mod.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const CANDIDATES = [
  process.env.CRAFTOS,
  'C:\\Program Files\\CraftOS-PC\\CraftOS-PC_console.exe',
  'C:\\Program Files (x86)\\CraftOS-PC\\CraftOS-PC_console.exe',
  path.join(process.env.LOCALAPPDATA || '', 'Programs', 'CraftOS-PC', 'CraftOS-PC_console.exe'),
  '/usr/bin/craftos',
  '/usr/local/bin/craftos',
];

function findCraftos() {
  for (const c of CANDIDATES) if (c && fs.existsSync(c)) return c;
  console.error('CraftOS-PC nao encontrado. Instale de https://www.craftos-pc.cc/ ou aponte a');
  console.error('variavel CRAFTOS para o executavel (CraftOS-PC_console.exe no Windows).');
  process.exit(2);
}

const EXE = findCraftos();
const DATA = path.join(os.tmpdir(), 'mosaic-craftos');
const COMPUTER = path.join(DATA, 'computer', '0');

// Limpa o computador a cada execucao para o teste comecar sempre do zero.
function resetComputer() {
  fs.rmSync(COMPUTER, { recursive: true, force: true });
  fs.mkdirSync(COMPUTER, { recursive: true });
}

// A saida headless e um despejo do terminal a cada mudanca de tela: o final e o estado final.
function lastScreen(raw, lines) {
  const clean = raw.replace(/\r/g, '').split('\n').map((l) => l.replace(/\s+$/, ''));
  while (clean.length && clean[clean.length - 1] === '') clean.pop();
  return clean.slice(-(lines || 19)).join('\n');
}

function run(args, timeoutMs) {
  const res = spawnSync(EXE, ['--headless', '-d', DATA, ...args], {
    encoding: 'utf8', timeout: timeoutMs || 120000, input: '',
    windowsHide: true,
  });
  return { out: (res.stdout || '') + (res.stderr || ''), status: res.status };
}

const mounts = (rw) => [
  rw ? '--mount-rw' : '--mount-ro', `/os=${path.join(ROOT, 'os')}`,
];

const cmd = process.argv[2] || 'test';
const arg = process.argv[3];

if (cmd === 'test') {
  resetComputer();
  const { out, status } = run([...mounts(true), '--script', path.join(ROOT, 'tools', 'test', 'run.lua')]);
  const result = out.replace(/\r/g, '').split('\n')
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => /self-check:|^\s+- /.test(l));
  // As linhas se repetem a cada quadro; ficamos com a ultima ocorrencia de cada uma.
  const seen = new Set();
  const unique = [];
  for (const l of result.reverse()) if (!seen.has(l.trim())) { seen.add(l.trim()); unique.unshift(l.trim()); }
  if (unique.length) console.log(unique.join('\n'));
  else { console.log('(nao achei o resultado; tela final:)'); console.log(lastScreen(out)); }
  process.exit(status || 0);
}

// Liga o OS e tira um print PNG de verdade (pixels, fonte e cores do CraftOS-PC).
// Precisa do modo grafico: uma janela abre por alguns segundos e fecha sozinha.
function bootAndShoot(actions, secs, outFile) {
  resetComputer();
  fs.copyFileSync(path.join(ROOT, 'startup.lua'), path.join(COMPUTER, 'startup.lua'));
  const SHOTS = path.join(DATA, 'screenshots');
  fs.rmSync(SHOTS, { recursive: true, force: true });
  const OUT = path.join(DATA, 'out');
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'snap.lua'), [
    'mosaic.minimize()',
    `sleep(${secs})`,
    ...actions,
    // term.screenshot e uma extensao do CraftOS-PC; captura a tela real, nao o redirect.
    'local shoot = term.screenshot or (term.native and term.native().screenshot)',
    'if shoot then pcall(shoot) end',
    'sleep(1)',
    'os.shutdown()',
  ].join('\n'));
  fs.writeFileSync(path.join(COMPUTER, '.settings'),
    '{\n  ["mosaic.autostart"] = {\n    "/out/snap.lua",\n  },\n}\n');

  spawnSync(EXE.replace('_console', ''), ['-d', DATA, ...mounts(true), '--mount-rw', `/out=${OUT}`], {
    encoding: 'utf8', timeout: (secs + 30) * 1000, input: '', windowsHide: true,
  });

  if (!fs.existsSync(SHOTS)) return null;
  const files = fs.readdirSync(SHOTS).filter((f) => /\.(png|bmp|webp)$/.test(f)).sort();
  if (!files.length) return null;
  const src = path.join(SHOTS, files[files.length - 1]);
  const dest = outFile || path.join(ROOT, 'tools', 'shots', files[files.length - 1]);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return dest;
}

if (cmd === 'shot') {
  const actions = arg === 'pointer'
    ? ['mosaic.togglePointer()', 'local p = mosaic.pointer()', 'p.x, p.y = 20, 8', 'sleep(1)']
    : (arg ? [`mosaic.launch("/os/apps/${arg}.lua")`, 'sleep(2)'] : []);
  if (arg && arg !== 'pointer' && !fs.existsSync(path.join(ROOT, 'os', 'apps', `${arg}.lua`))) {
    console.error(`nao existe os/apps/${arg}.lua`);
    process.exit(2);
  }
  const file = bootAndShoot(actions, arg ? 2 : 3, process.argv[4]);
  if (!file) {
    console.error('O CraftOS-PC nao gerou o print. Ele precisa do modo grafico (nao roda headless).');
    process.exit(1);
  }
  console.log(file);
  process.exit(0);
}

// Liga o OS de verdade, executa `actions` (Lua) e devolve a tela composta.
// A tela nao pode sair do despejo do headless: o relogio redesenha a cada segundo e o fim
// da saida vira so a taskbar. Entao o proprio OS tira a foto, por um app de autostart.
function bootAndSnap(actions, secs) {
  resetComputer();
  fs.copyFileSync(path.join(ROOT, 'startup.lua'), path.join(COMPUTER, 'startup.lua'));
  const OUT = path.join(DATA, 'out');
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'snap.lua'), [
    'mosaic.minimize()',
    `sleep(${secs})`,
    ...actions,
    'local h = fs.open("/out/screen.txt", "w")',
    'h.write(mosaic.screenshotText())',
    'h.close()',
    'os.shutdown()',
  ].join('\n'));
  fs.writeFileSync(path.join(COMPUTER, '.settings'),
    '{\n  ["mosaic.autostart"] = {\n    "/out/snap.lua",\n  },\n}\n');
  run([...mounts(true), '--mount-rw', `/out=${OUT}`], (secs + 25) * 1000);
  const shot = path.join(OUT, 'screen.txt');
  if (!fs.existsSync(shot)) {
    console.error('O OS nao chegou a tirar a foto da tela. Rode "node tools/craftos.js test".');
    process.exit(1);
  }
  return fs.readFileSync(shot, 'utf8').replace(/[ \t]+$/gm, '');
}

if (cmd === 'boot') {
  console.log(bootAndSnap([], parseInt(arg || '3', 10)));
  process.exit(0);
}

if (cmd === 'app') {
  if (!arg) {
    console.error('uso: node tools/craftos.js app <nome>   (nome do arquivo em os/apps, sem .lua)');
    console.error('apps: ' + fs.readdirSync(path.join(ROOT, 'os', 'apps')).map((f) => f.replace('.lua', '')).join(' '));
    process.exit(2);
  }
  const app = `/os/apps/${arg}.lua`;
  if (!fs.existsSync(path.join(ROOT, 'os', 'apps', `${arg}.lua`))) {
    console.error(`nao existe ${app}`);
    process.exit(2);
  }
  console.log(bootAndSnap([`mosaic.launch("${app}")`, 'sleep(2)'], 2));
  process.exit(0);
}

if (cmd === 'exec') {
  if (!arg) { console.error('uso: node tools/craftos.js exec "<codigo lua>"'); process.exit(2); }
  resetComputer();
  const { out, status } = run([...mounts(true), '--exec', arg]);
  console.log(lastScreen(out));
  process.exit(status || 0);
}

if (cmd === 'run') {
  if (!arg) { console.error('uso: node tools/craftos.js run <arquivo.lua>'); process.exit(2); }
  resetComputer();
  const { out, status } = run([...mounts(true), '--script', path.resolve(arg)]);
  console.log(lastScreen(out));
  process.exit(status || 0);
}

console.error(`comando desconhecido: ${cmd}\nuse: test | boot [segundos] | exec "<lua>" | run <arquivo.lua>`);
process.exit(2);
