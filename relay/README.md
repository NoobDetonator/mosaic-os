# Relay

Ponte entre os computadores do Minecraft e o seu PC. Serve três coisas na mesma porta:

- **dashboard web** em `http://localhost:8765/` — ver e controlar os computadores conectados
- **API HTTP** em `/api/*` — o que o dashboard e o MCP consomem
- **websocket** em `/ws/computer` — onde os computadores do jogo se conectam

## Subir

```bash
cd relay && npm install
node relay.js
```

Ele gera um token em `relay/.token` na primeira execução e imprime os endereços que o computador
do jogo pode usar. Variáveis: `PORT=9000` para trocar de porta, `TOKEN=segredo` para fixar o token.

## Ligar o computador do jogo

No Mosaic OS: menu `M` → **Config** → preencher a URL e o token → **Testar** → **Salvar relay** → `reboot`.
O `boot.lua` só sobe o daemon do relay se `mosaic.relay.url` já estiver definido no boot.

Pelo terminal dá na mesma:

```
set mosaic.relay.url ws://SEU_IP:8765/ws/computer
set mosaic.relay.token o-token-do-arquivo
reboot
```

O botão **Testar** troca `ws://` por `http://` e bate em `/api/ping`. Isso testa a rede **sem** depender
do websocket — se o Testar passa mas a conexão não sobe, o problema é o websocket especificamente.

### Qual IP usar

Quem faz a conexão é o computador do jogo, saindo **de dentro do servidor** até o seu PC. Então o IP
tem que ser um que o *servidor* enxergue:

| situação | o que usar |
|---|---|
| mundo local / servidor na mesma máquina | `ws://localhost:8765/ws/computer` |
| servidor em outra máquina da mesma LAN | o IP LAN do seu PC (`192.168.x.x`) |
| servidor remoto, com Radmin/Hamachi | o IP da VPN (`26.x.x.x` no Radmin, `25.x.x.x` no Hamachi) |
| servidor remoto sem VPN | porta liberada no roteador, ou um túnel (Cloudflare Tunnel, ngrok) |

> **Atenção às regras do CC:Tweaked.** O mod bloqueia faixas privadas por padrão (`192.168.*`, `10.*`,
> `172.16-31.*`, `127.*`) na regra `$private` do `computercraft-server.toml`. Num servidor na mesma LAN
> isso **bloqueia** a conexão até o admin liberar aquele host. IPs de Radmin (`26.x`) e Hamachi (`25.x`)
> não caem nessa faixa, então passam nas regras padrão.

O servidor também precisa de `[http] enabled = true` e `websocket_enabled = true` no
`computercraft-server.toml`, e a porta do relay liberada no firewall do seu PC (entrada, TCP).

## MCP: deixar o Claude Code operar o computador

```bash
claude mcp add --scope user mosaic -- node /caminho/para/relay/mcp.js
```

É **stdio**, não HTTP — não adianta apontar um MCP HTTP para `http://localhost:8765/mcp`, essa rota não
existe (o `relay.js` devolve 404 para tudo fora de `/api/` e `/`). O `mcp.js` lê o relay em
`MOSAIC_RELAY` (padrão `http://localhost:8765`) e o token em `MOSAIC_TOKEN` (padrão: `relay/.token`).

Ferramentas expostas: `list_computers`, `computer_info`, `exec_lua`, `run_shell`, `read_file`,
`write_file`, `list_files`, `delete_file`, `screenshot`, `launch_app`, `list_processes`,
`kill_process`, `notify`, `send_input`.

## Testar sem o jogo

```bash
node tools/test-relay.js
```

Sobe o relay numa porta própria, simula um computador conectando, exercita a API e fecha.
