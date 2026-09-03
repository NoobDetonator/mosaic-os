'use strict';
// A paleta do Mosaic (os/kernel/palette.lua) vista do lado do Node, e o casamento de uma cor
// RGB qualquer com um dos 16 slots do CC.
//
// Nao e a paleta de fabrica do CC: sete slots diferem (branco, cinza claro, cinza, preto,
// azul, azul claro e ciano viram os tons do Windows 95). Converter contra a paleta errada
// da cor visivelmente trocada — um cinza de botao viraria azulado.

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

module.exports = { PALETTE, LUA_NAME, NAMED, nearest };
