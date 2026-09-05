// Musica: do link ate' o bloco de DFPWM que o alto-falante do jogo toca.
//
// Cadeia: yt-dlp busca e baixa o audio, ffmpeg converte para DFPWM, e o relay serve o
// arquivo em pedacos de 16 KiB. O tamanho do pedaco nao e' escolha: o DFPWM gasta 1 bit por
// amostra e o `speaker.playAudio` do CC aceita no maximo 128*1024 amostras por chamada, que
// dao exatamente 16*1024 bytes - ~2,7 s de som.
//
// Medido no CraftOS-PC: decodificar um pedaco desses custa 38 ms no computador do jogo, ou
// ~1,4% de CPU enquanto toca. Por isso o pedaco inteiro vai de uma vez, sem picar.
'use strict';
const { spawn, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CACHE_DIR = process.env.MOSAIC_CACHE || path.join(__dirname, 'cache');
const BLOCO = 16 * 1024;
const TAXA = 48000;
const MAX_SEGUNDOS = parseInt(process.env.MOSAIC_MAX_SEGUNDOS || '1800', 10);

// yt-dlp e ffmpeg sao programas de fora, e podem simplesmente nao estar instalados. O relay
// nao morre por isso: as outras rotas continuam de pe' e esta aqui diz o que falta.
let deps = null;

function versao(cmd, args) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: 8000, windowsHide: true }, (err, stdout) => {
      resolve(err ? null : String(stdout).split('\n')[0].trim().slice(0, 60));
    });
  });
}

async function dependencias(recarrega) {
  if (deps && !recarrega) return deps;
  const [ytdlp, ffmpeg] = await Promise.all([
    versao('yt-dlp', ['--version']),
    versao('ffmpeg', ['-version']),
  ]);
  deps = {
    ytdlp, ffmpeg,
    ok: Boolean(ytdlp && ffmpeg),
    falta: [!ytdlp && 'yt-dlp', !ffmpeg && 'ffmpeg'].filter(Boolean),
  };
  return deps;
}

function erroDeps(d) {
  return {
    erro: 'falta instalar ' + d.falta.join(' e ') + ' no computador que roda o relay',
    falta: d.falta,
  };
}

// O YouTube recusa o download conforme o "cliente" que o yt-dlp finge ser, e qual funciona
// muda com o tempo. Medido nesta maquina em 04/09/2026: o padrao e o `tv` e `ios` deram
// HTTP 403; `web_safari` e `mweb` baixaram. Passar a lista faz o yt-dlp tentar em ordem.
//
// Se um dia parar tudo de novo, o conserto e' esta variavel - nao o codigo:
//   MOSAIC_YT_CLIENTS=default,web_safari,mweb,tv node relay.js
// Um cliente POR TENTATIVA, e nao os tres numa lista separada por virgula: a lista deixa o
// yt-dlp escolher o formato com um cliente e baixar com outro, e ai o 403 volta. Medido: a
// lista falhou onde `web_safari` sozinho funcionou.
const YT_CLIENTS = (process.env.MOSAIC_YT_CLIENTS || 'web_safari,mweb,default').split(',');
const argsCliente = (cli) => ['--extractor-args', 'youtube:player_client=' + cli];

// O YouTube esconde o endereco do audio atras de um desafio em JavaScript, e o yt-dlp
// precisa de um interpretador para resolver. Sem um, a BUSCA funciona e o titulo aparece -
// so' o download falha, com HTTP 403. O erro aponta para o lugar errado: a caca vai parar
// nos player_client, que nao tem nada a ver.
//
// O yt-dlp so' liga o deno sozinho, e mandar instalar deno seria pedir um programa a mais
// para cada pessoa que for rodar o relay. Mas o relay JA' e' node - e node serve de runtime.
// process.execPath e' o node que esta rodando isto agora, entao nao ha o que instalar nem
// PATH para acertar. Conferido em 05/09/2026, inclusive com o caminho do Windows: o yt-dlp
// corta o RUNTIME:PATH no primeiro dois-pontos, e "C:\..." passa inteiro.
const ARGS_JS = ['--js-runtimes', 'node:' + process.execPath];

function idDe(q) { return crypto.createHash('sha1').update(q).digest('hex').slice(0, 16); }
function arquivoDe(id) { return path.join(CACHE_DIR, id + '.dfpwm'); }
function metaDe(id) { return path.join(CACHE_DIR, id + '.json'); }

function corre(cmd, args, opts) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { windowsHide: true, ...opts });
    let out = '', err = '';
    if (p.stdout) p.stdout.on('data', (d) => { out += d; });
    if (p.stderr) p.stderr.on('data', (d) => { if (err.length < 8000) err += d; });
    p.on('error', reject);
    p.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(err.trim().split('\n').pop() || (cmd + ' saiu ' + code)))));
  });
}

// Aceita link ou termo de busca. `ytsearch1:` faz o yt-dlp buscar e pegar o primeiro, que e'
// o que um bot de musica faz quando voce digita o nome em vez de colar o endereco.
function alvoDe(q) {
  const t = String(q || '').trim();
  if (!t) return null;
  return /^https?:\/\//i.test(t) ? t : 'ytsearch1:' + t;
}

// Trabalhos em andamento: id -> { estado, titulo, erro }.
//
// Preparar uma musica leva de 20 a 60 segundos (medido: 21 s so' para o yt-dlp achar), e uma
// requisicao HTTP do CC:T morre em 30. Entao o pedido NAO espera: dispara, responde
// "preparando" na hora, e o app pergunta de novo. Quando fica pronto, a mesma pergunta
// devolve a musica.
const trabalhos = new Map();

function metaPronta(id) {
  if (!fs.existsSync(arquivoDe(id)) || !fs.existsSync(metaDe(id))) return null;
  try {
    const meta = JSON.parse(fs.readFileSync(metaDe(id), 'utf8'));
    meta.blocos = Math.ceil(fs.statSync(arquivoDe(id)).size / BLOCO);
    meta.estado = 'pronto';
    return meta;
  } catch (_) { return null; }
}

// Acha o arquivo que o yt-dlp acabou de gravar. O nome traz a extensao do formato que ele
// escolheu (webm, m4a, opus...), que so' se sabe depois.
function achaBaixado(id) {
  for (const nome of fs.readdirSync(CACHE_DIR)) {
    if (nome.startsWith(id + '.dl.')) return path.join(CACHE_DIR, nome);
  }
  return null;
}

async function prepara(id, alvo) {
  const job = trabalhos.get(id);
  fs.mkdirSync(CACHE_DIR, { recursive: true });

  let info;
  try {
    // A consulta vai com o cliente PADRAO. Fixar um cliente aqui quebrou com "Requested
    // format is not available": nem todo cliente enxerga todos os formatos, e para achar o
    // video e ler titulo e duracao o padrao e' o que ve mais. Quem varia e' o download.
    const bruto = await corre('yt-dlp',
      ['--dump-single-json', '--no-playlist', '--no-warnings', ...ARGS_JS, alvo]);
    info = JSON.parse(bruto);
    if (info.entries && info.entries.length) info = info.entries[0];
  } catch (e) {
    job.estado = 'erro'; job.erro = 'yt-dlp nao achou: ' + e.message;
    return;
  }

  job.titulo = String(info.title || '').slice(0, 120);
  const duracao = Math.round(Number(info.duration) || 0);
  if (duracao > MAX_SEGUNDOS) {
    job.estado = 'erro';
    job.erro = 'longo demais (' + Math.round(duracao / 60) + ' min); o teto e ' + Math.round(MAX_SEGUNDOS / 60);
    return;
  }

  // Baixar pelo endereco concreto, e nao pelo `ytsearch1:` de novo: buscar duas vezes gasta
  // mais 20 segundos e pode cair num video diferente do que foi anunciado.
  const concreto = info.webpage_url || info.original_url || alvo;
  const destino = arquivoDe(id);
  const parcial = destino + '.parcial';
  let baixado = null;
  try {
    job.estado = 'baixando';
    // Arquivo intermediario em vez de cano: o `-o -` do yt-dlp entrega formato fragmentado,
    // e o ffmpeg nao le isso de um cano sem busca ("Invalid data found when processing
    // input"). Medido, nao suposto - foi assim que a primeira versao falhou.
    // Cada cliente e' uma tentativa inteira. Qual funciona muda com o tempo, e o YouTube
    // devolve 403 no download (nao na consulta), entao so' da para saber tentando.
    let ultimo;
    for (const cli of YT_CLIENTS) {
      try {
        await corre('yt-dlp', ['-f', 'bestaudio/best', '--no-playlist', '--no-warnings', '--quiet',
          '-o', path.join(CACHE_DIR, id + '.dl.%(ext)s'), ...ARGS_JS, ...argsCliente(cli), concreto]);
        baixado = achaBaixado(id);
        if (baixado) break;
        ultimo = new Error('o yt-dlp nao deixou arquivo (cliente ' + cli + ')');
      } catch (e) {
        ultimo = e;
        // Limpa a sobra parcial antes da proxima tentativa, senao o achaBaixado acha lixo.
        const meio = achaBaixado(id);
        if (meio) { try { fs.unlinkSync(meio); } catch (_) { /* ja foi */ } }
      }
    }
    if (!baixado) throw ultimo || new Error('nenhum cliente do YouTube funcionou');

    job.estado = 'convertendo';
    // DFPWM e' 1 bit por amostra, mono, 48 kHz - o que o alto-falante do CC toca. O ffmpeg
    // ganhou o formato na 5.1; versao mais velha falha aqui e a mensagem sobe para o app.
    await corre('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', baixado,
      '-ac', '1', '-ar', String(TAXA), '-f', 'dfpwm', '-y', parcial]);
    fs.renameSync(parcial, destino);
  } catch (e) {
    try { fs.unlinkSync(parcial); } catch (_) { /* nao existia */ }
    job.estado = 'erro'; job.erro = 'conversao falhou: ' + e.message;
    return;
  } finally {
    if (baixado) { try { fs.unlinkSync(baixado); } catch (_) { /* ja foi */ } }
  }

  const tamanho = fs.statSync(destino).size;
  const meta = {
    id,
    titulo: job.titulo || 'sem titulo',
    autor: String(info.uploader || info.channel || '').slice(0, 80),
    duracao: duracao || Math.round((tamanho * 8) / TAXA),
    bytes: tamanho,
    blocos: Math.ceil(tamanho / BLOCO),
  };
  fs.writeFileSync(metaDe(id), JSON.stringify(meta));
  job.estado = 'pronto';
}

async function resolve(q) {
  const d = await dependencias();
  if (!d.ok) return erroDeps(d);

  const alvo = alvoDe(q);
  if (!alvo) return { erro: 'pedido vazio' };
  const id = idDe(alvo);

  // Ja convertido antes: nao paga download nem conversao de novo.
  const pronta = metaPronta(id);
  if (pronta) { trabalhos.delete(id); return pronta; }

  const job = trabalhos.get(id);
  if (job) {
    if (job.estado === 'erro') { trabalhos.delete(id); return { erro: job.erro }; }
    return { id, estado: job.estado, titulo: job.titulo || '', espere: true };
  }

  const novo = { estado: 'buscando', titulo: '', erro: null, quando: Date.now() };
  trabalhos.set(id, novo);
  // Solta o trabalho e responde na hora. O `catch` existe porque um erro nao capturado aqui
  // derrubaria o relay inteiro, e nao so' esta musica.
  prepara(id, alvo).catch((e) => { novo.estado = 'erro'; novo.erro = String((e && e.message) || e); });
  return { id, estado: 'buscando', titulo: '', espere: true };
}

// O enesimo pedaco, contando de 1. Devolve null quando acabou - e' assim que o app sabe que
// a musica terminou, sem precisar confiar na duracao anunciada.
function bloco(id, n) {
  if (!/^[0-9a-f]{16}$/.test(String(id))) return null;
  const arq = arquivoDe(id);
  if (!fs.existsSync(arq)) return null;
  const inicio = (n - 1) * BLOCO;
  const tamanho = fs.statSync(arq).size;
  if (n < 1 || inicio >= tamanho) return null;
  const fd = fs.openSync(arq, 'r');
  try {
    const buf = Buffer.alloc(Math.min(BLOCO, tamanho - inicio));
    fs.readSync(fd, buf, 0, buf.length, inicio);
    return buf;
  } finally {
    fs.closeSync(fd);
  }
}

module.exports = { resolve, bloco, dependencias, BLOCO, TAXA, CACHE_DIR };
