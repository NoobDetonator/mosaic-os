#!/usr/bin/env node
// Servidor MCP: expoe os computadores do Minecraft como ferramentas para o Claude Code.
//
//   claude mcp add mosaic -- node <caminho>/relay/mcp.js
//
// Le o relay em MOSAIC_RELAY (padrao http://localhost:8765) com MOSAIC_TOKEN
// (padrao: o conteudo de relay/.token).
'use strict';
const fs = require('fs');
const path = require('path');
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { z } = require('zod');

const RELAY = process.env.MOSAIC_RELAY || 'http://localhost:8765';
const TOKEN_FILE = path.join(__dirname, '.token');
const TOKEN = process.env.MOSAIC_TOKEN
  || (fs.existsSync(TOKEN_FILE) ? fs.readFileSync(TOKEN_FILE, 'utf8').trim() : '');

async function api(route, options) {
  const res = await fetch(RELAY + '/api' + route, {
    ...options,
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + TOKEN },
  });
  const data = await res.json().catch(() => ({ error: 'resposta invalida do relay' }));
  if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status));
  return data;
}

const text = (value) => ({
  content: [{ type: 'text', text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }],
});

const server = new McpServer({ name: 'mosaic-os', version: '0.1.0' });

server.tool('list_computers', 'Lista os computadores do Minecraft conectados ao relay.', {}, async () =>
  text(await api('/computers')));

server.tool('computer_info', 'Detalhes de um computador: tela, espaco livre, perifericos conectados.',
  { id: z.number().describe('ID do computador') },
  async ({ id }) => text(await api(`/computers/${id}/info`)));

server.tool('exec_lua', 'Executa codigo Lua no computador e devolve o que foi impresso e retornado.',
  { id: z.number(), code: z.string().describe('codigo Lua, ex: return os.getComputerLabel()') },
  async ({ id, code }) => text(await api(`/computers/${id}/exec`, { method: 'POST', body: JSON.stringify({ code }) })));

server.tool('run_shell', 'Roda um comando do shell do CraftOS (ls, edit, programas) e devolve a saida.',
  { id: z.number(), cmd: z.string(), timeout: z.number().optional() },
  async ({ id, cmd, timeout }) => text(await api(`/computers/${id}/shell`, { method: 'POST', body: JSON.stringify({ cmd, timeout }) })));

server.tool('read_file', 'Le um arquivo do computador.',
  { id: z.number(), path: z.string() },
  async ({ id, path: p }) => text(await api(`/computers/${id}/file?path=${encodeURIComponent(p)}`)));

server.tool('write_file', 'Escreve (ou sobrescreve) um arquivo no computador.',
  { id: z.number(), path: z.string(), content: z.string() },
  async ({ id, path: p, content }) => text(await api(`/computers/${id}/file?path=${encodeURIComponent(p)}`,
    { method: 'PUT', body: JSON.stringify({ content }) })));

server.tool('list_files', 'Lista os arquivos de uma pasta do computador.',
  { id: z.number(), path: z.string().default('/') },
  async ({ id, path: p }) => text(await api(`/computers/${id}/ls?path=${encodeURIComponent(p)}`)));

server.tool('delete_file', 'Apaga um arquivo ou pasta do computador.',
  { id: z.number(), path: z.string() },
  async ({ id, path: p }) => text(await api(`/computers/${id}/file?path=${encodeURIComponent(p)}`, { method: 'DELETE' })));

server.tool('screenshot', 'Captura a tela do computador como texto (uma linha por linha da tela).',
  { id: z.number() },
  async ({ id }) => {
    const s = await api(`/computers/${id}/screen`);
    return text(s.lines.map((l) => l.text.replace(/\s+$/, '')).join('\n'));
  });

server.tool('launch_app', 'Abre um programa numa janela do Mosaic OS.',
  { id: z.number(), path: z.string().describe('ex: /os/apps/files.lua') },
  async ({ id, path: p }) => text(await api(`/computers/${id}/launch`, { method: 'POST', body: JSON.stringify({ path: p }) })));

server.tool('list_processes', 'Lista as janelas e servicos rodando no computador.',
  { id: z.number() },
  async ({ id }) => text(await api(`/computers/${id}/ps`)));

server.tool('kill_process', 'Fecha uma janela/processo pelo id.',
  { id: z.number(), pid: z.number() },
  async ({ id, pid }) => text(await api(`/computers/${id}/kill`, { method: 'POST', body: JSON.stringify({ pid }) })));

server.tool('notify', 'Mostra um aviso na tela do computador.',
  { id: z.number(), text: z.string(), secs: z.number().optional() },
  async ({ id, text: t, secs }) => text(await api(`/computers/${id}/notify`, { method: 'POST', body: JSON.stringify({ text: t, secs }) })));

server.tool('send_input', 'Envia teclas ou texto para o computador (como se voce digitasse).',
  {
    id: z.number(),
    event: z.enum(['char', 'key', 'paste', 'mouse_click']).describe('char=uma letra, key=codigo de tecla, paste=texto, mouse_click=clique'),
    args: z.array(z.any()).describe('argumentos do evento, ex: ["a"] ou [257,false] ou [1,10,5]'),
  },
  async ({ id, event, args }) => text(await api(`/computers/${id}/inject`, { method: 'POST', body: JSON.stringify({ name: event, args }) })));

async function main() {
  await server.connect(new StdioServerTransport());
}
main().catch((err) => {
  console.error('mosaic mcp:', err.message);
  process.exit(1);
});
