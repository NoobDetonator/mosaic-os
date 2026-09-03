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

const files = ['startup.lua', ...walk(path.join(ROOT, 'os'), []).map((p) => path.relative(ROOT, p))]
  .map((p) => p.split(path.sep).join('/'))
  .sort()
  .map((rel) => ({
    path: rel,
    sha1: crypto.createHash('sha1').update(fs.readFileSync(path.join(ROOT, rel))).digest('hex'),
  }));

const manifest = { name: 'Mosaic OS', version, files };
fs.writeFileSync(path.join(ROOT, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`manifest.json: v${version}, ${files.length} arquivos`);

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
