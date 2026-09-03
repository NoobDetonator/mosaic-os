#!/usr/bin/env node
// Roda o Mosaic OS dentro do CraftOS-PC (implementacao real do CC:Tweaked), sem abrir janela.
//
//   node tools/craftos.js test          self-check do kernel na ROM de verdade
//   node tools/craftos.js boot [segs]   liga o OS de verdade e mostra a tela final
//   node tools/craftos.js exec "<lua>"  roda um trecho de Lua e mostra a tela
//   node tools/craftos.js run <arquivo> roda um .lua do host dentro do computador
//   node tools/craftos.js bench        mede o custo do compositor, dos icones e do kernel
//
// Qualquer comando aceita --size LxA (padrao 51x19, o do computador avancado). O alvo do
// projeto e 80x30, que exige mexer no computercraft-server.toml do servidor; 51x19 continua
// tendo de funcionar, porque nem todo servidor vai mudar.
// ATENCAO: so o modo grafico (shot) respeita o tamanho. O headless do CraftOS-PC ignora
// defaultWidth e computerWidth e sempre roda 51x19, entao test e bench medem nesse tamanho.
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
  // /os vem montado da propria pasta do repositorio, entao o que o OS grava em /os/var
  // (seeded.json, logs) cai no repo e NAO morre com o computador. Sem limpar aqui, a
  // execucao seguinte comeca com estado velho — foi assim que a area de trabalho apareceu
  // vazia: o seeded.json dizia "ja semeei" e o /home tinha acabado de ser apagado.
  fs.rmSync(path.join(ROOT, 'os', 'var'), { recursive: true, force: true });
  writeSize();
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
// Argumentos posicionais, pulando as opcoes e o valor delas. Sem isso o valor de
// --size virava o nome do arquivo de saida do `shot`, e o print saia num arquivo
// chamado "80x30".
const positional = [];
for (let i = 3; i < process.argv.length; i++) {
  if (process.argv[i] === '--size' || process.argv[i] === '--rom') { i++; continue; }
  if (process.argv[i].startsWith('--')) continue;
  positional.push(process.argv[i]);
}
const arg = positional[0] || null;

// Tamanho do terminal: o CraftOS-PC le de config/global.json na pasta de dados.
const sizeArg = process.argv.indexOf('--size');
const SIZE = sizeArg > 0 && process.argv[sizeArg + 1]
  ? process.argv[sizeArg + 1].toLowerCase().split('x').map(Number)
  : [51, 19];
function writeSize() {
  const dir = path.join(DATA, 'config');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'global.json'),
    JSON.stringify({ defaultWidth: SIZE[0], defaultHeight: SIZE[1] }, null, 2));
  // Tamanho por computador. Nem isso vale no headless, mas o modo grafico obedece.
  fs.writeFileSync(path.join(dir, '0.json'),
    JSON.stringify({ computerWidth: SIZE[0], computerHeight: SIZE[1], isColor: true }, null, 2));
}

if (cmd === 'bench') {
  resetComputer();
  const { out } = run([...mounts(true), '--script', path.join(ROOT, 'tools', 'test', 'bench.lua')]);
  // O headless repete a tela a cada mudanca; o relatorio final e o que interessa.
  const lines = out.replace(/\r/g, '').split('\n').map((l) => l.replace(/\s+$/, ''));
  const marks = lines.filter((l) => /^Mosaic bench/.test(l));
  const start = marks.length ? lines.lastIndexOf(marks[marks.length - 1]) : 0;
  console.log(lines.slice(start, start + 16).join('\n'));
  process.exit(0);
}

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
  const special = {
    pointer: ['mosaic.togglePointer()', 'local p = mosaic.pointer()', 'p.x, p.y = 20, 8', 'sleep(1)'],
    // Clique direito na area de trabalho e depois "Sobre", para fotografar o dialogo com o logo.
    // Escolhe pelo teclado (End vai para o ultimo item, que e' o Sobre) em vez de clicar numa
    // linha fixa: o menu mudou de 5 para 9 itens quando a area de trabalho virou pasta, e a
    // coordenada cravada passou a acertar "Atualizar".
    // Linha 15 e' area vazia tanto em 51x19 quanto em 80x30; a linha 8 caia em cima de
    // um icone no tamanho padrao, e ai o menu era o do item, sem "Sobre".
    about: ['os.queueEvent("mouse_click", 2, 30, 15)', 'sleep(1)',
            'os.queueEvent("key", keys["end"], false)', 'sleep(0.5)',
            'os.queueEvent("key", keys.enter, false)', 'sleep(2)'],
    // Menu Iniciar aberto e o clique direito num programa dele. A altura vem do proprio
    // terminal para o cenario valer em 51x19 e em 80x30 sem duas coordenadas cravadas.
    // Abre a pasta Programas com clique duplo, para conferir todos os icones de uma vez.
    // Programas e' o 4o icone (a pasta e listada em ordem alfabetica) e a grade comeca em
    // x = 2 com 12 colunas por icone, entao ele cai em 38..48 tanto em 51x19 quanto em 80x30.
    programas: ['os.queueEvent("mouse_click", 1, 42, 4)', 'sleep(0.2)',
                'os.queueEvent("mouse_click", 1, 42, 4)', 'sleep(2)'],
    // A calculadora com historico de verdade: digita algumas contas antes da foto, senao
    // o print e' so' uma janela vazia. `calcpad` abre o teclado de botoes com F2.
    calc: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'local function digita(s) for i = 1, #s do os.queueEvent("char", s:sub(i, i)) end os.queueEvent("key", keys.enter, false) sleep(0.6) end',
                'digita("2(3+4)")', 'digita("raio = 12")', 'digita("2pi raio")',
                'digita("5!+sqrt(81)")', 'digita("1/0")', 'sleep(0.5)'],
    calcpad: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'local function digita(s) for i = 1, #s do os.queueEvent("char", s:sub(i, i)) end os.queueEvent("key", keys.enter, false) sleep(0.6) end',
                'digita("2(3+4)")', 'digita("raio = 12")', 'digita("2pi raio")',
                'digita("5!+sqrt(81)")', 'digita("1/0")', 'sleep(0.5)',
                'os.queueEvent("key", keys.f2, false)', 'sleep(1.2)'],
    // Aba Blocos. O clique vai na linha das abas da janela da calculadora, achada pelo
    // mosaic.list() em vez de coordenada cravada: a janela nasce em cascata.
    calcblocos: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Calculadora" then',
                '  os.queueEvent("mouse_click", 1, p.x + 10, p.y + p.h) end end',
                'sleep(1.5)'],
    // Aba Grafico. Mesmo truque do calcblocos, so' que o botao fica mais a direita.
    calcgraf: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Calculadora" then',
                '  os.queueEvent("mouse_click", 1, p.x + 20, p.y + p.h) end end',
                'sleep(2)'],
    startctx: ['local _, H = mosaic.screenSize()',
               'os.queueEvent("mouse_click", 1, 3, H)', 'sleep(1)',
               'os.queueEvent("mouse_click", 2, 5, 5)', 'sleep(1.5)'],
  };
  const actions = special[arg] || (arg ? [`mosaic.launch("/os/apps/${arg}.lua")`, 'sleep(2)'] : []);
  if (arg && !special[arg] && !fs.existsSync(path.join(ROOT, 'os', 'apps', `${arg}.lua`))) {
    console.error(`nao existe os/apps/${arg}.lua`);
    process.exit(2);
  }
  const file = bootAndShoot(actions, arg ? 2 : 3, positional[1]);
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
