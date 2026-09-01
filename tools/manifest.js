#!/usr/bin/env node
// Gera manifest.json: versão + lista de arquivos instaláveis (os/**, startup.lua) com sha1.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const version = fs.readFileSync(path.join(ROOT, 'os', 'version.lua'), 'utf8').match(/version\s*=\s*"([^"]+)"/)[1];

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
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
