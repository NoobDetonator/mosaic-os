# Mosaic OS — regras para IAs e desenvolvedores

Sistema operacional com janelas para **CC:Tweaked** rodando em **Minecraft 1.16.5 (All The Mods 6)**.
Isso significa CC:Tweaked ~1.95–1.101 e **Lua 5.1 (Cobalt)**. Advanced Peripherals 0.7.x (nomes camelCase).

## Regras de código (obrigatórias)

- **Lua 5.1 estrito.** Proibido: `goto`, `//`, `& | ~ << >>`, `_ENV`, `utf8.*`, `string.pack/unpack`, `table.move`,
  `coroutine.isyieldable`, escapes `\u{}`, `%g` em format, `math.tointeger/type/ult`. Bitwise: use `bit32`.
- `load(code, "=name", "t", env)` **sempre com env explícito** (pré-1.109 o `load` usa o env do chamador).
- **APIs do CC:T proibidas** (mais novas que 1.101):
  - `http.get/post/request{ url=..., timeout=... }` e `http.websocket{...}` (forma tabela, 1.105) → use argumentos posicionais.
  - `textutils.serialiseJSON(t, {opts})` (1.106+) → use `serialiseJSON(t)`; `textutils.serialise(t, {compact=})` (1.97).
  - `fs.open(p, "r+")`/`"w+"` (1.109); `fs.find` com `?` (1.106); `fs.combine` com mais de 2 args; `fs.attributes().isReadOnly`.
  - `colors.fromBlit` (1.106) → `2 ^ tonumber(c, 16)`. `cc.expect.range` (1.96). `parallel.*` com arg `spawn` (1.120).
  - Hashbang em programas (1.103). Evento `file_transfer` (1.101) só opcional.
  - `Websocket.getResponseHeaders` (1.117); 2º retorno de `Websocket.receive` (1.117).
- Advanced Peripherals 0.7 (1.16.5): `peripheral.find("chatBox")`, `"playerDetector"`, `"environmentDetector"`,
  `"energyDetector"`, `"meBridge"`, `"rsBridge"`, `"inventoryManager"`, `"redstoneIntegrator"`, `"blockReader"`,
  `"geoScanner"`, `"NBTStorage"`, `"colonyIntegrator"`, `"arController"`. **Nunca** snake_case (`chat_box`).
- Nada de dependências externas (Basalt, Pine3D). `ui.lua` é o toolkit da casa.
- Nomes de código em **inglês**; textos de interface e docs em **PT-BR**.
- Cada módulo é `require`-ável (`return M`). Apps em `os/apps/*.lua` exportam `main(...)` **ou** são scripts comuns.
- Processos são coroutines cooperativas: **todo loop precisa fazer yield** (`os.pullEvent`, `sleep`) senão o computador trava (CC aborta em ~7 s).

## Arquitetura (resumo)

```
startup.lua        -> pcall(shell.run, "/os/boot.lua"); fallback p/ shell da ROM
os/boot.lua        -> settings, package.path, wm.init(term.current()), proc.init, spawn desktop + daemons, proc.run()
os/kernel/proc.lua -> scheduler: spawn/launch/resume/kill/terminate/setFocus/raise/list/step/run; multishell-compat
os/kernel/wm.lua   -> canvas offscreen (window.create(root,1,1,W,H,false)), z-order, hitTest, drag/resize, taskbar, screenshot
os/kernel/ui.lua   -> widgets (form/label/button/textbox/list/checkbox/dropdown/progress) + msgbox/confirm/prompt modais
os/kernel/theme.lua-> cores nomeadas
os/lib/*           -> fsx, hal (periféricos), httpx, log, pixel (teletext 2x3), strutil
os/net/*           -> relay.lua (websocket p/ relay Node), netd.lua (rednet entre computadores Mosaic)
os/docs/*          -> guias em markdown simples lidos pelo app Ajuda (entram no manifest)
os/apps/*          -> desktop, launcher, registry, files, editor, netcenter, periph, taskman, settings, help, notes, calc, clock, remote, pkg, mirror
relay/             -> relay.js (WS + HTTP API + dashboard), mcp.js (tools p/ Claude Code)
```

Fatos do kernel que não são óbvios:
- `Window.redraw()`/`restoreCursor()` não fazem nada em janela invisível → compositor usa `setVisible(true); setVisible(false)`.
- Root do WM é `term.current()` capturado no boot (não `term.native()`, pois o startup roda dentro do multishell da ROM).
- `term.redirect` é global: `proc.resume` faz `prev = term.redirect(p.term) ... p.term = term.redirect(prev)`.
- `terminate` ignora filtros de evento; vai só para o processo focado. `os.queueEvent` descarta funções → só ids.
- Programas externos rodam via `os.run(env, "/rom/programs/shell.lua", cmd, ...)`; o env recebe um `multishell` compatível
  para `shell.openTab`/`fg`/`bg` abrirem janelas.
- O app "Terminal" não é um arquivo: é a entrada `action = "shell"` do `apps/registry.lua`, que abre o shell da ROM numa janela.
- `ui.form` rola sozinho: `Form:draw` desloca `w.y` durante o desenho e devolve, e `Form:handle` soma `self.scroll` ao y do mouse.
  Nenhum widget sabe que existe scroll. Só `list` e `text` (com `scrollable = true`) consomem `mouse_scroll`; o resto deixa o form rolar.
- Sub-pixel (`lib/pixel`) é 2x3 por célula, e uma célula com sub-pixel só aceita 2 cores e nenhum texto: serve para imagem, não para interface.

## Como testar

- `node tools/lint.js` — sintaxe Lua 5.1 (luaparse) + grep de APIs proibidas. Rode antes de dizer que terminou.
- `node tools/test.js` — self-check do kernel no emulador embutido (`tools/emu`, fengari). Não precisa do CraftOS-PC.
- `node tools/debug.js os/apps/files.lua` — abre um app no emulador e mostra a tela, antes e depois de rolar.
- `node tools/emu/emu.js --show` — boota o OS de verdade e imprime a tela final; bom para conferir layout.
- `node tools/manifest.js` — regenera `manifest.json` (usado por `install.lua` e pelo app `pkg`).
- CraftOS-PC **v2.7.2** (ROM do CC:T 1.101.1; versões 2.8+ têm ROM Lua 5.2 e escondem bugs):
  `craftos --headless --script tools/test/run.lua --mount-rw /os=<abs>/os --directory <tmp>`.
- Relay: `cd relay && npm install && node relay.js` → `http://localhost:8765`.
- `node tools/test-relay.js` — teste de integração do relay (sobe o servidor, conecta, fecha).
