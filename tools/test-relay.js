#!/usr/bin/env node
// Teste de integracao do relay: sobe o servidor, conecta um computador falso que fala
// o mesmo protocolo do os/net/relay.lua, e exercita a API HTTP de ponta a ponta.
'use strict';
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('../relay/node_modules/ws');

const PORT = 8791;
const TOKEN = 'token-de-teste';
const BASE = `http://127.0.0.1:${PORT}`;
const relayPath = path.join(__dirname, '..', 'relay', 'relay.js');

let failures = 0, passed = 0;
const w = (s) => require('fs').writeSync(1, s + '\n');
function check(cond, msg) {
  if (cond) passed++;
  else { failures++; w(' - ' + msg); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(route, options = {}) {
  const res = await fetch(BASE + '/api' + route, {
    ...options,
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + TOKEN, ...options.headers },
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

// Computador falso: responde como o os/net/relay.lua responderia.
function fakeComputer(id) {
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws/computer`, { headers: { Authorization: 'Bearer ' + TOKEN } });
  ws.on('open', () => ws.send(JSON.stringify({ type: 'hello', id, label: 'teste', os: 'Mosaic OS 0.1.0', host: 'emu' })));
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    const reply = (ok, value) => ws.send(JSON.stringify(ok ? { id: msg.id, ok: true, result: value } : { id: msg.id, ok: false, error: value }));
    switch (msg.type) {
      case 'exec': return reply(true, { output: 'ola', returns: [String(id)] });
      case 'info': return reply(true, { id, label: 'teste', free: 12345 });
      case 'screenshot': return reply(true, { w: 3, h: 1, lines: [{ text: 'abc', fg: '000', bg: 'fff' }] });
      case 'fs.read': return reply(true, { path: msg.path, content: 'conteudo', size: 8 });
      case 'fs.write': return reply(true, { path: msg.path, size: (msg.content || '').length });
      case 'fs.list': return reply(true, { path: msg.path, entries: [{ name: 'os', path: '/os', isDir: true, size: 0 }] });
      case 'ps': return reply(true, [{ id: 1, title: 'Terminal', focused: true }]);
      case 'notify': return reply(true, true);
      case 'kill': return reply(false, 'processo nao encontrado');
      default: return reply(false, 'comando desconhecido: ' + msg.type);
    }
  });
  return ws;
}

(async () => {
  const relay = spawn('node', [relayPath], { env: { ...process.env, PORT: String(PORT), TOKEN }, stdio: 'ignore' });
  try {
    await sleep(900);

    const ping = await api('/ping');
    check(ping.status === 200 && ping.body.ok === true, 'ping do relay falhou');

    const noAuth = await fetch(BASE + '/api/computers');
    check(noAuth.status === 401, 'API aceitou requisicao sem token');

    const empty = await api('/computers');
    check(Array.isArray(empty.body) && empty.body.length === 0, 'lista deveria comecar vazia');

    const pc = fakeComputer(7);
    await sleep(500);

    const list = await api('/computers');
    check(list.body.length === 1 && list.body[0].id === 7, 'computador nao apareceu na lista');
    check(list.body[0].label === 'teste', 'label do computador nao chegou');

    const exec = await api('/computers/7/exec', { method: 'POST', body: JSON.stringify({ code: 'return 1' }) });
    check(exec.status === 200 && exec.body.output === 'ola', 'exec nao devolveu a saida');
    check(exec.body.returns[0] === '7', 'exec nao devolveu o retorno');

    const info = await api('/computers/7/info');
    check(info.body.free === 12345, 'info nao chegou');

    const screen = await api('/computers/7/screen');
    check(screen.body.lines[0].text === 'abc', 'screenshot nao chegou');

    const read = await api('/computers/7/file?path=/x.lua');
    check(read.body.content === 'conteudo', 'leitura de arquivo falhou');

    const write = await api('/computers/7/file?path=/y.lua', { method: 'PUT', body: JSON.stringify({ content: 'abc' }) });
    check(write.body.size === 3, 'escrita de arquivo falhou');

    const ls = await api('/computers/7/ls?path=/');
    check(ls.body.entries[0].name === 'os', 'listagem de pasta falhou');

    const ps = await api('/computers/7/ps');
    check(ps.body[0].title === 'Terminal', 'lista de processos falhou');

    const kill = await api('/computers/7/kill', { method: 'POST', body: JSON.stringify({ pid: 99 }) });
    check(kill.status === 502 && /nao encontrado/.test(kill.body.error), 'erro do computador nao virou erro HTTP');

    const missing = await api('/computers/99/exec', { method: 'POST', body: JSON.stringify({ code: 'x' }) });
    check(missing.status === 502 && /nao esta conectado/.test(missing.body.error), 'computador ausente deveria dar erro');

    // Eventos do jogo chegam pelo fluxo SSE
    const es = await fetch(BASE + '/api/events?token=' + TOKEN);
    const reader = es.body.getReader();
    await reader.read(); // hello
    pc.send(JSON.stringify({ type: 'event', name: 'redstone', args: [] }));
    const got = await Promise.race([
      reader.read().then((r) => new TextDecoder().decode(r.value)),
      sleep(2000).then(() => ''),
    ]);
    check(got.includes('game_event') && got.includes('redstone'), 'evento do jogo nao chegou no SSE');
    reader.cancel().catch(() => {});

    pc.close();
    await sleep(400);
    const after = await api('/computers');
    check(after.body.length === 0, 'computador nao saiu da lista ao desconectar');
  } catch (err) {
    failures++;
    w(' - excecao: ' + err.message);
  } finally {
    relay.kill();
  }

  w(`Relay integracao: ${passed} ok, ${failures} falhas`);
  process.exit(failures === 0 ? 0 : 1);
})();
