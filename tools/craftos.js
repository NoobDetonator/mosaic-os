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
  // Os apoios de teste (perifericos falsos) vivem em tools/test e sao carregados por
  // caminho de dentro do CC. O emulador proprio ja monta isso como /test; sem o mesmo
  // aqui, o run.lua daria "File not found" so' no CraftOS.
  '--mount-ro', `/test=${path.join(ROOT, 'tools', 'test')}`,
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
// `extra` entra no global.json junto com o tamanho. Serve para o modo `live` liberar o
// endereco local: o CraftOS-PC tambem bloqueia IP local por padrao (http_blacklist), como o
// CC:T do jogo faz com a regra $private.
function writeSize(extra) {
  const dir = path.join(DATA, 'config');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'global.json'),
    JSON.stringify({ defaultWidth: SIZE[0], defaultHeight: SIZE[1], ...(extra || {}) }, null, 2));
  // Tamanho por computador. Nem isso vale no headless, mas o modo grafico obedece.
  fs.writeFileSync(path.join(dir, '0.json'),
    JSON.stringify({ computerWidth: SIZE[0], computerHeight: SIZE[1], isColor: true }, null, 2));
}

// ---------------------------------------------------------------- live
// Um Mosaic de verdade para MEXER, nao para fotografar: janela grafica, alto-falante que sai
// som, monitores, e o relay ligado. E' o mais perto do jogo que da para chegar sem o jogo.
//
//   node tools/craftos.js live [--size 80x30]
//
// Tres coisas precisam ser arrumadas para a musica tocar aqui, e as tres sao o mesmo
// problema que aparece no Minecraft:
//   1. o CraftOS-PC bloqueia IP local por padrao (http_blacklist), como o $private do CC:T;
//   2. o computador precisa de um alto-falante ao lado (periphemu);
//   3. o OS precisa do endereco do relay nas configuracoes.
if (cmd === 'live') {
  const { spawn } = require('child_process');
  const PORTA = parseInt(process.env.PORT || '8765', 10);
  const relayDir = path.join(ROOT, 'relay');
  const tokenFile = path.join(relayDir, '.token');

  const espera = (ms) => new Promise((r) => setTimeout(r, ms));
  const ping = async () => {
    try {
      const r = await fetch(`http://127.0.0.1:${PORTA}/api/ping`);
      return r.ok;
    } catch (_) { return false; }
  };

  (async () => {
    // Aproveita um relay ja rodando; so' sobe um se nao houver. Subir um segundo daria
    // "porta em uso" e o erro nao explicaria nada.
    let meuRelay = null;
    if (await ping()) {
      console.log(`relay: ja estava rodando na porta ${PORTA}`);
    } else {
      if (!fs.existsSync(path.join(relayDir, 'node_modules'))) {
        console.error('Falta `cd relay && npm install`.');
        process.exit(2);
      }
      meuRelay = spawn(process.execPath, ['relay.js'], {
        cwd: relayDir, env: { ...process.env, PORT: String(PORTA) },
        stdio: ['ignore', 'ignore', 'inherit'],
      });
      for (let i = 0; i < 30 && !(await ping()); i++) await espera(300);
      if (!(await ping())) { console.error('o relay nao subiu'); process.exit(1); }
      console.log(`relay: subi um na porta ${PORTA} (morre junto com esta janela)`);
    }

    const token = fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : '';

    resetComputer();
    // http_blacklist vazio: sem isto o computador nao alcanca o relay em 127.0.0.1, que e'
    // exatamente a armadilha do $private no jogo.
    writeSize({ http_blacklist: [], http_whitelist: ['*'], http_enable: true, http_websocket_enabled: true });
    fs.copyFileSync(path.join(ROOT, 'startup.lua'), path.join(COMPUTER, 'startup.lua'));

    const OUT = path.join(DATA, 'out');
    fs.rmSync(OUT, { recursive: true, force: true });
    fs.mkdirSync(OUT, { recursive: true });
    // periphemu e' extensao do emulador (proibida em os/), e por isso mora aqui fora.
    fs.writeFileSync(path.join(OUT, 'perifericos.lua'), [
      'if not periphemu then return end',
      'pcall(periphemu.create, "left", "speaker")',
      '-- Monitores para experimentar o "Enviar para monitor" da barra de tarefas. No modo',
      '-- grafico cada um abre a propria janela; no headless o CraftOS-PC recusa.',
      'pcall(periphemu.create, "top", "monitor")',
      'pcall(periphemu.create, "right", "monitor")',
    ].join('\n'));

    // O .settings do CC e' tabela LUA (textutils.serialize), nao JSON: `{"a":"b"}` nao
    // carrega, e a falha e' silenciosa - o OS so' abriria sem relay nenhum.
    fs.writeFileSync(path.join(COMPUTER, '.settings'), [
      '{',
      `  ["mosaic.relay.url"] = "ws://127.0.0.1:${PORTA}/ws/computer",`,
      `  ["mosaic.relay.token"] = "${token.replace(/"/g, '')}",`,
      '  ["mosaic.som.enabled"] = true,',
      '  ["mosaic.som.volume"] = 1,',
      '  ["mosaic.autostart"] = {',
      '    "/out/perifericos.lua",',
      '  },',
      '}',
      '',
    ].join('\n'));

    // `--check` faz o mesmo preparo mas roda headless e confere, em vez de abrir a janela.
    // Existe para o preparo nao apodrecer calado: se o formato do .settings mudar, ou o
    // musicd parar de enxergar o relay, isto acusa - e ninguem descobre so' ao abrir.
    if (process.argv.includes('--check')) {
      fs.writeFileSync(path.join(OUT, 'checar.lua'), [
        'sleep(2)',   // deixa os perifericos e os servicos subirem',
        'local L = {}',
        'local function diz(k, v) L[#L + 1] = k .. "=" .. tostring(v) end',
        'diz("relay.url", settings.get("mosaic.relay.url"))',
        'diz("speaker", peripheral.find("speaker") ~= nil)',
        'local st = mosaic.musicStatus and mosaic.musicStatus()',
        'diz("musicd", st ~= nil)',
        'diz("musicd.relay", st and st.relay)',
        'diz("musicd.temSom", st and st.temSom)',
        'local doc, err = mosaic.lib("httpx").gatewayJSON("/api/deps")',
        'diz("relay.deps", doc and (tostring(doc.ok) .. " falta:" .. table.concat(doc.falta or {}, ",")) or ("ERRO " .. tostring(err)))',
        'local h = fs.open("/out/live.txt", "w") h.write(table.concat(L, "\\n")) h.close()',
        'os.shutdown()',
      ].join('\n'));
      fs.writeFileSync(path.join(COMPUTER, '.settings'),
        fs.readFileSync(path.join(COMPUTER, '.settings'), 'utf8')
          .replace('"/out/perifericos.lua",', '"/out/perifericos.lua",\n    "/out/checar.lua",'));
      run([...mounts(true), '--mount-rw', `/out=${OUT}`], 60000);
      const rel = path.join(OUT, 'live.txt');
      if (meuRelay) meuRelay.kill();
      if (!fs.existsSync(rel)) { console.error('o OS nao chegou a conferir nada'); process.exit(1); }
      const texto = fs.readFileSync(rel, 'utf8');
      console.log(texto);
      const ruim = /=(false|nil)|ERRO/.test(texto);
      process.exit(ruim ? 1 : 0);
    }

    console.log('');
    console.log('  Mosaic ao vivo no CraftOS-PC');
    console.log('  ---------------------------------------------');
    console.log(`  relay:       http://127.0.0.1:${PORTA}/`);
    console.log('  alto-falante: left      monitores: top, right');
    console.log('  som:         abra Musica, cole um link ou digite um nome');
    console.log('  monitor:     botao direito no botao da barra de tarefas');
    console.log('');
    console.log('  Feche a janela do CraftOS-PC para encerrar.');
    console.log('');

    const gui = EXE.replace('_console', '');
    const filho = spawn(gui, ['-d', DATA, ...mounts(true), '--mount-rw', `/out=${OUT}`],
      { stdio: 'inherit' });
    filho.on('close', () => { if (meuRelay) meuRelay.kill(); process.exit(0); });
  })();
  return;
}

if (cmd === 'bench') {
  resetComputer();
  // O relatorio sai por arquivo e nao pela tela: ele passou das 19 linhas do terminal e as
  // medidas do fim rolavam para fora sem ninguem notar que faltavam.
  const OUT = path.join(DATA, 'out');
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });
  run([...mounts(true), '--mount-rw', `/out=${OUT}`,
    '--script', path.join(ROOT, 'tools', 'test', 'bench.lua')]);
  const rel = path.join(OUT, 'bench.txt');
  if (!fs.existsSync(rel)) {
    console.error('O bench nao gerou /out/bench.txt - provavelmente quebrou antes do relatorio.');
    process.exit(1);
  }
  const texto = fs.readFileSync(rel, 'utf8');
  console.log(texto);
  // Guarda a ultima medida, para dar diff entre uma otimizacao e outra.
  const dest = positional[1] || path.join(ROOT, 'docs', 'bench-ultimo.txt');
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, texto);
  process.exit(0);
}

if (cmd === 'test') {
  resetComputer();
  // Tempo folgado: aqui o relogio e' real, e os testes que esperam a batida de um servico
  // (a musica) custam segundos de verdade, nao passos virtuais como no emulador.
  const { out, status } = run([...mounts(true), '--script', path.join(ROOT, 'tools', 'test', 'run.lua')], 300000);
  const result = out.replace(/\r/g, '').split('\n')
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => /self-check:|^\s+- /.test(l));
  // As linhas se repetem a cada quadro; ficamos com a ultima ocorrencia de cada uma.
  const seen = new Set();
  const unique = [];
  for (const l of result.reverse()) if (!seen.has(l.trim())) { seen.add(l.trim()); unique.unshift(l.trim()); }
  if (unique.length) { console.log(unique.join('\n')); process.exit(status || 0); }
  // Sem a linha do self-check o teste abortou antes do fim (erro de sintaxe, arquivo que
  // falta, computador travado). Isso NAO e' sucesso: sair com 0 aqui ja deixou passar um
  // commit vermelho uma vez, porque o `&&` da linha de comando seguiu em frente.
  console.log('(o teste nao chegou ao resultado; tela final:)');
  console.log(lastScreen(out));
  process.exit(1);
}

// Liga o OS e tira um print PNG de verdade (pixels, fonte e cores do CraftOS-PC).
// Precisa do modo grafico: uma janela abre por alguns segundos e fecha sozinha.
// `configExtra` existe para o cenario que precisa alcancar o relay: por padrao o CraftOS-PC
// bloqueia IP local, como o CC:T do jogo. O padrao continua estrito de proposito - so' quem
// declara que precisa e' que afrouxa.
function bootAndShoot(actions, secs, outFile, configExtra) {
  resetComputer();
  if (configExtra) writeSize(configExtra);
  fs.copyFileSync(path.join(ROOT, 'startup.lua'), path.join(COMPUTER, 'startup.lua'));
  const SHOTS = path.join(DATA, 'screenshots');
  fs.rmSync(SHOTS, { recursive: true, force: true });
  const OUT = path.join(DATA, 'out');
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });
  // O reator falso vive em tools/test, que nao e' montado no computador: vai junto
  // para /out, que ja e' montado rw para o snap.
  fs.copyFileSync(path.join(ROOT, 'tools', 'test', 'fake-reactor.lua'),
    path.join(OUT, 'fake-reactor.lua'));
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
    calcbaus: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Calculadora" then',
                '  os.queueEvent("mouse_click", 1, p.x + 31, p.y + p.h) end end',
                'sleep(2)'],
    calccreate: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Calculadora" then',
                '  os.queueEvent("mouse_click", 1, p.x + 39, p.y + p.h) end end',
                'sleep(2)'],
    // Blocos em 3D: abre a aba, gera uma cupula e liga a caixa 3D com Alt+3.
    calc3d: ['local r = mosaic.require("apps.registry") r.open(r.byId("calc"))', 'sleep(1.5)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Calculadora" then',
                '  os.queueEvent("mouse_click", 1, p.x + 10, p.y + p.h)',
                '  sleep(1)',
                // abre a lista de formas e escolhe Esfera (6a linha), que rende mais em 3D
                '  os.queueEvent("mouse_click", 1, p.x + 10, p.y + 1)',
                '  sleep(1)',
                '  os.queueEvent("mouse_click", 1, p.x + 10, p.y + 7)',
                '  sleep(1)',
                '  os.queueEvent("mouse_click", 1, p.x + 41, p.y + 1) end end',
                'sleep(3)'],
    // Demos 3D. Eles nao estao no registry de proposito, entao abrem pelo caminho mesmo.
    cubo: ['mosaic.launchWith({ title = "Cubo 3D", w = 50, h = 17 }, "/os/demos/cubo.lua")',
                'sleep(3)'],
    terreno: ['mosaic.launchWith({ title = "Terreno", w = 50, h = 17 }, "/os/demos/terreno.lua")',
                'sleep(3)'],
    // Espaco para a foto: o modelo para no angulo inicial (frente e lateral, com a agua
    // furtada do telhado de perfil) em vez de sair num quadro qualquer do giro.
    modelo: ['mosaic.launchWith({ title = "Modelos", w = 50, h = 17 }, "/os/demos/modelo.lua")',
                'sleep(1)', 'os.queueEvent("key", keys.space, false)', 'sleep(1.5)'],
    // O mesmo visualizador na Suzanne do Blender: N troca de modelo (a lista sai em ordem
    // alfabetica, entao casa vem antes de monkey).
    modelosuz: ['mosaic.launchWith({ title = "Modelos", w = 50, h = 17 }, "/os/demos/modelo.lua")',
                'sleep(1)', 'os.queueEvent("key", keys.space, false)', 'sleep(0.3)',
                'os.queueEvent("key", keys.n, false)', 'sleep(0.3)',
                // Meia volta: a Suzanne sai do Blender de costas para a camera do orbit.
                'for _ = 1, 21 do os.queueEvent("key", keys.left, false) sleep(0.05) end', 'sleep(1.5)'],
    // O mesmo cubo com a paleta de oito degraus ligada (tecla P), para comparar lado a lado.
    cubopal: ['mosaic.launchWith({ title = "Cubo 3D", w = 50, h = 17 }, "/os/demos/cubo.lua")',
                'sleep(2)', 'os.queueEvent("key", keys.p, false)', 'sleep(2)'],
    // Liga a paleta de 3D e SAI: prova que ela volta ao normal. Se o icone do Paint ou o do
    // Reator sairem cinzas neste print, o restore nao funcionou.
    cubopalvolta: ['mosaic.launchWith({ title = "Cubo 3D", w = 50, h = 17 }, "/os/demos/cubo.lua")',
                'sleep(2)', 'os.queueEvent("key", keys.p, false)', 'sleep(1.5)',
                'os.queueEvent("key", keys.q, false)', 'sleep(2)'],
    // Modo arame, na casa e nao na Suzanne: com 968 triangulos as arestas se encostam e o
    // arame vira uma mancha cinza. Arame se le com pouco poligono.
    arame: ['mosaic.launchWith({ title = "Modelos", w = 50, h = 17 }, "/os/demos/modelo.lua")',
                'sleep(1)', 'os.queueEvent("key", keys.space, false)', 'sleep(0.3)',
                'os.queueEvent("key", keys.a, false)', 'sleep(1.5)'],
    // O menu de janela com monitores de mentira. Monitor de verdade nao existe no CraftOS-PC
    // headless nem sai no print do modo grafico (o term.screenshot fotografa so' a janela do
    // computador), mas o MENU aparece na tela do computador - e e' ele que se quer mostrar.
    monitor: ['local fp = dofile("/test/fake-periph.lua")',
                'fp.monitor("monitor_0", 30, 10)',
                'fp.monitor("monitor_1", 60, 20)',
                'fp.instalar()',
                'mosaic.launchWith({ title = "Relogio", w = 24, h = 8 }, "/os/apps/clock.lua")',
                'sleep(2)',
                // Clique direito no botao da barra de tarefas, achado pelo titulo em vez de
                // coordenada cravada: o botao encolhe conforme o numero de janelas abertas.
                'local _, H = mosaic.screenSize()',
                'for _, s in ipairs(mosaic.wm.slots) do',
                '  if s.p.title == "Relogio" then os.queueEvent("mouse_click", 2, s.x1 + 1, H) end end',
                'sleep(2)'],
    // O navegador com uma pagina DE VERDADE, pelo relay. Aqui nao ha mentira nenhuma: se o
    // relay nao estiver no ar, o print sai com a mensagem de erro - e isso e' informacao.
    web: ['settings.set("mosaic.relay.url", "ws://127.0.0.1:8765/ws/computer")',
                `settings.set("mosaic.relay.token", ${JSON.stringify(
                  fs.existsSync(path.join(ROOT, 'relay', '.token'))
                    ? fs.readFileSync(path.join(ROOT, 'relay', '.token'), 'utf8').trim() : '')})`,
                'local r = mosaic.require("apps.registry") r.open(r.byId("browser"))',
                'sleep(1.5)',
                'for ch in ("tweaked.cc/peripheral/speaker.html"):gmatch(".") do os.queueEvent("char", ch) end',
                'os.queueEvent("key", keys.enter, false)',
                'sleep(5)'],
    // A busca, que e' o outro caminho do navegador.
    webbusca: ['settings.set("mosaic.relay.url", "ws://127.0.0.1:8765/ws/computer")',
                `settings.set("mosaic.relay.token", ${JSON.stringify(
                  fs.existsSync(path.join(ROOT, 'relay', '.token'))
                    ? fs.readFileSync(path.join(ROOT, 'relay', '.token'), 'utf8').trim() : '')})`,
                'local r = mosaic.require("apps.registry") r.open(r.byId("browser"))',
                'sleep(1.5)',
                'for ch in ("alto falante minecraft computercraft"):gmatch(".") do os.queueEvent("char", ch) end',
                'os.queueEvent("key", keys.enter, false)',
                'sleep(5)'],
    // O tocador com uma fila de mentira. Sem isto o print seria uma janela vazia dizendo
    // "cole um link": o relay de verdade levaria 30 s e dependeria da internet.
    musica: ['local fp = dofile("/test/fake-periph.lua")',
                'fp.speaker("speaker_0")',
                'local h = fp.http()',
                'local n = 0',
                'h.responde("/api/musica", function()',
                '  n = n + 1',
                '  local nomes = { "C418 - Sweden", "C418 - Wet Hands", "Lena Raine - Pigstep" }',
                '  local durs = { 216, 90, 148 }',
                '  return string.format(',
                '    [[{"id":"abc000000000000%d","titulo":"%s","autor":"C418","duracao":%d,"blocos":%d}]],',
                '    n, nomes[n] or "Faixa", durs[n] or 100, math.ceil((durs[n] or 100) / 2.73))',
                'end)',
                'h.responde("/api/audio/", string.rep("\\170", 16 * 1024))',
                'fp.instalar()',
                'settings.set("mosaic.relay.url", "ws://127.0.0.1:8765/ws/computer")',
                'settings.set("mosaic.relay.token", "x")',
                'local r = mosaic.require("apps.registry") r.open(r.byId("music"))',
                'sleep(1)',
                'for _ = 1, 3 do os.queueEvent("mosaic:music_cmd", "add", "faixa") sleep(1.2) end',
                'sleep(1.5)'],
    // O painel do reator com um reator de mentira: o de verdade so' existe no jogo.
    // `janela` e' o tamanho, para conferir o mesmo painel em tela de monitor.
    reator: ['dofile("/out/fake-reactor.lua").instalar()',
                'local W, H = mosaic.screenSize()',
                'mosaic.launchWith({ title = "Reator", x = 1, y = 1, w = W, h = H - 1 }, "/os/apps/reactor.lua")',
                'sleep(6)'],
    // O mesmo painel no tamanho do monitor de verdade do servidor: 36x24 na escala 0,5.
    reatormon: ['dofile("/out/fake-reactor.lua").instalar()',
                'mosaic.launchWith({ title = "Reator", x = 1, y = 1, w = 36, h = 24 }, "/os/apps/reactor.lua")',
                'sleep(6)'],
    // O painel do reator em 3D: a aba fica depois de Painel, Controle e Config.
    reator3d: ['dofile("/out/fake-reactor.lua").instalar()',
                'local W, H = mosaic.screenSize()',
                'mosaic.launchWith({ title = "Reator", x = 1, y = 1, w = W, h = H - 1 }, "/os/apps/reactor.lua")',
                'sleep(4)',
                'for _, p in ipairs(mosaic.list()) do if p.title == "Reator" then',
                '  os.queueEvent("mouse_click", 1, p.x + 27, p.y + p.h) end end',
                // Espaco congela o giro: sem isso cada print sai num angulo diferente e
                // nao da' para comparar um ajuste com o outro.
                'sleep(0.5)', 'os.queueEvent("key", keys.space, false)', 'sleep(1.5)'],
    startctx: ['local _, H = mosaic.screenSize()',
               'os.queueEvent("mouse_click", 1, 3, H)', 'sleep(1)',
               'os.queueEvent("mouse_click", 2, 5, 5)', 'sleep(1.5)'],
  };
  // Abre pelo registry quando o app tem entrada la: e assim que o usuario abre, com o
  // titulo e o tamanho de janela certos. Sem isso o print mostrava "files" no lugar de
  // "Arquivos", e numa janela menor que a de verdade.
  const actions = special[arg] || (arg ? [
    'local r = mosaic.require("apps.registry")',
    `local a = r.byId("${arg}")`,
    `if a then r.open(a) else mosaic.launch("/os/apps/${arg}.lua") end`,
    'sleep(2)',
  ] : []);
  if (arg && !special[arg] && !fs.existsSync(path.join(ROOT, 'os', 'apps', `${arg}.lua`))) {
    console.error(`nao existe os/apps/${arg}.lua`);
    process.exit(2);
  }
  // `web` fala com o relay de verdade, entao precisa do IP local liberado e do relay no ar.
  const precisaRelay = arg === 'web' || arg === 'webbusca';
  const file = bootAndShoot(actions, arg ? 2 : 3, positional[1], precisaRelay
    ? { http_blacklist: [], http_whitelist: ['*'], http_enable: true } : null);
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
