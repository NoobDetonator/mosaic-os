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

async function resolve(q) {
  const d = await dependencias();
  if (!d.ok) return erroDeps(d);

  const alvo = alvoDe(q);
  if (!alvo) return { erro: 'pedido vazio' };

  const id = idDe(alvo);
  // Ja convertido antes: nao paga download nem conversao de novo.
  if (fs.existsSync(arquivoDe(id)) && fs.existsSync(metaDe(id))) {
    try {
      const meta = JSON.parse(fs.readFileSync(metaDe(id), 'utf8'));
      meta.blocos = Math.ceil(fs.statSync(arquivoDe(id)).size / BLOCO);
      return meta;
    } catch (_) { /* cache estragado: refaz */ }
  }

  let info;
  try {
    const bruto = await corre('yt-dlp', ['--dump-single-json', '--no-playlist', '--no-warnings', alvo]);
    info = JSON.parse(bruto);
    if (info.entries && info.entries.length) info = info.entries[0];
  } catch (e) {
    return { erro: 'yt-dlp nao achou: ' + e.message };
  }

  const duracao = Math.round(Number(info.duration) || 0);
  if (duracao > MAX_SEGUNDOS) {
    return { erro: 'longo demais (' + Math.round(duracao / 60) + ' min); o teto e ' + Math.round(MAX_SEGUNDOS / 60) };
  }

  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const destino = arquivoDe(id);
  const parcial = destino + '.parcial';
  try {
    // O audio sai do yt-dlp pela saida padrao e entra direto no ffmpeg: sem arquivo
    // intermediario de dezenas de MB no disco de quem joga.
    //
    // DFPWM e' 1 bit por amostra, mono, 48 kHz - e' o que o alto-falante do CC toca.
    // O ffmpeg ganhou o formato na 5.1; versao mais velha falha aqui, e a mensagem dele
    // sobe inteira para o app.
    const yt = spawn('yt-dlp', ['-f', 'bestaudio', '-o', '-', '--no-playlist', '--no-warnings', '--quiet', alvo],
      { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const ff = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', 'pipe:0',
      '-ac', '1', '-ar', String(TAXA), '-f', 'dfpwm', '-y', parcial],
      { windowsHide: true, stdio: ['pipe', 'ignore', 'pipe'] });
    yt.stdout.pipe(ff.stdin);
    let erroFf = '';
    ff.stderr.on('data', (b) => { if (erroFf.length < 4000) erroFf += b; });
    let erroYt = '';
    yt.stderr.on('data', (b) => { if (erroYt.length < 4000) erroYt += b; });

    await new Promise((ok, falhou) => {
      ff.on('error', falhou);
      yt.on('error', falhou);
      ff.on('close', (c) => (c === 0 ? ok() : falhou(new Error(erroFf.trim().split('\n').pop() || erroYt.trim().split('\n').pop() || ('ffmpeg saiu ' + c)))));
    });
    fs.renameSync(parcial, destino);
  } catch (e) {
    try { fs.unlinkSync(parcial); } catch (_) { /* nao existia */ }
    return { erro: 'conversao falhou: ' + e.message };
  }

  const tamanho = fs.statSync(destino).size;
  const meta = {
    id,
    titulo: String(info.title || 'sem titulo').slice(0, 120),
    autor: String(info.uploader || info.channel || '').slice(0, 80),
    duracao: duracao || Math.round((tamanho * 8) / TAXA),
    bytes: tamanho,
    blocos: Math.ceil(tamanho / BLOCO),
  };
  fs.writeFileSync(metaDe(id), JSON.stringify(meta));
  return meta;
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
