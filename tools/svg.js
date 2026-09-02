#!/usr/bin/env node
// Converte SVG para o formato vetorial do Mosaic (os/lib/vector.lua).
//
//   node tools/svg.js <arquivo.svg> [...]     grava em os/share/vectors/<nome>.lua
//
// Le um pedaco do SVG: viewBox, rect, circle, ellipse, polygon, polyline e path com
// M/L/H/V/Z (maiusculo e minusculo). NAO le transform, curva de Bezier, grupo aninhado,
// gradiente nem espessura de traco. Se o desenho usar isso, achate no editor antes:
// no Inkscape, "Caminho > Objeto para caminho" e "Desagrupar" resolvem quase tudo.
//
// Isso e de proposito: um leitor completo de SVG e um projeto por si so, e o Mosaic so
// precisa de figuras chapadas para logo, marca e grafico.
'use strict';
const fs = require('fs');
const path = require('path');

const OUT = path.resolve(__dirname, '..', 'os', 'share', 'vectors');

// Paleta do Mosaic (kernel/palette.lua). A padrao do CC daria cores erradas: 7 slots diferem.
const PALETTE = {
  '0': [0xff, 0xff, 0xff], '1': [0xf2, 0xb2, 0x33], '2': [0xe5, 0x7f, 0xd8], '3': [0x10, 0x84, 0xd0],
  '4': [0xde, 0xde, 0x6c], '5': [0x7f, 0xcc, 0x19], '6': [0xf2, 0xb2, 0xcc], '7': [0x80, 0x80, 0x80],
  '8': [0xc0, 0xc0, 0xc0], '9': [0x00, 0x80, 0x80], 'a': [0xb2, 0x66, 0xe5], 'b': [0x00, 0x00, 0x80],
  'c': [0x7f, 0x66, 0x4c], 'd': [0x57, 0xa6, 0x4e], 'e': [0xcc, 0x4c, 0x4c], 'f': [0x00, 0x00, 0x00],
};

const LUA_NAME = {
  '0': 'colors.white', '1': 'colors.orange', '2': 'colors.magenta', '3': 'colors.lightBlue',
  '4': 'colors.yellow', '5': 'colors.lime', '6': 'colors.pink', '7': 'colors.gray',
  '8': 'colors.lightGray', '9': 'colors.cyan', 'a': 'colors.purple', 'b': 'colors.blue',
  'c': 'colors.brown', 'd': 'colors.green', 'e': 'colors.red', 'f': 'colors.black',
};

const NAMED = {
  black: 'f', white: '0', red: 'e', lime: '5', green: 'd', blue: 'b', navy: 'b',
  yellow: '4', cyan: '9', aqua: '9', teal: '9', magenta: '2', fuchsia: '2',
  gray: '7', grey: '7', silver: '8', orange: '1', purple: 'a', brown: 'c', pink: '6',
};

function nearest(r, g, b) {
  let best = 'f', bestD = Infinity;
  for (const hex of Object.keys(PALETTE)) {
    const p = PALETTE[hex];
    // Verde pesa mais: e onde o olho enxerga melhor.
    const d = 2 * (r - p[0]) ** 2 + 4 * (g - p[1]) ** 2 + 3 * (b - p[2]) ** 2;
    if (d < bestD) { bestD = d; best = hex; }
  }
  return best;
}

function color(value) {
  if (!value) return null;
  const v = String(value).trim().toLowerCase();
  if (v === 'none' || v === 'transparent') return null;
  if (NAMED[v]) return NAMED[v];
  let m = /^#([0-9a-f]{3})$/.exec(v);
  if (m) return nearest(...m[1].split('').map((c) => parseInt(c + c, 16)));
  m = /^#([0-9a-f]{6})$/.exec(v);
  if (m) return nearest(parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16));
  m = /^rgba?\(([^)]+)\)$/.exec(v);
  if (m) {
    const p = m[1].split(',').map(parseFloat);
    return nearest(p[0], p[1], p[2]);
  }
  return 'f';
}

function attr(tag, name) {
  const m = new RegExp(name + '\\s*=\\s*"([^"]*)"').exec(tag)
    || new RegExp(name + "\\s*=\\s*'([^']*)'").exec(tag);
  return m ? m[1] : null;
}

function fillOf(tag) {
  const direct = attr(tag, 'fill');
  if (direct !== null) return color(direct);
  const style = attr(tag, 'style');
  if (style) {
    const m = /fill\s*:\s*([^;]+)/.exec(style);
    if (m) return color(m[1]);
  }
  return 'f';   // sem fill declarado, o SVG pinta de preto
}

// "d" do path vira a lista { "M", x, y, "L", x, y, ..., "Z" } que os/lib/vector le.
function parsePath(d) {
  const out = [];
  const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
  let i = 0, cmd = null, x = 0, y = 0, sx = 0, sy = 0;
  const num = () => parseFloat(tokens[i++]);
  while (i < tokens.length) {
    if (/[a-zA-Z]/.test(tokens[i])) cmd = tokens[i++];
    if (i > tokens.length) break;
    if (cmd === 'M' || cmd === 'm') {
      const nx = num(), ny = num();
      x = cmd === 'm' ? x + nx : nx;
      y = cmd === 'm' ? y + ny : ny;
      sx = x; sy = y;
      out.push('M', x, y);
      cmd = cmd === 'm' ? 'l' : 'L';   // numeros extras depois de M contam como L, igual no SVG
    } else if (cmd === 'L' || cmd === 'l') {
      const nx = num(), ny = num();
      x = cmd === 'l' ? x + nx : nx;
      y = cmd === 'l' ? y + ny : ny;
      out.push('L', x, y);
    } else if (cmd === 'H' || cmd === 'h') {
      const nx = num();
      x = cmd === 'h' ? x + nx : nx;
      out.push('L', x, y);
    } else if (cmd === 'V' || cmd === 'v') {
      const ny = num();
      y = cmd === 'v' ? y + ny : ny;
      out.push('L', x, y);
    } else if (cmd === 'Z' || cmd === 'z') {
      out.push('Z');
      x = sx; y = sy;
    } else {
      while (i < tokens.length && !/[a-zA-Z]/.test(tokens[i])) i++;   // curva: pula os numeros
    }
  }
  return out;
}

function convert(file) {
  const src = fs.readFileSync(file, 'utf8');
  const vbAttr = attr(src, 'viewBox');
  const vb = vbAttr ? vbAttr.trim().split(/[\s,]+/).map(Number) : [0, 0, 16, 16];
  const box = [vb[0], vb[1], vb[0] + vb[2], vb[1] + vb[3]];
  const parts = [];
  const warn = new Set();

  const tags = src.match(/<(rect|circle|ellipse|polygon|polyline|path)\b[^>]*>/g) || [];
  for (const tag of tags) {
    const kind = /^<(\w+)/.exec(tag)[1];
    if (/transform\s*=/.test(tag)) warn.add(`${kind} com transform (ignorado)`);
    const fill = fillOf(tag);
    if (!fill) continue;
    if (kind === 'rect') {
      parts.push({ rect: [+attr(tag, 'x') || 0, +attr(tag, 'y') || 0, +attr(tag, 'width') || 0, +attr(tag, 'height') || 0], fill });
    } else if (kind === 'circle') {
      parts.push({ circle: [+attr(tag, 'cx') || 0, +attr(tag, 'cy') || 0, +attr(tag, 'r') || 0], fill });
    } else if (kind === 'ellipse') {
      warn.add('ellipse virou circulo pelo raio menor');
      parts.push({ circle: [+attr(tag, 'cx') || 0, +attr(tag, 'cy') || 0,
        Math.min(+attr(tag, 'rx') || 0, +attr(tag, 'ry') || 0)], fill });
    } else if (kind === 'polygon' || kind === 'polyline') {
      const nums = (attr(tag, 'points') || '').trim().split(/[\s,]+/).map(Number).filter((n) => !isNaN(n));
      const d = [];
      for (let k = 0; k + 1 < nums.length; k += 2) d.push(k === 0 ? 'M' : 'L', nums[k], nums[k + 1]);
      if (d.length) { d.push('Z'); parts.push({ d, fill }); }
    } else if (kind === 'path') {
      if (/[cCsSqQtTaA]/.test(attr(tag, 'd') || '')) warn.add('path com curva (so os trechos retos entram)');
      const d = parsePath(attr(tag, 'd') || '');
      if (d.length) parts.push({ d, fill, rule: attr(tag, 'fill-rule') === 'evenodd' ? 'eo' : null });
    }
  }
  return { box, parts, warn: [...warn] };
}

function toLua(name, shape) {
  const n = (v) => (Number.isInteger(v) ? String(v) : String(Math.round(v * 100) / 100));
  const out = [
    `-- ${name}: desenho vetorial, convertido de SVG por tools/svg.js.`,
    '-- As coordenadas vivem na caixa vb; o os/lib/vector escala para o tamanho pedido.',
    'return {',
    `    vb = { ${shape.box.map(n).join(', ')} },`,
  ];
  for (const p of shape.parts) {
    const fill = LUA_NAME[p.fill] || 'colors.black';
    if (p.rect) out.push(`    { rect = { ${p.rect.map(n).join(', ')} }, fill = ${fill} },`);
    else if (p.circle) out.push(`    { circle = { ${p.circle.map(n).join(', ')} }, fill = ${fill} },`);
    else {
      const d = p.d.map((v) => (typeof v === 'string' ? `"${v}"` : n(v))).join(', ');
      out.push(`    { fill = ${fill},${p.rule ? ' rule = "eo",' : ''} d = { ${d} } },`);
    }
  }
  out.push('}', '');
  return out.join('\n');
}

const files = process.argv.slice(2).filter((a) => !a.startsWith('-'));
if (!files.length) {
  console.error('uso: node tools/svg.js <arquivo.svg> [...]');
  process.exit(2);
}
fs.mkdirSync(OUT, { recursive: true });
for (const file of files) {
  if (!fs.existsSync(file)) { console.error(`nao existe: ${file}`); continue; }
  const name = path.basename(file).replace(/\.svg$/i, '').toLowerCase().replace(/[^a-z0-9_-]/g, '-');
  const shape = convert(file);
  if (!shape.parts.length) {
    console.error(`${file}: nenhuma figura com preenchimento. Achate o desenho no editor`);
    console.error('  (Inkscape: "Caminho > Objeto para caminho" e "Desagrupar").');
    continue;
  }
  const dest = path.join(OUT, name + '.lua');
  fs.writeFileSync(dest, toLua(name, shape));
  console.log(`${shape.parts.length} figura(s) -> ${path.relative(process.cwd(), dest)}`);
  for (const w of shape.warn) console.log(`  aviso: ${w}`);
}
