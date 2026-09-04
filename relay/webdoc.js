// HTML -> documento simples, para o computador do jogo so' ter que desenhar.
//
// Por que aqui e nao no Lua: um computador do CC tem 51 colunas, Lua 5.1 e um limite de 7
// segundos por passo. Os browsers antigos de CC tentaram interpretar HTML de dentro do jogo
// e o resultado documentado e' "bagunçado, sem imagem". O Node faz o trabalho sujo e manda
// blocos prontos.
//
// Formato de saida (chaves curtas de proposito: isso vira JSON e atravessa o websocket):
//
//   { url, titulo, blocos: [ { t, s, n } ], links: [ href, ... ], cortado: bool }
//
//   t = h1 h2 h3 p li quote code hr img
//   s = texto ja em ASCII, sem entidade e sem espaco sobrando
//   n = numero do link, quando o bloco inteiro e' um link
//
// Links dentro do texto viram marcador numerado: "clique [3] para ver". E' o jeito do lynx,
// e em 51 colunas ele ganha de qualquer alternativa - nao gasta cor, nao gasta linha, e da
// para escolher pelo teclado.
'use strict';

// Sem dependencia nova: o relay tem `ws` e mais nada, e um analisador de HTML de verdade
// (jsdom) custa dezenas de megabytes para um ganho que 51 colunas nao mostram.
const LIMITE_BLOCOS = 600;
const LIMITE_TEXTO = 4000;      // por bloco

const ENTIDADES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '-', mdash: '-',
  lsquo: "'", rsquo: "'", ldquo: '"', rdquo: '"', hellip: '...', middot: '-', bull: '-',
  copy: '(c)', reg: '(R)', trade: '(TM)', deg: 'o', laquo: '"', raquo: '"', times: 'x',
};

function decodeEntities(s) {
  return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);?/g, (todo, corpo) => {
    if (corpo[0] === '#') {
      const cod = corpo[1] === 'x' || corpo[1] === 'X'
        ? parseInt(corpo.slice(2), 16) : parseInt(corpo.slice(1), 10);
      if (!Number.isFinite(cod) || cod < 0 || cod > 0x10ffff) return todo;
      try { return String.fromCodePoint(cod); } catch (_) { return todo; }
    }
    const v = ENTIDADES[corpo.toLowerCase()];
    if (v !== undefined) return v;
    // As entidades de letra acentuada sao dezenas (&aacute; &ccedil; &otilde; ...) e nao
    // vale a pena listar uma por uma: o padrao e' sempre letra + nome do acento, e como
    // tudo vai virar ASCII adiante, a letra sozinha ja e' a resposta certa.
    const acentuada = corpo.match(/^([a-zA-Z])(acute|grave|circ|tilde|uml|ring|cedil|slash|lig)$/);
    if (acentuada) return acentuada[1];
    return todo;
  });
}

// O terminal do CC desenha byte a byte, sem UTF-8: "coração" sai como lixo na tela. Por isso
// o proprio OS escreve PT-BR sem acento. Tirar o acento aqui e' o que faz uma pagina em
// portugues ficar legivel no jogo.
const AVULSOS = {
  '—': '-', '–': '-', '‘': "'", '’': "'", '“': '"', '”': '"',
  '…': '...', ' ': ' ', '•': '-', '«': '"', '»': '"',
  '×': 'x', '€': 'EUR', '£': 'GBP', '→': '->', '←': '<-',
};

// Escapes em vez dos caracteres literais: este arquivo passa por editor, git e terminal do
// Windows, e um traco longo trocado por outro byte no caminho quebraria calado.
const RE_AVULSOS = /[—–‘’“”… •«»×€£→←]/g;

function asciify(s) {
  let out = s.replace(RE_AVULSOS, (c) => AVULSOS[c] || "?");
  // NFD separa a letra do acento; U+0300..U+036F sao os acentos ja soltos.
  out = out.normalize("NFD").replace(/[̀-ͯ]/g, "");
  // O que sobrou fora do ASCII imprimivel nao tem como ser desenhado: vira ?.
  return out.replace(/[^\x20-\x7e\n]/g, '?');
}

function limpa(s) {
  return asciify(decodeEntities(s)).replace(/[ \t\r\n]+/g, ' ').trim();
}

// Tira o que nunca vira texto. O <head> sai junto, menos o <title>, que e' lido antes.
function removeRuido(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(script|style|noscript|svg|canvas|template|iframe|form|select)\b[\s\S]*?<\/\1\s*>/gi, ' ')
    .replace(/<(script|style|noscript|svg|canvas|template|iframe|form|select)\b[^>]*\/?>/gi, ' ')
    .replace(/<\/?(header|footer|nav|aside)\b[^>]*>/gi, ' ');
}

function tituloDe(html) {
  const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return m ? limpa(m[1]).slice(0, 120) : '';
}

// Extrai o elemento que comeca em `abre`, contando aninhamento. Sem isto nao da para pegar
// um <div>: o `[\s\S]*?</div>` para no primeiro fechamento, que quase sempre e' de um filho.
function extraiElemento(html, tag, abre, fimDaAbertura) {
  const re = new RegExp(`<(/?)${tag}\\b[^>]*>`, 'gi');
  re.lastIndex = fimDaAbertura;
  let nivel = 1;
  let m;
  while ((m = re.exec(html)) !== null) {
    nivel += m[1] === '/' ? -1 : 1;
    if (nivel === 0) return html.slice(fimDaAbertura, m.index);
  }
  return html.slice(fimDaAbertura);   // documento truncado: fica o que veio
}

function tamanhoTexto(h) {
  return h.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim().length;
}

// Nomes que a web usa para "aqui esta o artigo". Nao e' adivinhacao: sao os que aparecem em
// MediaWiki, WordPress e nos principais sites de noticia.
const RE_CONTEUDO = /\b(?:id|class)\s*=\s*["'][^"']*(mw-content-text|entry-content|post-content|article-?body|story-?body|articleBody|main-content|content__article|postArticle)/i;
const MAX_CANDIDATOS = 25;

// Onde esta o texto de verdade.
//
// Medido numa pagina de verdade: a Wikipedia poe o seletor de 143 idiomas DENTRO do <main>,
// entao ficar so' no <main> enche o documento de menu. O artigo mesmo esta num <div> mais
// fundo. Dai a regra: entre os candidatos, o maior em texto ganha - mas se um candidato
// dentro dele guarda quase o mesmo texto, ele ganha, porque so' perdeu a moldura.
function corpoDe(html) {
  const candidatos = [];
  const re = /<(main|article|section|div)\b([^>]*)>/gi;
  let m;
  while ((m = re.exec(html)) !== null && candidatos.length < MAX_CANDIDATOS) {
    const tag = m[1].toLowerCase();
    const eForte = tag === 'main' || tag === 'article';
    if (!eForte && !RE_CONTEUDO.test(m[2] || '')) continue;
    const corpo = extraiElemento(html, tag, m.index, re.lastIndex);
    const len = tamanhoTexto(corpo);
    if (len > 200) candidatos.push({ corpo, len, ini: m.index, tam: corpo.length });
  }
  if (candidatos.length === 0) {
    const b = html.match(/<body\b[^>]*>([\s\S]*)<\/body\s*>/i);
    return b ? b[1] : html;
  }
  candidatos.sort((a, b) => b.len - a.len);
  let melhor = candidatos[0];
  // Desce enquanto o de dentro guardar 60% do texto: e' o que tira menu e rodape sem
  // arriscar cortar o artigo no meio.
  for (let volta = 0; volta < 3; volta++) {
    const dentro = candidatos.find((c) => c !== melhor && c.tam < melhor.tam
      && c.ini >= melhor.ini && c.ini < melhor.ini + melhor.tam && c.len >= melhor.len * 0.6);
    if (!dentro) break;
    melhor = dentro;
  }
  return melhor.corpo;
}

// Link sem texto (icone, imagem clicavel) precisa de um nome, e a URL inteira nao serve:
// numa tela de 51 colunas ela ocupa tres linhas e nao diz nada. O ultimo pedaco do caminho
// costuma ser o assunto; sem caminho, fica o dominio.
function rotuloDeUrl(href) {
  if (!href) return '';
  try {
    const u = new URL(href);
    const partes = u.pathname.split('/').filter(Boolean);
    const ultima = partes.length ? decodeURIComponent(partes[partes.length - 1]) : '';
    return limpa(ultima.replace(/\.[a-z0-9]{1,5}$/i, '').replace(/[_-]+/g, ' ')).slice(0, 40)
      || u.hostname.replace(/^www\./, '');
  } catch (_) { return ''; }
}

function resolveUrl(href, base) {
  if (!href) return null;
  try { return new URL(href, base).toString(); } catch (_) { return null; }
}

const BLOCO = {
  h1: 'h1', h2: 'h2', h3: 'h3', h4: 'h3', h5: 'h3', h6: 'h3',
  p: 'p', li: 'li', dt: 'h3', dd: 'p', blockquote: 'quote', pre: 'code', figcaption: 'p',
  tr: 'p', div: 'p', section: 'p',
};

function parse(html, url) {
  const bruto = removeRuido(html);
  const titulo = tituloDe(html);
  const corpo = corpoDe(bruto);

  const blocos = [];
  const links = [];
  let buf = '';
  let tipo = 'p';
  let emLink = null;
  let cortado = false;

  // Texto que nao vai dar para ler no jogo. Medido numa pagina de verdade: a Wikipedia poe o
  // seletor de 143 idiomas dentro do <main>, e cada nome em alfabeto nao latino vira uma
  // linha de '?' na tela. Sem este filtro, metade do documento e' isso.
  function ilegivel(s) {
    const interrogacoes = (s.match(/\?/g) || []).length;
    if (interrogacoes > 0 && interrogacoes / s.length > 0.4) return true;
    // Bloco sem nenhuma letra nem numero e' enfeite: separador, icone, seta.
    return !/[a-zA-Z0-9]/.test(s);
  }

  function flush() {
    const s = limpa(buf);
    buf = '';
    if (!s) return;
    if (ilegivel(s)) { tipo = 'p'; return; }
    if (blocos.length >= LIMITE_BLOCOS) { cortado = true; return; }
    const b = { t: tipo, s: s.slice(0, LIMITE_TEXTO) };
    // Bloco que e' so' um link (item de menu, resultado de busca) ganha o numero solto, para
    // o app poder abrir sem a pessoa ter que achar o marcador no meio do texto.
    const so = s.match(/^\[(\d+)\]$|^(.*?)\s*\[(\d+)\]$/);
    if (so) {
      const n = Number(so[1] || so[3]);
      if (n) { b.n = n; b.s = (so[2] || '').trim() || rotuloDeUrl(links[n - 1]) || s; }
    }
    blocos.push(b);
    tipo = 'p';
  }

  // Tokenizador simples: alterna entre texto e tag. Nao trata HTML malformado como um
  // navegador trataria - trata como o que e', uma sequencia de marcas.
  const re = /<\/?([a-zA-Z][a-zA-Z0-9]*)((?:"[^"]*"|'[^']*'|[^'">])*)>/g;
  let pos = 0;
  let m;
  while ((m = re.exec(corpo)) !== null) {
    buf += corpo.slice(pos, m.index);
    pos = re.lastIndex;
    const fecha = m[0][1] === '/';
    const tag = m[1].toLowerCase();
    const attrs = m[2] || '';

    if (tag === 'br') { flush(); continue; }
    if (tag === 'hr') { flush(); if (blocos.length < LIMITE_BLOCOS) blocos.push({ t: 'hr', s: '' }); continue; }

    if (tag === 'img' && !fecha) {
      const alt = (attrs.match(/\balt\s*=\s*"([^"]*)"/i) || attrs.match(/\balt\s*=\s*'([^']*)'/i) || [])[1];
      const src = resolveUrl((attrs.match(/\bsrc\s*=\s*"([^"]*)"/i) || attrs.match(/\bsrc\s*=\s*'([^']*)'/i) || [])[1], url);
      if (src) {
        flush();
        if (blocos.length < LIMITE_BLOCOS) blocos.push({ t: 'img', s: limpa(alt || 'imagem'), src });
      }
      continue;
    }

    if (tag === 'a') {
      if (!fecha) {
        const href = resolveUrl(
          (attrs.match(/\bhref\s*=\s*"([^"]*)"/i) || attrs.match(/\bhref\s*=\s*'([^']*)'/i) || [])[1], url);
        // Ancora interna e javascript: nao levam a lugar nenhum no jogo.
        if (href && /^https?:/i.test(href)) {
          links.push(href);
          emLink = links.length;
        }
      } else if (emLink) {
        buf += ` [${emLink}]`;
        emLink = null;
      }
      continue;
    }

    const b = BLOCO[tag];
    if (b) {
      flush();
      if (!fecha) tipo = b;
      // div e section abrem bloco mas nao mudam o tipo: sao caixa, nao texto.
      if (!fecha && (tag === 'div' || tag === 'section' || tag === 'tr')) tipo = 'p';
    }
  }
  buf += corpo.slice(pos);
  flush();

  return { url, titulo, blocos, links, cortado };
}

// Resultado de busca do DuckDuckGo (endpoint html, sem chave). E' raspagem: se eles mudarem
// o HTML isso quebra, e o app tem que dizer isso em vez de mostrar tela vazia.
function parseBusca(html, termo) {
  const blocos = [{ t: 'h1', s: 'Busca: ' + asciify(termo) }];
  const links = [];
  const vistos = {};

  // Le as ancoras direto, sem passar pelo parse() de pagina. Motivo: o parse agrupa texto
  // ate' achar uma marca de bloco, e uma lista de resultados sem <div> entre eles viraria um
  // paragrafo so' com todos os titulos grudados. Aqui a unidade e' a ancora, que e' o que um
  // resultado de busca realmente e'.
  const re = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = (m[1].match(/\bhref\s*=\s*"([^"]*)"/i) || m[1].match(/\bhref\s*=\s*'([^']*)'/i) || [])[1];
    if (!href) continue;
    // O DuckDuckGo embrulha o destino em /l/?uddg=<url>
    let real = href;
    const u = href.match(/[?&]uddg=([^&]+)/);
    if (u) { try { real = decodeURIComponent(u[1]); } catch (_) { /* fica o embrulho */ } }
    if (!/^https?:/i.test(real)) continue;
    if (/(^https?:\/\/)?([^/]*\.)?duckduckgo\.com/i.test(real)) continue;
    if (vistos[real]) continue;
    const titulo = limpa(m[2].replace(/<[^>]*>/g, ' '));
    if (!titulo) continue;
    vistos[real] = true;
    links.push(real);
    blocos.push({ t: 'li', s: titulo, n: links.length });
  }
  if (links.length === 0) {
    blocos.push({ t: 'p', s: 'Nenhum resultado. A busca e raspagem de HTML: pode ter mudado do outro lado.' });
  }
  return { url: 'busca:' + termo, titulo: 'Busca: ' + asciify(termo), blocos, links, cortado: false };
}

module.exports = { parse, parseBusca, asciify, decodeEntities, limpa, tituloDe, corpoDe };
