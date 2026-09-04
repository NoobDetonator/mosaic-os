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

## Porta de entrada para a internet

O relay também é o caminho do computador do jogo para a web. Ele busca, limpa e devolve
pronto — no CC não cabe interpretar HTML (51 colunas, Lua 5.1, teto de 7 segundos por passo).

| rota | o que faz |
|---|---|
| `GET /api/web?url=` | busca a página e devolve blocos: título, parágrafo, lista, código, imagem |
| `GET /api/busca?q=` | busca no DuckDuckGo e devolve os resultados no mesmo formato |
| `GET /api/musica?q=` | resolve link **ou nome**, converte para DFPWM e devolve `{id, titulo, duracao, blocos}` |
| `GET /api/audio/<id>/<n>` | o enésimo pedaço de 16 KiB de áudio, cru |
| `GET /api/deps` | diz o que está instalado nesta máquina |

Todas exigem o token, menos `/api/ping`.

O texto volta **sem acento** de propósito: o terminal do CC desenha byte a byte, sem UTF-8, e
sem isso toda página em português vira lixo na tela.

**Endereço de rede local é bloqueado.** O relay roda na sua máquina; um computador do servidor
pedindo `192.168.0.1` faria dele um túnel para a sua rede de casa. O bloqueio é por IP
literal — um *nome* que resolve para endereço privado passa, então não exponha o relay a
quem você não conhece.

### Música precisa de dois programas

`yt-dlp` (baixa) e `ffmpeg` 5.1+ (converte para DFPWM). Sem eles o resto do relay continua
funcionando normalmente, e `/api/musica` diz qual está faltando.

```bash
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg
```

O áudio convertido fica em `relay/cache/`, e é reaproveitado: a mesma música só é baixada uma
vez. A busca por nome usa `ytsearch1:`, igual a um bot de música — você cola o link ou digita
o nome.

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
