#!/usr/bin/env node
// Converte .obj (Wavefront, o que o Blender exporta) para o formato de malha do Mosaic.
//
//   node tools/obj.js <arquivo.obj> [...]     grava em os/share/models/<nome>.lua
//
// Le v, vn, f, usemtl e mtllib, e do .mtl ao lado le Kd (a cor difusa) de cada material,
// casando cada uma com a paleta do Mosaic. Triangula face de 4 lados ou mais em leque.
// NAO le textura (nao existe UV no motor), curva, grupo de suavizacao nem transformacao —
// avisa e segue, como o tools/svg.js faz.
//
// No Blender, exporte com "Forward: -Z, Up: Y" (o padrao do exportador) e com "Triangulate
// Faces" se a malha tiver n-gono concavo: o leque daqui so' acerta poligono convexo.
//
// Duas conversoes acontecem aqui, e as duas sao silenciosas se estiverem certas:
//
//  1. Mao. O .obj e' de mao direita com +z vindo para o observador; o Mosaic e' de mao
//     esquerda com +z entrando na tela. Entao z troca de sinal. Sem isso o modelo sai
//     espelhado, e espelhado e' dificil de notar num print.
//  2. Ordem dos cantos. Depois de trocar o sinal de z, o produto vetorial de mao direita
//     passa a apontar para DENTRO, que e' exatamente a convencao dos geradores do
//     os/lib/mesh (ver shade.faceNormal). Ou seja: nao precisa inverter nada. Quando o
//     arquivo traz `vn`, cada face e' conferida contra a normal declarada e so' as que
//     discordarem trocam de ordem — arquivo de origem duvidosa nao passa despercebido.
'use strict';
const fs = require('fs');
const path = require('path');
const { LUA_NAME, nearest } = require('./palette');

const OUT = path.resolve(__dirname, '..', 'os', 'share', 'models');

// Kd vem em 0..1 lineares no papel, mas todo exportador grava sRGB direto. Tratar como
// sRGB e o que casa com o que se ve no Blender.
function readMtl(file, warn) {
  const mats = {};
  if (!fs.existsSync(file)) {
    warn.add(`nao achei ${path.basename(file)}: tudo sai em cinza claro`);
    return mats;
  }
  let cur = null;
  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    const t = raw.trim().split(/\s+/);
    if (t[0] === 'newmtl') { cur = t.slice(1).join(' '); mats[cur] = '8'; }
    else if (t[0] === 'Kd' && cur) {
      const [r, g, b] = t.slice(1, 4).map((v) => Math.round(Math.min(1, Math.max(0, parseFloat(v))) * 255));
      if (!Number.isNaN(r)) mats[cur] = nearest(r, g, b);
    } else if (t[0] === 'map_Kd') warn.add('textura ignorada: o motor nao tem UV');
  }
  return mats;
}

// "12", "12/3", "12//4", "12/3/4" e indice negativo (relativo ao fim da lista).
function refs(tok, nv, nn) {
  const p = tok.split('/');
  const v = parseInt(p[0], 10);
  const n = p[2] ? parseInt(p[2], 10) : 0;
  return [v < 0 ? nv + v : v - 1, n === 0 ? -1 : (n < 0 ? nn + n : n - 1)];
}

function cross(u, v) {
  return [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
}

function convert(file) {
  const warn = new Set();
  const dir = path.dirname(file);
  const verts = [];      // ja com z invertido
  const norms = [];      // idem
  let mats = {};
  let cor = '8';
  const tris = [];
  const edges = {};      // aresta -> quantas faces a usam, para saber se a casca e fechada
  let flipadas = 0;
  let semNormal = 0;

  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    const line = raw.replace(/#.*$/, '').trim();
    if (!line) continue;
    const t = line.split(/\s+/);
    const k = t[0];
    if (k === 'v') verts.push([parseFloat(t[1]), parseFloat(t[2]), -parseFloat(t[3])]);
    else if (k === 'vn') norms.push([parseFloat(t[1]), parseFloat(t[2]), -parseFloat(t[3])]);
    else if (k === 'mtllib') Object.assign(mats, readMtl(path.join(dir, t.slice(1).join(' ')), warn));
    else if (k === 'usemtl') {
      const nome = t.slice(1).join(' ');
      if (mats[nome]) cor = mats[nome];
      else { cor = '8'; warn.add(`material "${nome}" sem Kd: sai em cinza claro`); }
    } else if (k === 'f') {
      const face = t.slice(1).map((tok) => refs(tok, verts.length, norms.length));
      if (face.length < 3) { warn.add('face com menos de 3 cantos, pulada'); continue; }
      if (face.length > 4) warn.add(`n-gono de ${face.length} lados triangulado em leque (so acerta convexo)`);
      for (const [vi] of face) {
        if (!verts[vi]) { warn.add('face aponta para vertice que nao existe, pulada'); }
      }
      if (face.some(([vi]) => !verts[vi])) continue;
      for (let i = 1; i + 1 < face.length; i++) {
        const idx = [face[0], face[i], face[i + 1]];
        const [a, b, c] = idx.map(([vi]) => verts[vi]);
        // Confere contra a normal declarada; sem ela, fica a ordem do arquivo (que, depois
        // do z invertido, ja e a do Mosaic).
        const decl = idx.map(([, ni]) => norms[ni]).filter(Boolean);
        if (decl.length) {
          const n = cross([b[0] - a[0], b[1] - a[1], b[2] - a[2]], [c[0] - a[0], c[1] - a[1], c[2] - a[2]]);
          // shade.faceNormal nega o produto vetorial, entao "para fora" e' -n. Dividir pelo
          // tamanho do produto vetorial (o dobro da area) tira o peso do triangulo da conta:
          // o que importa e' o angulo, nao o tamanho.
          const mag = Math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) || 1;
          const dot = -(n[0] * decl[0][0] + n[1] * decl[0][1] + n[2] * decl[0][2]) / mag;
          // O corte em -0,1 (uns 6 graus) e' contra falso positivo. A Suzanne tem duas lascas
          // de area 0,0006 cujo produto vetorial e' quase perpendicular a normal declarada: o
          // sinal ali e' ruido de arredondamento, e virar a ordem nao muda nada no desenho.
          if (dot < -0.1) { const tmp = idx[1]; idx[1] = idx[2]; idx[2] = tmp; flipadas++; }
        } else semNormal++;
        tris.push({ a: idx[0][0], b: idx[1][0], c3: idx[2][0], c: cor });
        for (let e = 0; e < 3; e++) {
          const x = idx[e][0], y = idx[(e + 1) % 3][0];
          const key = x < y ? `${x},${y}` : `${y},${x}`;
          edges[key] = (edges[key] || 0) + 1;
        }
      }
    } else if (k === 'vt' || k === 'o' || k === 'g' || k === 's' || k === 'l') {
      // vt e' textura (sem UV no motor), o/g/s sao organizacao: nada a fazer, e sem aviso.
    } else warn.add(`"${k}" ignorado`);
  }

  // Casca fechada: toda aresta compartilhada por exatamente duas faces. So' assim o descarte
  // de face de costas e' seguro — numa malha aberta ele faria sumir o lado de dentro.
  const fechada = tris.length > 0 && Object.keys(edges).every((e) => edges[e] === 2);
  if (semNormal) warn.add(`${semNormal} triangulo(s) sem vn: se o modelo sair de dentro para fora, exporte com normais`);
  return { tris, verts, fechada, warn: [...warn], flipadas };
}

// O arquivo e' indexado, e nao uma lista de triangulos com os nove numeros cada. A Suzanne
// tem 507 vertices e 968 triangulos: repetir vertice dava 105 KB, e o computador do jogo tem
// 1 MB de disco no total. Indexado da um terco disso. Quem desdobra e' o mesh.load, uma vez.
//
// Tudo em vetor plano (v, t, cores): em Lua, tabela aninhada custa uma tabela por elemento, e
// aqui seriam milhares delas so' para serem jogadas fora depois de montar os triangulos.
function toLua(name, m) {
  const n = (v) => {
    const r = Math.round(v * 10000) / 10000;
    return Object.is(r, -0) ? '0' : String(r);   // "-0" nao ajuda ninguem a ler
  };
  // So' vertice usado por alguma face entra, renumerado: .obj com vertice solto e' comum.
  const mapa = {};
  const usados = [];
  const idx = (vi) => {
    if (mapa[vi] === undefined) { mapa[vi] = usados.length; usados.push(vi); }
    return mapa[vi] + 1;                          // Lua conta de 1
  };
  const cores = [];
  const corIdx = {};
  const linhas = [];
  for (const t of m.tris) {
    if (corIdx[t.c] === undefined) { cores.push(t.c); corIdx[t.c] = cores.length; }
    linhas.push(`${idx(t.a)}, ${idx(t.b)}, ${idx(t.c3)}, ${corIdx[t.c]},`);
  }

  const out = [
    `-- ${name}: malha 3D, convertida de ${name}.obj por tools/obj.js.`,
    `-- ${m.tris.length} triangulos, ${usados.length} vertices, casca ` +
      `${m.fechada ? 'fechada (descarte de face e seguro)' : 'aberta'}.`,
    `-- Carregue com mesh.load("/os/share/models/${name}.lua"): v e' a lista de vertices`,
    '-- (tres numeros cada) e t a de triangulos (tres indices em v, mais a cor em cores).',
    'return {',
    `    closed = ${m.fechada},`,
    `    cores = { ${cores.map((c) => LUA_NAME[c]).join(', ')} },`,
    '    v = {',
  ];
  for (let i = 0; i < usados.length; i += 4) {
    out.push('        ' + usados.slice(i, i + 4).map((vi) => m.verts[vi].map(n).join(', ')).join(',  ') + ',');
  }
  out.push('    },', '    t = {');
  for (let i = 0; i < linhas.length; i += 4) out.push('        ' + linhas.slice(i, i + 4).join(' '));
  out.push('    },', '}', '');
  return out.join('\n');
}

const files = process.argv.slice(2).filter((a) => !a.startsWith('-'));
if (!files.length) {
  console.error('uso: node tools/obj.js <arquivo.obj> [...]');
  process.exit(2);
}
fs.mkdirSync(OUT, { recursive: true });
for (const file of files) {
  if (!fs.existsSync(file)) { console.error(`nao existe: ${file}`); process.exitCode = 1; continue; }
  const name = path.basename(file).replace(/\.obj$/i, '').toLowerCase().replace(/[^a-z0-9_-]/g, '-');
  const m = convert(file);
  if (!m.tris.length) {
    console.error(`${file}: nenhuma face. Exporte a malha (nao so' a camera e a luz).`);
    process.exitCode = 1;
    continue;
  }
  const dest = path.join(OUT, name + '.lua');
  fs.writeFileSync(dest, toLua(name, m));
  console.log(`${m.tris.length} triangulo(s), casca ${m.fechada ? 'fechada' : 'aberta'} -> ${path.relative(process.cwd(), dest)}`);
  if (m.flipadas) console.log(`  ${m.flipadas} face(s) com a ordem dos cantos corrigida pela normal do arquivo`);
  for (const w of m.warn) console.log(`  aviso: ${w}`);
}
