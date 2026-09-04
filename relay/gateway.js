// Porta de entrada do Mosaic para a internet.
//
// O computador do jogo nao fala com o site: ele fala com o relay, e o relay traz a pagina ja
// mastigada. Nao e' preferencia, e' o que a plataforma permite - o CC:T tem limite de 7
// segundos por passo, Lua 5.1, 51 colunas e nenhum analisador de HTML.
'use strict';
const webdoc = require('./webdoc.js');

const MAX_BYTES = 3 * 1024 * 1024;      // pagina maior que isso e' anuncio, nao texto
const TIMEOUT_MS = 15000;
const CACHE_MAX = 30;
const CACHE_MS = 5 * 60 * 1000;
const UA = 'Mozilla/5.0 (compatible; MosaicOS/1.0; +CC:Tweaked)';

// Cache pequeno e por tempo. Serve para o "voltar" do browser nao pagar a pagina de novo, e
// para uma pagina aberta em dois computadores custar um download so'.
const cache = new Map();

function doCache(chave) {
  const e = cache.get(chave);
  if (!e) return null;
  if (Date.now() - e.quando > CACHE_MS) { cache.delete(chave); return null; }
  return e.valor;
}

function poeCache(chave, valor) {
  cache.set(chave, { quando: Date.now(), valor });
  // Map guarda a ordem de insercao: o primeiro e' o mais velho.
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
}

function limpaCache() { cache.clear(); }

// Faixas que nao podem ser alcancadas de dentro do jogo.
//
// O relay roda na maquina de quem joga, e o token o protege de fora - mas um computador do
// servidor pedindo http://192.168.0.1/ transformaria o relay num tunel para a rede de casa.
// Isto e' bloqueio por IP literal; um nome que RESOLVE para endereco privado passa, e por
// isso o relay nao deve ser exposto a quem voce nao conhece.
const PRIVADOS = [
  /^127\./, /^10\./, /^192\.168\./, /^169\.254\./, /^0\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
];

function urlPermitida(bruta) {
  let u;
  try { u = new URL(bruta); } catch (_) { return { ok: false, erro: 'endereco invalido' }; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') {
    return { ok: false, erro: 'so http e https' };
  }
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (h === 'localhost' || h === '::1' || h.endsWith('.localhost')) {
    return { ok: false, erro: 'endereco local bloqueado' };
  }
  if (/^\d+\.\d+\.\d+\.\d+$/.test(h) && PRIVADOS.some((re) => re.test(h))) {
    return { ok: false, erro: 'endereco de rede local bloqueado' };
  }
  return { ok: true, url: u.toString() };
}

// Baixa com teto de tamanho de verdade: `await r.text()` leria os 300 MB de um arquivo que
// se diz HTML antes de alguem reclamar.
async function baixa(url, aceita) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(url, {
      redirect: 'follow',
      signal: ctrl.signal,
      headers: { 'User-Agent': UA, Accept: aceita || 'text/html,*/*' },
    });
    const tipo = (r.headers.get('content-type') || '').toLowerCase();
    const partes = [];
    let total = 0;
    let cortado = false;
    if (r.body) {
      for await (const pedaco of r.body) {
        total += pedaco.length;
        if (total > MAX_BYTES) { cortado = true; break; }
        partes.push(pedaco);
      }
    }
    return { status: r.status, url: r.url, tipo, corpo: Buffer.concat(partes), cortado };
  } finally {
    clearTimeout(t);
  }
}

async function pagina(bruta) {
  const v = urlPermitida(bruta);
  if (!v.ok) return { erro: v.erro };

  const doCachePronto = doCache('p:' + v.url);
  if (doCachePronto) return doCachePronto;

  let r;
  try {
    r = await baixa(v.url);
  } catch (e) {
    const msg = e && e.name === 'AbortError' ? 'o site demorou demais' : (e && e.message) || 'falhou';
    return { erro: msg };
  }
  if (r.status >= 400) return { erro: 'o site respondeu ' + r.status, status: r.status };

  // Nem tudo e' HTML. Texto puro vira um bloco de codigo, que e' como se le melhor num
  // terminal; o resto (imagem, zip, pdf) nao tem como ser mostrado e diz isso.
  if (r.tipo && !/text\/html|application\/xhtml/.test(r.tipo)) {
    if (/^text\/|json|xml|javascript/.test(r.tipo)) {
      const texto = webdoc.asciify(r.corpo.toString('utf8'));
      const doc = {
        url: r.url, titulo: r.url.split('/').pop() || r.url, links: [], cortado: r.cortado,
        blocos: texto.split(/\n/).slice(0, 600).map((l) => ({ t: 'code', s: l })),
      };
      poeCache('p:' + v.url, doc);
      return doc;
    }
    return { erro: 'nao e pagina nem texto: ' + r.tipo };
  }

  const doc = webdoc.parse(r.corpo.toString('utf8'), r.url);
  doc.cortado = doc.cortado || r.cortado;
  poeCache('p:' + v.url, doc);
  return doc;
}

// Busca. O DuckDuckGo tem um endpoint HTML sem chave, que e' o que da para usar sem cadastro
// e sem cota. E' RASPAGEM: se eles mudarem o HTML, isto para de achar resultado - e o
// webdoc.parseBusca devolve uma linha dizendo isso, em vez de uma tela vazia sem explicacao.
async function busca(termo) {
  const t = String(termo || '').trim();
  if (!t) return { erro: 'busca vazia' };

  const pronto = doCache('b:' + t);
  if (pronto) return pronto;

  let r;
  try {
    r = await baixa('https://html.duckduckgo.com/html/?q=' + encodeURIComponent(t));
  } catch (e) {
    const msg = e && e.name === 'AbortError' ? 'a busca demorou demais' : (e && e.message) || 'falhou';
    return { erro: msg };
  }
  if (r.status >= 400) return { erro: 'a busca respondeu ' + r.status };

  const doc = webdoc.parseBusca(r.corpo.toString('utf8'), t);
  poeCache('b:' + t, doc);
  return doc;
}

module.exports = { pagina, busca, urlPermitida, limpaCache, MAX_BYTES };
