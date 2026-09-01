#!/usr/bin/env node
// Lint do Mosaic OS: sintaxe Lua 5.1 (luaparse) + APIs proibidas (mais novas que CC:T 1.101).
'use strict';
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');

// ponytail: regex, não análise semântica. '//' e sintaxe 5.2+ já são pegos pelo luaparse em modo 5.1.
const FORBIDDEN = [
  [/\bgoto\b/, 'goto (Lua 5.2)'],
  [/\b_ENV\b/, '_ENV (Lua 5.2)'],
  [/\butf8\./, 'biblioteca utf8 (Lua 5.3)'],
  [/\bstring\.(pack|unpack|packsize)\b/, 'string.pack (Lua 5.3)'],
  [/\btable\.move\b/, 'table.move (Lua 5.3)'],
  [/\bcoroutine\.isyieldable\b/, 'coroutine.isyieldable (Lua 5.2)'],
  [/\bhttp\.(get|post|request|websocket|websocketAsync)\s*\{/, 'http.* forma tabela (CC:T 1.105)'],
  [/\btextutils\.(serialiseJSON|serializeJSON)\s*\([^)]*,\s*\{/, 'serialiseJSON com tabela de opções (CC:T 1.106)'],
  [/\btextutils\.(serialise|serialize)\s*\([^)]*,\s*\{/, 'serialise com opções (CC:T 1.97)'],
  [/\bfs\.open\s*\([^,]+,\s*["'][rw]\+/, 'fs.open r+/w+ (CC:T 1.109)'],
  [/\bcolors\.fromBlit\b|\bcolours\.fromBlit\b/, 'colors.fromBlit (CC:T 1.106)'],
  [/\bexpect\.range\b/, 'cc.expect.range (CC:T 1.96)'],
  [/\bfs\.combine\s*\([^()]*,[^()]*,[^()]*\)/, 'fs.combine com >2 args (CC:T 1.95)'],
  [/\bgetResponseHeaders\s*\(\)/, 'Websocket.getResponseHeaders (CC:T 1.117) — ok só em http.Response'],
];

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === 'tools' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.lua')) out.push(p);
  }
  return out;
}

function stripComments(src) {
  // Remove comentários de linha e de bloco para não acusar falsos positivos.
  return src.replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, '').replace(/--[^\n]*/g, '');
}

let errors = 0;
const files = walk(ROOT, []);
for (const file of files) {
  const rel = path.relative(ROOT, file);
  const src = fs.readFileSync(file, 'utf8');
  try {
    luaparse.parse(src, { luaVersion: '5.1', comments: false });
  } catch (e) {
    errors++;
    console.log(`${rel}:${e.line || '?'}: SINTAXE: ${e.message}`);
    continue;
  }
  const clean = stripComments(src).split('\n');
  clean.forEach((line, i) => {
    for (const [re, why] of FORBIDDEN) {
      if (re.test(line)) {
        errors++;
        console.log(`${rel}:${i + 1}: PROIBIDO: ${why}\n    ${line.trim()}`);
      }
    }
  });
}
console.log(`${files.length} arquivos, ${errors} problema(s).`);
process.exit(errors ? 1 : 0);
