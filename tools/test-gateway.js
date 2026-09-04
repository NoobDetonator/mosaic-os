#!/usr/bin/env node
// Testa o lado do relay que olha para fora: o tradutor de HTML (relay/webdoc.js), o filtro
// de enderecos (relay/gateway.js) e a divisao do audio em pedacos (relay/musica.js).
//
// Roda SEM rede e SEM o relay ligado, de proposito: e' texto entrando e blocos saindo. O que
// ele cobre e' justamente o que quebra calado - acento que vira lixo na tela do CC, link que
// perde o numero, pagina com <main> vazio, e o pedaco de audio com um byte a mais ou a menos.
'use strict';
const webdoc = require('../relay/webdoc.js');

let falhas = 0, ok = 0;
function check(cond, msg) {
  if (cond) { ok++; } else { falhas++; console.log(' - ' + msg); }
}
function eq(a, b, msg) { check(a === b, msg + ' (veio: ' + JSON.stringify(a) + ')'); }

// ---------------------------------------------------------------- acentos
// A razao de existir desta funcao: o terminal do CC desenha byte a byte, sem UTF-8.
eq(webdoc.asciify('coracao ja e vovo'), 'coracao ja e vovo', 'ASCII puro nao pode mudar');
eq(webdoc.asciify('coração'), 'coracao', 'cedilha e til deviam sumir');
eq(webdoc.asciify('Júlio Álvares'), 'Julio Alvares', 'acento em maiuscula tambem');
eq(webdoc.asciify('a—b'), 'a-b', 'traco longo vira hifen');
eq(webdoc.asciify('“aspas”'), '"aspas"', 'aspas curvas viram retas');
eq(webdoc.asciify('a…b'), 'a...b', 'reticencias viram tres pontos');
eq(webdoc.asciify('中文'), '??', 'o que nao tem ASCII vira ?');

// ---------------------------------------------------------------- entidades
eq(webdoc.decodeEntities('a&amp;b'), 'a&b', '&amp;');
eq(webdoc.decodeEntities('&lt;tag&gt;'), '<tag>', '&lt; &gt;');
eq(webdoc.decodeEntities('&#65;&#x42;'), 'AB', 'entidade numerica, decimal e hexa');
eq(webdoc.decodeEntities('&naoexiste;'), '&naoexiste;', 'entidade desconhecida fica como esta');
eq(webdoc.limpa('  a\n\n   b  '), 'a b', 'espaco sobrando some');

// ---------------------------------------------------------------- pagina
const pagina = `<html><head><title>P&aacute;gina de Teste</title>
<style>body{color:red}</style><script>var x = "<p>nao sou texto</p>";</script></head>
<body><nav><a href="/menu">Menu</a></nav>
<h1>T&iacute;tulo</h1>
<p>Um par&aacute;grafo com <a href="/interno">link interno</a> e
<a href="https://exemplo.com/x">link externo</a>.</p>
<ul><li><a href="https://a.com">Primeiro</a></li><li>Sem link</li></ul>
<pre>codigo(1)</pre>
<img src="/foto.png" alt="uma foto">
<hr>
<p>Fim.</p></body></html>`;

const doc = webdoc.parse(pagina, 'https://site.com/pag');
eq(doc.titulo, 'Pagina de Teste', 'titulo com entidade e acento');

const texto = doc.blocos.map((b) => b.t + ':' + b.s).join('\n');
check(!texto.includes('nao sou texto'), 'conteudo de <script> vazou para o texto');
check(!texto.includes('color:red'), 'conteudo de <style> vazou para o texto');
check(doc.blocos.some((b) => b.t === 'h1' && b.s === 'Titulo'), 'faltou o h1 sem acento');
check(doc.blocos.some((b) => b.t === 'code' && b.s === 'codigo(1)'), 'faltou o bloco de codigo');
check(doc.blocos.some((b) => b.t === 'hr'), 'faltou a linha horizontal');

// Link relativo vira absoluto, e ganha numero.
check(doc.links.includes('https://site.com/interno'), 'link relativo nao virou absoluto');
check(doc.links.includes('https://exemplo.com/x'), 'faltou o link externo');
const par = doc.blocos.find((b) => b.s.startsWith('Um paragrafo'));
check(par && /\[\d+\]/.test(par.s), 'o paragrafo perdeu o marcador de link');

// Item de lista que e' so' um link ganha o numero solto, para dar para abrir direto.
// A URL sai normalizada pelo `new URL` (dominio nu ganha a barra final): e' o que se quer,
// porque e' assim que ela vai ser pedida depois.
const item = doc.blocos.find((b) => b.s === 'Primeiro');
check(item && item.n && doc.links[item.n - 1] === 'https://a.com/',
  'o item que e so um link nao ganhou numero proprio');

// Imagem vira bloco com a origem resolvida.
const img = doc.blocos.find((b) => b.t === 'img');
check(img && img.src === 'https://site.com/foto.png', 'a imagem perdeu a origem absoluta');
check(img && img.s === 'uma foto', 'a imagem perdeu o texto alternativo');

// ---------------------------------------------------------------- corpo
// <main> com pouco texto e armadilha comum: a pagina poe um <main> vazio e o texto fora.
const vazio = '<html><body><main><div></div></main><p>' + 'x'.repeat(400) + '</p></body></html>';
check(webdoc.parse(vazio, 'http://a').blocos.length > 0, '<main> vazio escondeu a pagina toda');

const comMain = '<html><body><p>ruido</p><main><p>' + 'y'.repeat(400) + '</p></main></body></html>';
const dm = webdoc.parse(comMain, 'http://a');
check(!dm.blocos.some((b) => b.s === 'ruido'), '<main> com conteudo deveria excluir o resto');

// Sem body nenhum tambem nao pode quebrar.
check(webdoc.parse('<p>solto</p>', 'http://a').blocos.length === 1, 'html sem body quebrou');
check(webdoc.parse('', 'http://a').blocos.length === 0, 'html vazio quebrou');

// ---------------------------------------------------------------- busca
const buscaHtml = `<html><body>
<a class="result__a" href="/l/?uddg=https%3A%2F%2Fdestino.com%2Fpag">Resultado Um</a>
<a class="result__a" href="/l/?uddg=https%3A%2F%2Foutro.org%2F">Resultado Dois</a>
<a href="https://duckduckgo.com/interno">nao conta</a>
</body></html>`;
const busca = webdoc.parseBusca(buscaHtml, 'teste');
eq(busca.links.length, 2, 'a busca devia achar dois resultados');
eq(busca.links[0], 'https://destino.com/pag', 'o link do resultado nao foi desembrulhado');
check(busca.blocos.some((b) => b.s === 'Resultado Um' && b.n === 1),
  'o resultado perdeu o titulo ou o numero');

const vazia = webdoc.parseBusca('<html><body></body></html>', 'nada');
check(vazia.blocos.some((b) => b.s.includes('raspagem')),
  'busca sem resultado tem que dizer que e raspagem, nao ficar muda');

// ---------------------------------------------------------------- enderecos
// O relay roda na maquina de quem joga. Um computador do servidor pedindo 192.168.0.1
// transformaria o relay num tunel para a rede de casa.
const gateway = require('../relay/gateway.js');
for (const mau of ['http://127.0.0.1/', 'http://192.168.0.1/', 'http://10.0.0.5/',
  'http://172.16.0.1/', 'http://localhost:8080/', 'file:///etc/passwd', 'nao e url']) {
  check(!gateway.urlPermitida(mau).ok, 'devia bloquear ' + mau);
}
for (const bom of ['http://exemplo.com/', 'https://a.b.c/x?y=1', 'http://172.32.0.1/']) {
  check(gateway.urlPermitida(bom).ok, 'devia permitir ' + bom);
}

// ---------------------------------------------------------------- pedacos de audio
// A conta que faz o som nao estalar: DFPWM gasta 1 bit por amostra, o playAudio do CC aceita
// no maximo 128*1024 amostras, logo o pedaco e' de 16*1024 bytes. Se este teste quebrar, ou
// a musica passa a engasgar ou o alto-falante recusa o buffer.
const musica = require('../relay/musica.js');
const fsx = require('fs');
const pathx = require('path');

eq(musica.BLOCO, 16 * 1024, 'o pedaco tem que ser de 16 KiB');
eq(musica.BLOCO * 8, 128 * 1024, 'o pedaco tem que dar exatamente o maximo do playAudio');
eq(musica.TAXA, 48000, 'o alto-falante do CC toca a 48 kHz');

// Um arquivo de mentira, para exercitar a divisao sem precisar de yt-dlp nem ffmpeg (que
// nem sempre estao instalados). Dois pedacos e meio: cobre o comeco, o meio e a sobra.
fsx.mkdirSync(musica.CACHE_DIR, { recursive: true });
const idFalso = 'aaaaaaaaaaaaaaaa';
const arqFalso = pathx.join(musica.CACHE_DIR, idFalso + '.dfpwm');
const total = musica.BLOCO * 2 + 100;
const conteudo = Buffer.alloc(total);
for (let i = 0; i < total; i++) conteudo[i] = i % 256;
fsx.writeFileSync(arqFalso, conteudo);
try {
  const b1 = musica.bloco(idFalso, 1);
  const b2 = musica.bloco(idFalso, 2);
  const b3 = musica.bloco(idFalso, 3);
  eq(b1 && b1.length, musica.BLOCO, 'primeiro pedaco com tamanho errado');
  eq(b2 && b2.length, musica.BLOCO, 'segundo pedaco com tamanho errado');
  eq(b3 && b3.length, 100, 'o ultimo pedaco tem que ser so a sobra');
  check(b1[0] === 0 && b1[1] === 1, 'o primeiro pedaco nao comeca no inicio do arquivo');
  check(b2[0] === conteudo[musica.BLOCO], 'o segundo pedaco nao comeca onde o primeiro acabou');
  check(musica.bloco(idFalso, 4) === null, 'depois do fim tem que dar null, e e assim que o app sabe que acabou');
  check(musica.bloco(idFalso, 0) === null, 'pedaco zero nao existe (contagem comeca em 1)');
  // Id fora do formato nao pode virar caminho de arquivo.
  check(musica.bloco('../../etc/passwd', 1) === null, 'id invalido devia ser recusado');
  check(musica.bloco('nao-hexa', 1) === null, 'id fora do formato devia ser recusado');
} finally {
  fsx.unlinkSync(arqFalso);
}

console.log(`gateway: ${ok} ok, ${falhas} falhas`);
process.exit(falhas === 0 ? 0 : 1);
