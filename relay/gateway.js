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

// A politica e' conferida no IP usado pelo socket, inclusive apos cada redirect.
const dns = require('dns');
const net = require('net');
const http = require('http');
const https = require('https');
function ipPublico(ip) {
  if (net.isIP(ip) === 6) return /^[23][0-9a-f]{3}:/i.test(ip) && !/^200[12]:/i.test(ip);
  if (net.isIP(ip) !== 4) return false;
  const [a,b] = ip.split('.').map(Number);
  return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && [0,168].includes(b)) ||
    (a === 198 && [18,19].includes(b)));
}
function urlPermitida(bruta) {
  let u;
  try { u = new URL(bruta); } catch (_) { return { ok:false, erro:'endereco invalido' }; }
  if (!['http:','https:'].includes(u.protocol)) return { ok:false, erro:'so http e https' };
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g,'');
  if (u.username || u.password || h === 'localhost' || h.endsWith('.localhost') ||
      (net.isIP(h) && !ipPublico(h))) return { ok:false, erro:'endereco local bloqueado' };
  return { ok:true, url:u.toString() };
}
function lookupPublico(host, options, callback) {
  dns.lookup(host, {all:true}, (err, addresses) => {
    if (err) return callback(err);
    if (!addresses.length || addresses.some(a => !ipPublico(a.address)))
      return callback(new Error('endereco de rede local bloqueado'));
    if (options.all) callback(null, addresses);
    else callback(null, addresses[0].address, addresses[0].family);
  });
}
async function baixa(url, aceita) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    for (let hop=0; hop<6; hop++) {
      const valid = urlPermitida(url);
      if (!valid.ok) throw new Error(valid.erro);
      const r = await new Promise((resolve,reject) => {
        const transport = url.startsWith('https:') ? https : http;
        const req = transport.get(url, {signal:ctrl.signal, lookup:lookupPublico, agent:false,
          headers:{'User-Agent':UA, Accept:aceita || 'text/html,*/*', 'Accept-Encoding':'identity'}},resolve);
        req.on('error',reject);
      });
      if ([301,302,303,307,308].includes(r.statusCode) && r.headers.location) {
        r.destroy(); url = new URL(r.headers.location,url).toString(); continue;
      }
      const partes=[]; let total=0, cortado=false;
      for await (const pedaco of r) {
        total += pedaco.length;
        if (total > MAX_BYTES) { cortado=true; break; }
        partes.push(pedaco);
      }
      return {status:r.statusCode,url,tipo:(r.headers['content-type'] || '').toLowerCase(),
        corpo:Buffer.concat(partes),cortado};
    }
    throw new Error('redirecionamentos demais');
  } finally { clearTimeout(timer); }
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
