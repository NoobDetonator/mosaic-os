#!/usr/bin/env node
// Gera manifest.json: versão + lista de arquivos instaláveis (os/**, startup.lua) com sha1.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const version = fs.readFileSync(path.join(ROOT, 'os', 'version.lua'), 'utf8').match(/version\s*=\s*"([^"]+)"/)[1];

// os/var e' estado de execucao (seeded.json, logs), criado pelo boot no computador e
// gitignorado aqui. Sem pular, o manifest listava o log que por acaso estivesse na pasta:
// o arquivo nao existe no GitHub, entao o instalador tomava 404 e contava como falha —
// e num update ele sobrescreveria o log do proprio usuario.
const SKIP = new Set(['var']);

function walk(dir, out, rel) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!rel && SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out, true);
    else out.push(p);
  }
  return out;
}

// Extras: o que e' bom ter e nao e' o sistema. O computador do jogo tem 1.000.000 bytes de
// disco no total, o CC cobra minimo de 500 bytes por arquivo E por pasta, e o Mosaic sozinho
// ja come dois tercos disso. Demo e modelo 3D so' entram com `install extras`.
const OPCIONAL = [/^os[/]demos[/]/, /^os[/]share[/]models[/]/];

const files = ['startup.lua', ...walk(path.join(ROOT, 'os'), []).map((p) => path.relative(ROOT, p))]
  .map((p) => p.split(path.sep).join('/'))
  .sort()
  .map((rel) => {
    const buf = fs.readFileSync(path.join(ROOT, rel));
    // CRLF aqui vira hash errado LA'. O .gitattributes guarda tudo em LF, entao o
    // raw.githubusercontent serve LF - mas o manifest e' gerado do arquivo do disco, e um
    // editor (ou um script em Windows) que grave CRLF produz um sha1 que nunca vai bater.
    // No jogo isso aparecia como "Conteudo diverge do manifest" no meio da instalacao.
    if (buf.includes('\r\n')) {
      throw new Error(`${rel} esta com CRLF; o instalador vai recusar o hash. Converta para LF.`);
    }
    const e = {
      path: rel,
      sha1: crypto.createHash('sha1').update(buf).digest('hex'),
      // O tamanho vai no manifest para o instalador conferir o espaco ANTES de comecar, em
      // vez de morrer no meio da lista com "Out of space" e deixar o computador pela metade.
      size: buf.length,
    };
    if (OPCIONAL.some((re) => re.test(rel))) e.optional = true;
    return e;
  });

const manifest = { name: 'Mosaic OS', version, files };
fs.writeFileSync(path.join(ROOT, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');

// A soma crua mente para menos: quem manda e' a conta do CC, com o piso de 500 bytes.
const conta = (list) => list.reduce((t, f) => t + Math.max(500, f.size), 0);
const base = files.filter((f) => !f.optional);
const extras = files.filter((f) => f.optional);
const kb = (n) => (n / 1024).toFixed(0) + ' KB';
console.log(`manifest.json: v${version}, ${files.length} arquivos`);
console.log(`  sistema: ${base.length} arquivos, ${kb(conta(base))} no disco do jogo`);
if (extras.length) {
  console.log(`  extras:  ${extras.length} arquivos, ${kb(conta(extras))} (so com "install extras")`);
}
console.log('  o computador do CC tem 977 KB (1.000.000 bytes) no total');

// O instalador baixa cada caminho do manifest do raw.githubusercontent. Arquivo que existe
// aqui mas nao esta versionado da 404 la e conta como falha na instalacao — sem nenhuma
// pista do motivo. Melhor descobrir agora que no computador do jogo.
try {
  const tracked = new Set(require('child_process')
    .execSync('git ls-files', { cwd: ROOT, encoding: 'utf8' }).split('\n'));
  const missing = files.map((f) => f.path).filter((p) => !tracked.has(p));
  if (missing.length) {
    console.error('\nAVISO: no manifest mas fora do git (dariam 404 no instalador):');
    for (const p of missing) console.error('  ' + p);
    process.exitCode = 1;
  }
} catch (e) {
  // Sem git na maquina: segue sem a checagem, nao e' motivo para falhar.
}
