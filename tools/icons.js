#!/usr/bin/env node
// Gera os icones do Mosaic OS em .nfp (um pixel do arquivo = um sub-pixel na tela).
//
//   node tools/icons.js                    regera os icones do sistema a partir da arte abaixo
//   node tools/icons.js --from <pasta>     converte PNG de uma pasta (biblioteca de icones)
//
// A arte fica em texto aqui mesmo, de proposito: num icone de 12x12 cada ponto e uma decisao
// de desenho, e converter automaticamente de um PNG grande sempre borra. O modo --from serve
// para trazer uma biblioteca inteira de uma vez; depois da para ajustar o que ficou ruim.
//
// Cada caractere e um digito hexadecimal de cor do CC; espaco = transparente.
// Com a paleta do Mosaic (kernel/palette.lua):
//   0 branco #FFFFFF   7 cinza escuro #808080   8 cinza claro #C0C0C0   f preto #000000
//   b azul-marinho #000080   3 azul claro #1084D0   9 teal #008080
//   1 laranja  4 amarelo  5 verde-limao  d verde  e vermelho  a roxo  c marrom  2 magenta  6 rosa
'use strict';
const fs = require('fs');
const path = require('path');

const OUT = path.resolve(__dirname, '..', 'os', 'share', 'icons');

// 12 x 12. Cada linha tem que ter exatamente 12 caracteres.
const ART = {
  terminal: [
    '            ',
    ' 8888888888 ',
    ' 8ffffffff8 ',
    ' 8f0ff0fff8 ',
    ' 8fff0ffff8 ',
    ' 8f0ffffff8 ',
    ' 8ffffffff8 ',
    ' 8888888888 ',
    '   777777   ',
    '  77777777  ',
    '            ',
    '            ',
  ],
  files: [
    '            ',
    ' ffff       ',
    'f4444f      ',
    'f444444fffff',
    'f4444444444f',
    'f4444444444f',
    'f4444444444f',
    'f4444444444f',
    'f4444444444f',
    'ffffffffffff',
    '            ',
    '            ',
  ],
  editor: [
    '            ',
    '  ffffffff  ',
    '  f000000f  ',
    '  f0ffff0f  ',
    '  f000000f  ',
    '  f0ffff0f  ',
    '  f000000f  ',
    '  f0ffff0f  ',
    '  f000000f  ',
    '  ffffffff  ',
    '            ',
    '            ',
  ],
  netcenter: [
    '            ',
    '    8888    ',
    '    8ff8    ',
    '    8888    ',
    '     ff     ',
    '  ffffffff  ',
    '  f      f  ',
    ' 8888  8888 ',
    ' 8ff8  8ff8 ',
    ' 8888  8888 ',
    '            ',
    '            ',
  ],
  periph: [
    '            ',
    '  f f f f   ',
    ' ffffffffff ',
    ' f88888888f ',
    ' f8ffffff8f ',
    ' f8f7777f8f ',
    ' f8f7777f8f ',
    ' f8ffffff8f ',
    ' f88888888f ',
    ' ffffffffff ',
    '  f f f f   ',
    '            ',
  ],
  taskman: [
    '            ',
    'ffffffffffff',
    'f0000000000f',
    'f0000000000f',
    'f00e0000000f',
    'f00e00d0000f',
    'f00e00d00b0f',
    'f00e00d00b0f',
    'f00e00d00b0f',
    'ffffffffffff',
    '            ',
    '            ',
  ],
  settings: [
    '            ',
    '   f    f   ',
    '  ffffffff  ',
    ' fff8888fff ',
    ' f88888888f ',
    'ff888ff888ff',
    'ff888ff888ff',
    ' f88888888f ',
    ' fff8888fff ',
    '  ffffffff  ',
    '   f    f   ',
    '            ',
  ],
  help: [
    '            ',
    '   bbbbbb   ',
    '  bbbbbbbb  ',
    ' bbb0000bbb ',
    ' bbbbbb0bbb ',
    ' bbbbb00bbb ',
    ' bbbb00bbbb ',
    ' bbbbbbbbbb ',
    ' bbbb00bbbb ',
    '  bbbbbbbb  ',
    '   bbbbbb   ',
    '            ',
  ],
  reactor: [
    '            ',
    ' ffffffffff ',
    ' f77777777f ',
    ' f75555557f ',
    ' f75444457f ',
    ' f75411457f ',
    ' f75444457f ',
    ' f75555557f ',
    ' f77777777f ',
    ' ffffffffff ',
    '            ',
    '            ',
  ],
  notes: [
    '            ',
    '  ffffffff  ',
    '  f444444f  ',
    '  f4ffff4f  ',
    '  f444444f  ',
    '  f4ffff4f  ',
    '  f444444f  ',
    '  f4ffff4f  ',
    '  f444444f  ',
    '  ffffffff  ',
    '            ',
    '            ',
  ],
  calc: [
    '            ',
    ' ffffffffff ',
    ' f88888888f ',
    ' f80000000f ',
    ' f88888888f ',
    ' f8f7f7f7f8 ',
    ' f88888888f ',
    ' f8f7f7f7f8 ',
    ' f88888888f ',
    ' ffffffffff ',
    '            ',
    '            ',
  ],
  clock: [
    '            ',
    '   ffffff   ',
    '  f000000f  ',
    ' f00000000f ',
    ' f000f0000f ',
    ' f000f0000f ',
    ' f000ff000f ',
    ' f00000000f ',
    '  f000000f  ',
    '   ffffff   ',
    '            ',
    '            ',
  ],
  remote: [
    '            ',
    '  ffffffff  ',
    '  f888888f  ',
    '  f8ffff8f  ',
    '  f8f00f8f  ',
    '  f8ffff8f  ',
    '  f888888f  ',
    '  f8e88e8f  ',
    '  f888888f  ',
    '  ffffffff  ',
    '            ',
    '            ',
  ],
  pkg: [
    '            ',
    '     ff     ',
    '     ff     ',
    '   ffffff   ',
    '    ffff    ',
    '     ff     ',
    '            ',
    ' cccccccccc ',
    ' c11111111c ',
    ' cccccccccc ',
    '            ',
    '            ',
  ],
  paint: [
    '            ',
    '  ffffffff  ',
    '  f0eeee0f  ',
    '  f0e11e0f  ',
    '  f0e44e0f  ',
    '  f0e55e0f  ',
    '  f0ebbe0f  ',
    '  f0eeee0f  ',
    '  ffffffff  ',
    '     ff     ',
    '     ff     ',
    '            ',
  ],
  lua: [
    '            ',
    '   bbbbbb   ',
    '  bbbbbbbb  ',
    ' bbbb00bbbb ',
    ' bbb0000bbb ',
    ' bbb0000bbb ',
    ' bbbb00bbbb ',
    ' bbbbbbbbbb ',
    '  bbbbbbbb  ',
    '   bbbbbb   ',
    '            ',
    '            ',
  ],
  // Reserva: app do usuario, ou qualquer um sem icone proprio.
  app: [
    '            ',
    '  ffffffff  ',
    '  f888888f  ',
    '  f8f00f8f  ',
    '  f80ff08f  ',
    '  f80ff08f  ',
    '  f8f00f8f  ',
    '  f888888f  ',
    '  ffffffff  ',
    '            ',
    '            ',
    '            ',
  ],
};

function checkArt(name, rows) {
  if (rows.length !== 12) throw new Error(`${name}: ${rows.length} linhas, esperado 12`);
  rows.forEach((r, i) => {
    if (r.length !== 12) throw new Error(`${name}: linha ${i + 1} tem ${r.length} caracteres, esperado 12`);
    if (!/^[0-9a-f ]*$/.test(r)) throw new Error(`${name}: linha ${i + 1} tem caractere invalido: ${r}`);
  });
}

// ---------------------------------------------------------------- PNG -> .nfp
// Paleta do Mosaic (kernel/palette.lua). Converter contra a paleta padrao do CC daria
// cores erradas: sete slots diferem.
const MOSAIC_PALETTE = {
  '0': [0xff, 0xff, 0xff], '1': [0xf2, 0xb2, 0x33], '2': [0xe5, 0x7f, 0xd8], '3': [0x10, 0x84, 0xd0],
  '4': [0xde, 0xde, 0x6c], '5': [0x7f, 0xcc, 0x19], '6': [0xf2, 0xb2, 0xcc], '7': [0x80, 0x80, 0x80],
  '8': [0xc0, 0xc0, 0xc0], '9': [0x00, 0x80, 0x80], 'a': [0xb2, 0x66, 0xe5], 'b': [0x00, 0x00, 0x80],
  'c': [0x7f, 0x66, 0x4c], 'd': [0x57, 0xa6, 0x4e], 'e': [0xcc, 0x4c, 0x4c], 'f': [0x00, 0x00, 0x00],
};

function nearest(r, g, b) {
  let best = 'f', bestD = Infinity;
  for (const [hex, [pr, pg, pb]] of Object.entries(MOSAIC_PALETTE)) {
    // Distancia ponderada: o olho pesa mais o verde.
    const d = 2 * (r - pr) ** 2 + 4 * (g - pg) ** 2 + 3 * (b - pb) ** 2;
    if (d < bestD) { bestD = d; best = hex; }
  }
  return best;
}

function pngToNfp(file, size) {
  let PNG;
  try {
    PNG = require('pngjs').PNG;
  } catch (e) {
    console.error('Para converter PNG instale a dependencia:  cd tools && npm install pngjs');
    process.exit(2);
  }
  const img = PNG.sync.read(fs.readFileSync(file));
  const rows = [];
  for (let y = 0; y < size; y++) {
    let line = '';
    for (let x = 0; x < size; x++) {
      // Amostra o pixel do centro do bloco correspondente (nearest neighbour).
      const sx = Math.min(img.width - 1, Math.floor((x + 0.5) * img.width / size));
      const sy = Math.min(img.height - 1, Math.floor((y + 0.5) * img.height / size));
      const i = (img.width * sy + sx) << 2;
      const a = img.data[i + 3];
      line += a < 128 ? ' ' : nearest(img.data[i], img.data[i + 1], img.data[i + 2]);
    }
    rows.push(line);
  }
  return rows;
}

// ---------------------------------------------------------------- main
fs.mkdirSync(OUT, { recursive: true });
const args = process.argv.slice(2);
const fromIdx = args.indexOf('--from');

if (fromIdx >= 0) {
  const dir = args[fromIdx + 1];
  if (!dir || !fs.existsSync(dir)) {
    console.error('uso: node tools/icons.js --from <pasta com PNG>');
    process.exit(2);
  }
  const size = parseInt(args[args.indexOf('--size') + 1], 10) || 12;
  let n = 0;
  for (const f of fs.readdirSync(dir)) {
    if (!/\.png$/i.test(f)) continue;
    const name = f.replace(/\.png$/i, '').toLowerCase().replace(/[^a-z0-9_-]/g, '-');
    fs.writeFileSync(path.join(OUT, name + '.nfp'), pngToNfp(path.join(dir, f), size).join('\n') + '\n');
    n++;
  }
  console.log(`${n} icone(s) convertidos para ${path.relative(process.cwd(), OUT)} (${size}x${size})`);
  process.exit(0);
}

let count = 0;
for (const [name, rows] of Object.entries(ART)) {
  checkArt(name, rows);
  fs.writeFileSync(path.join(OUT, name + '.nfp'), rows.join('\n') + '\n');
  count++;
}
console.log(`${count} icones gravados em ${path.relative(process.cwd(), OUT)} (12x12 sub-pixels = 6x4 celulas)`);
