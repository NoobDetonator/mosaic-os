#!/usr/bin/env node
// Relay do Mosaic OS: ponte entre os computadores do Minecraft e voce (ou uma IA).
//
//   node relay.js                 porta 8765, token gerado em .token
//   PORT=9000 node relay.js       outra porta
//   TOKEN=segredo node relay.js   token fixo
//
// Os computadores conectam em  ws://<ip>:<porta>/ws/computer
// O painel web fica em         http://<ip>:<porta>/
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '8765', 10);
const HOST = process.env.HOST || '0.0.0.0';
const TOKEN_FILE = path.join(__dirname, '.token');
const TIMEOUT = parseInt(process.env.TIMEOUT || '20000', 10);

function loadToken() {
  if (process.env.TOKEN) return process.env.TOKEN;
  if (fs.existsSync(TOKEN_FILE)) return fs.readFileSync(TOKEN_FILE, 'utf8').trim();
  const token = crypto.randomBytes(12).toString('hex');
  fs.writeFileSync(TOKEN_FILE, token + '\n');
  return token;
}
const TOKEN = loadToken();

/** computerId -> { ws, info, connectedAt, lastSeen, address } */
const computers = new Map();
/** requestId -> { resolve, reject, timer } */
const pending = new Map();
/** clientes SSE */
const listeners = new Set();
const eventLog = [];
let nextRequestId = 1;

function broadcast(type, payload) {
  const line = `data: ${JSON.stringify({ type, ...payload, at: Date.now() })}\n\n`;
  for (const res of listeners) {
    try { res.write(line); } catch (e) { listeners.delete(res); }
  }
  eventLog.push({ type, ...payload, at: Date.now() });
  while (eventLog.length > 500) eventLog.shift();
}

function ask(id, message, timeoutMs) {
  const computer = computers.get(String(id));
  if (!computer) return Promise.reject(new Error(`computador ${id} nao esta conectado`));
  const reqId = nextRequestId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(reqId);
      reject(new Error('o computador nao respondeu a tempo'));
    }, timeoutMs || TIMEOUT);
    pending.set(reqId, { resolve, reject, timer });
    computer.ws.send(JSON.stringify({ ...message, id: reqId }));
  });
}

// ---------------------------------------------------------------- HTTP
function json(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*' });
  res.end(data);
}

function authorized(req) {
  const header = req.headers.authorization || '';
  const bearer = header.replace(/^Bearer\s+/i, '');
  const url = new URL(req.url, 'http://x');
  return bearer === TOKEN || url.searchParams.get('token') === TOKEN;
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => { data += c; });
    req.on('end', () => resolve(data));
  });
}

function computerList() {
  return [...computers.entries()].map(([id, c]) => ({
    id: Number(id), label: c.info.label, os: c.info.os, host: c.info.host,
    screen: c.info.screen, address: c.address,
    connectedAt: c.connectedAt, lastSeen: c.lastSeen,
  }));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const route = url.pathname;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    });
    return res.end();
  }

  // Ping publico: usado pelo botao "Testar" nas Configuracoes do OS.
  if (route === '/api/ping') return json(res, 200, { ok: true, name: 'mosaic-relay', computers: computers.size });

  if (route === '/' || route === '/index.html') {
    const file = path.join(__dirname, 'public', 'index.html');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(fs.readFileSync(file));
  }

  // Servir o /os do repositorio, para o computador do jogo puxar um arquivo alterado sem
  // passar pelo GitHub. E' so' para desenvolvimento: no jogo o caminho normal continua
  // sendo o app "Atualizar OS", que confere sha1 contra o manifest.
  //
  //   http.get("http://<relay>/dev/<token>/lib/powah.lua")
  //
  // O token vai no caminho porque o `http.get` do CC:T 1.101 aceita cabecalho, mas um
  // caminho simples e' menos coisa para errar de dentro do jogo. E o caminho e' resolvido
  // contra os/ e conferido depois: sem isso, "../../.." leria o disco inteiro.
  const dev = route.match(/^\/dev\/([^/]+)\/(.+)$/);
  if (dev) {
    if (dev[1] !== TOKEN) return json(res, 401, { error: 'token invalido' });
    const base = path.resolve(__dirname, '..', 'os');
    const file = path.resolve(base, dev[2]);
    if (!file.startsWith(base + path.sep) || !fs.existsSync(file)) {
      return json(res, 404, { error: 'nao encontrado' });
    }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end(fs.readFileSync(file));
  }

  if (!route.startsWith('/api/')) return json(res, 404, { error: 'nao encontrado' });
  if (!authorized(req)) return json(res, 401, { error: 'token invalido ou ausente' });

  try {
    if (route === '/api/computers' && req.method === 'GET') return json(res, 200, computerList());

    if (route === '/api/events') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      });
      res.write(`data: ${JSON.stringify({ type: 'hello', computers: computerList() })}\n\n`);
      listeners.add(res);
      req.on('close', () => listeners.delete(res));
      return;
    }

    const m = route.match(/^\/api\/computers\/(\d+)\/(.+)$/);
    if (!m) return json(res, 404, { error: 'rota desconhecida' });
    const [, id, action] = m;
    const body = req.method === 'GET' || req.method === 'DELETE' ? {} : JSON.parse((await readBody(req)) || '{}');

    const simple = {
      exec: () => ask(id, { type: 'exec', code: body.code }, body.timeout),
      shell: () => ask(id, { type: 'shell', cmd: body.cmd, cols: body.cols, rows: body.rows, timeout: body.timeout }, (body.timeout || 10) * 1000 + 5000),
      screen: () => ask(id, { type: 'screenshot' }),
      info: () => ask(id, { type: 'info' }),
      ps: () => ask(id, { type: 'ps' }),
      kill: () => ask(id, { type: 'kill', pid: body.pid }),
      launch: () => ask(id, { type: 'launch', path: body.path, args: body.args }),
      notify: () => ask(id, { type: 'notify', text: body.text, secs: body.secs }),
      inject: () => ask(id, { type: 'inject', name: body.name, args: body.args }),
      ls: () => ask(id, { type: 'fs.list', path: url.searchParams.get('path') || '/' }),
      reboot: () => ask(id, { type: 'reboot' }),
      shutdown: () => ask(id, { type: 'shutdown' }),
    };

    if (action === 'file') {
      const p = url.searchParams.get('path');
      if (!p) return json(res, 400, { error: 'informe ?path=' });
      if (req.method === 'GET') return json(res, 200, await ask(id, { type: 'fs.read', path: p }));
      if (req.method === 'PUT') return json(res, 200, await ask(id, { type: 'fs.write', path: p, content: body.content !== undefined ? body.content : '' }));
      if (req.method === 'DELETE') return json(res, 200, await ask(id, { type: 'fs.delete', path: p }));
      return json(res, 405, { error: 'metodo nao suportado' });
    }

    if (simple[action]) return json(res, 200, await simple[action]());
    return json(res, 404, { error: 'acao desconhecida: ' + action });
  } catch (err) {
    return json(res, 502, { error: err.message });
  }
});

// ---------------------------------------------------------------- WebSocket
const wss = new WebSocketServer({ server, path: '/ws/computer' });

wss.on('connection', (ws, req) => {
  const header = req.headers.authorization || '';
  if (header.replace(/^Bearer\s+/i, '') !== TOKEN) {
    ws.close(1008, 'token invalido');
    console.log(`[relay] conexao recusada (token) de ${req.socket.remoteAddress}`);
    return;
  }
  let id = null;
  const address = req.socket.remoteAddress;

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch (e) { return; }

    if (msg.type === 'hello') {
      id = String(msg.id);
      computers.set(id, { ws, info: msg, connectedAt: Date.now(), lastSeen: Date.now(), address });
      console.log(`[relay] computador #${id} (${msg.label || 'sem nome'}) conectado de ${address}`);
      broadcast('connected', { computer: computerList().find((c) => String(c.id) === id) });
      return;
    }

    if (id) computers.get(id).lastSeen = Date.now();

    if (msg.type === 'event') {
      broadcast('game_event', { computer: Number(id), name: msg.name, args: msg.args });
      return;
    }

    const wait = pending.get(msg.id);
    if (!wait) return;
    clearTimeout(wait.timer);
    pending.delete(msg.id);
    if (msg.ok) wait.resolve(msg.result === undefined ? true : msg.result);
    else wait.reject(new Error(msg.error || 'erro no computador'));
  });

  ws.on('close', () => {
    if (id && computers.get(id) && computers.get(id).ws === ws) {
      computers.delete(id);
      console.log(`[relay] computador #${id} desconectou`);
      broadcast('disconnected', { computer: Number(id) });
    }
  });
  ws.on('error', () => {});
});

server.listen(PORT, HOST, () => {
  const nets = require('os').networkInterfaces();
  const ips = [];
  for (const list of Object.values(nets)) {
    for (const n of list || []) if (n.family === 'IPv4' && !n.internal) ips.push(n.address);
  }
  console.log('');
  console.log('  Mosaic OS - relay');
  console.log('  ─────────────────────────────────────────────');
  console.log(`  Painel:      http://localhost:${PORT}/`);
  console.log(`  Token:       ${TOKEN}`);
  console.log('');
  console.log('  No jogo, em Configuracoes, coloque:');
  for (const ip of ips.length ? ips : ['<seu-ip>']) {
    console.log(`     ws://${ip}:${PORT}/ws/computer`);
  }
  console.log(`     token: ${TOKEN}`);
  console.log('');
  console.log('  Para o servidor do seu amigo enxergar seu PC, use o IP do Radmin/Hamachi');
  console.log('  (ou libere a porta no roteador). Detalhes em relay/README.md.');
  console.log('');
});
