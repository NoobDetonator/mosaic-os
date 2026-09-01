#!/usr/bin/env node
// Emulador headless minimo de um computador CC:Tweaked (fengari = Lua em JS) para testar o Mosaic OS.
// NAO e' um emulador completo: term/window/fs/os/settings/textutils sao reimplementados em tools/emu/bios.lua.
// Uso: node emu.js [--script /caminho/no/computador.lua] [--width 51] [--height 19] [--show] [--max-events N] [--pocket]
'use strict';
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const ROOT = path.resolve(__dirname, '..', '..');           // mosaic/
const SANDBOX = path.join(__dirname, 'sandbox');
const args = process.argv.slice(2);
function opt(name, def) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : def;
}
const opts = {
  script: opt('--script', '/startup.lua'),
  width: parseInt(opt('--width', '51'), 10),
  height: parseInt(opt('--height', '19'), 10),
  show: args.includes('--show'),
  maxEvents: parseInt(opt('--max-events', '20000'), 10),
  pocket: args.includes('--pocket'),
};

// Sandbox limpo a cada execucao; /os aponta para o codigo real, /os/var para o sandbox.
fs.rmSync(SANDBOX, { recursive: true, force: true });
fs.mkdirSync(path.join(SANDBOX, 'os_var'), { recursive: true });
fs.copyFileSync(path.join(ROOT, 'startup.lua'), path.join(SANDBOX, 'startup.lua'));
const MOUNTS = [
  ['os/var', path.join(SANDBOX, 'os_var')],
  ['os', path.join(ROOT, 'os')],
  ['rom', path.join(__dirname, 'rom')],
  ['test', path.join(__dirname, '..', 'test')],
  ['', SANDBOX],
];

function norm(p) {
  const parts = [];
  for (const seg of String(p).split(/[\\/]+/)) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') parts.pop();
    else parts.push(seg);
  }
  return parts.join('/');
}
function real(p) {
  const n = norm(p);
  for (const [prefix, dir] of MOUNTS) {
    if (prefix === '' || n === prefix || n.startsWith(prefix + '/')) {
      return { real: path.join(dir, n.slice(prefix.length)), readOnly: prefix === 'rom' };
    }
  }
  return { real: path.join(SANDBOX, n), readOnly: false };
}

const L0 = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L0);

// ATENCAO: funcoes JS recebem o estado da *thread* que chamou (coroutines); nunca usar L0 dentro delas.
const S = (s) => to_luastring(String(s));
const arg = (L, i) => (lua.lua_isnoneornil(L, i) ? null : to_jsstring(lua.lua_tostring(L, i)));
const pushString = (L, s) => lua.lua_pushstring(L, S(s));
function reg(name, fn) {
  lua.lua_pushjsfunction(L0, fn);
  lua.lua_setfield(L0, -2, S(name));
}

lua.lua_newtable(L0);
reg('read', (L) => {
  const { real: r } = real(arg(L, 1));
  try {
    lua.lua_pushstring(L, new Uint8Array(fs.readFileSync(r)));   // bytes crus
    return 1;
  } catch (e) { return 0; }
});
reg('write', (L) => {
  const { real: r, readOnly } = real(arg(L, 1));
  if (readOnly) { lua.lua_pushboolean(L, false); return 1; }
  const data = Buffer.from(lua.lua_tostring(L, 2));
  const append = lua.lua_toboolean(L, 3);
  fs.mkdirSync(path.dirname(r), { recursive: true });
  if (append) fs.appendFileSync(r, data); else fs.writeFileSync(r, data);
  lua.lua_pushboolean(L, true);
  return 1;
});
reg('exists', (L) => { lua.lua_pushboolean(L, fs.existsSync(real(arg(L, 1)).real)); return 1; });
reg('isDir', (L) => {
  const r = real(arg(L, 1)).real;
  lua.lua_pushboolean(L, fs.existsSync(r) && fs.statSync(r).isDirectory());
  return 1;
});
reg('isReadOnly', (L) => { lua.lua_pushboolean(L, real(arg(L, 1)).readOnly); return 1; });
reg('list', (L) => {
  const n = norm(arg(L, 1));
  const names = new Set();
  const r = real(n).real;
  if (fs.existsSync(r) && fs.statSync(r).isDirectory()) for (const f of fs.readdirSync(r)) names.add(f);
  for (const [prefix] of MOUNTS) {
    if (prefix && path.posix.dirname(prefix) === (n || '.')) names.add(path.posix.basename(prefix));
  }
  lua.lua_newtable(L);
  let i = 1;
  for (const f of [...names].sort()) { pushString(L, f); lua.lua_rawseti(L, -2, i++); }
  return 1;
});
reg('mkdir', (L) => { fs.mkdirSync(real(arg(L, 1)).real, { recursive: true }); return 0; });
reg('delete', (L) => { fs.rmSync(real(arg(L, 1)).real, { recursive: true, force: true }); return 0; });
reg('move', (L) => { fs.renameSync(real(arg(L, 1)).real, real(arg(L, 2)).real); return 0; });
reg('copy', (L) => { fs.cpSync(real(arg(L, 1)).real, real(arg(L, 2)).real, { recursive: true }); return 0; });
reg('size', (L) => {
  const r = real(arg(L, 1)).real;
  lua.lua_pushinteger(L, fs.existsSync(r) ? fs.statSync(r).size : 0);
  return 1;
});
// fs.writeSync: process.stdout.write seguido de process.exit() perde a saida quando stdout e um pipe.
const out = (fd, s) => { try { fs.writeSync(fd, String(s) + '\n'); } catch (e) { /* EPIPE */ } };
reg('print', (L) => { out(1, arg(L, 1)); return 0; });
reg('stderr', (L) => { out(2, arg(L, 1)); return 0; });
reg('epoch', (L) => { lua.lua_pushnumber(L, Date.now()); return 1; });
reg('date', (L) => {
  const fmt = arg(L, 1) || '%c';
  const t = lua.lua_isnoneornil(L, 2) ? new Date() : new Date(lua.lua_tonumber(L, 2) * 1000);
  const p = (n) => String(n).padStart(2, '0');
  const map = {
    '%Y': t.getFullYear(), '%m': p(t.getMonth() + 1), '%d': p(t.getDate()), '%H': p(t.getHours()),
    '%M': p(t.getMinutes()), '%S': p(t.getSeconds()), '%c': t.toString(),
    '%A': t.toLocaleDateString('pt-BR', { weekday: 'long' }), '%B': t.toLocaleDateString('pt-BR', { month: 'long' }), '%%': '%',
  };
  pushString(L, fmt.replace(/%[a-zA-Z%]/g, (m) => (m in map ? map[m] : m)));
  return 1;
});
reg('exit', (L) => {
  const code = lua.lua_isnoneornil(L, 1) ? 0 : lua.lua_tointeger(L, 1);
  const msg = arg(L, 2);
  if (msg) process.stderr.write(msg + '\n');
  process.exit(code);
});
lua.lua_newtable(L0);
for (const [k, v] of Object.entries(opts)) {
  if (typeof v === 'boolean') lua.lua_pushboolean(L0, v);
  else if (typeof v === 'number') lua.lua_pushinteger(L0, v);
  else pushString(L0, v);
  lua.lua_setfield(L0, -2, S(k));
}
lua.lua_setfield(L0, -2, S('opts'));
lua.lua_setglobal(L0, S('host'));

const bios = fs.readFileSync(path.join(__dirname, 'bios.lua'));
if (lauxlib.luaL_loadbuffer(L0, new Uint8Array(bios), bios.length, S('=bios.lua')) !== lua.LUA_OK) {
  console.error('bios.lua: ' + to_jsstring(lua.lua_tostring(L0, -1)));
  process.exit(2);
}
if (lua.lua_pcall(L0, 0, 0, 0) !== lua.LUA_OK) {
  console.error('bios.lua erro: ' + to_jsstring(lua.lua_tostring(L0, -1)));
  process.exit(2);
}
