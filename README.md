# Mosaic OS

Sistema operacional com janelas para [CC:Tweaked](https://tweaked.cc), escrito em Lua 5.1 puro —
sem Basalt, sem Pine3D, sem nenhuma dependência externa. Alvo: **Minecraft 1.16.5 / All The Mods 6**
(CC:Tweaked ~1.95–1.101, Advanced Peripherals 0.7.x).

![versão](https://img.shields.io/badge/versão-0.1.0%20"Tessera"-blue)

## Instalação

No computador do jogo (precisa ser **advanced computer** para mouse e cores, e a API `http`
tem que estar habilitada no servidor):

```
wget run https://raw.githubusercontent.com/NoobDetonator/mosaic-os/master/install.lua
reboot
```

O instalador guarda o `/startup.lua` que já existia como `/startup.old.lua` antes de sobrescrever.

### Atualizar

Pelo app **Atualizar OS** dentro do sistema, ou de novo pela linha de comando:

```
wget run https://raw.githubusercontent.com/NoobDetonator/mosaic-os/master/install.lua update
```

Ambos comparam arquivo por arquivo e só baixam o que mudou.

### Se algo quebrar

Crie o arquivo `/os/safemode` (`edit /os/safemode`, salve vazio) para o `startup.lua` pular o boot
e te deixar no shell da ROM. Apague o arquivo para voltar ao normal.

## O que vem dentro

**Kernel** — scheduler de processos em coroutines cooperativas, gerenciador de janelas com z-order,
arrastar/redimensionar e taskbar, e um toolkit de widgets próprio (`form`, `button`, `textbox`,
`list`, `checkbox`, `dropdown`, `progress`, modais).

**Aplicativos** — área de trabalho, terminal (shell da ROM em janela), arquivos, editor, centro de
rede, periféricos, gerenciador de tarefas, configurações, ajuda, notas, calculadora, relógio,
controle remoto e atualizador.

**Rede** — `netd` para conversar com outros computadores Mosaic via rednet, e `relay` para se
conectar por websocket a um servidor Node fora do jogo.

**Relay (`relay/`)** — servidor Node opcional que roda no seu PC: dashboard web para ver e controlar
os computadores do jogo, API HTTP, e um servidor MCP (`mcp.js`) para o Claude Code operar o
computador in-game direto.

## Desenvolvimento

```bash
cd tools && npm install     # luaparse + fengari
node tools/lint.js          # sintaxe Lua 5.1 + APIs novas demais para 1.16.5
node tools/test.js          # self-check do kernel no emulador CC embutido
node tools/manifest.js      # regenera o manifest.json usado pelo instalador

cd relay && npm install && node relay.js   # http://localhost:8765
node tools/test-relay.js                   # teste de integração do relay
```

As regras de código (o que é proibido usar por causa do Lua 5.1 e do CC:T antigo) estão em
[CLAUDE.md](CLAUDE.md) — vale a leitura antes de mandar PR.

## Estrutura

```
startup.lua          entrada, fica na raiz do computador
install.lua          instalador/atualizador
manifest.json        lista de arquivos + hashes (gerado)
os/boot.lua          inicializa settings, wm, kernel e daemons
os/kernel/           proc (scheduler), wm (janelas), ui (widgets), theme
os/lib/              fsx, hal (periféricos), httpx, log, strutil
os/net/              relay (websocket), netd (rednet)
os/apps/             aplicativos
relay/               servidor Node + dashboard + MCP
tools/               lint, emulador, testes, gerador de manifest
```
