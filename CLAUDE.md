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
os/lib/*           -> chart, clip (recortar/colar), fileops (acoes + menus), fsx, hal (periféricos), httpx, icons (.nfp 12x12),
                      log, pixel (teletext 2x3), powah, props, shortcut (.lnk), strutil, vector (rasterizador)
os/net/*           -> relay.lua (websocket p/ relay Node), netd.lua (rednet entre computadores Mosaic)
os/docs/*          -> guias em markdown simples lidos pelo app Ajuda (entram no manifest)
os/apps/*          -> desktop, folder, launcher, registry, files, editor, netcenter, periph, taskman, settings, help, notes, calc,
                      clock, remote, reactor, pkg, mirror
relay/             -> relay.js (WS + HTTP API + dashboard), mcp.js (tools p/ Claude Code)
```

Fatos do kernel que não são óbvios:
- `Window.redraw()`/`restoreCursor()` não fazem nada em janela invisível → as janelas dos apps são copiadas
  para o canvas com `setVisible(true); setVisible(false)`.
- **O canvas NÃO vai para a tela por `setVisible`.** A API `window` fotografa a paleta do pai quando é criada
  e a reempurra a cada `redraw()`; usar `setVisible` no canvas seria 16 `setPaletteColour` por quadro,
  desfazendo a paleta do Win95. `wm.render` compara cada linha com `wm.last` e só faz `root.blit` no que mudou.
  Quem mexer em `wm.resize` tem que limpar `wm.last`, senão sobram linhas velhas na tela.
- A paleta (`kernel/palette.lua`) é aplicada em `root` **antes** de `wm.init`, pelo mesmo motivo.
  **O emulador em JS não reproduz nada disso** — valide com `node tools/craftos.js`.
- Root do WM é `term.current()` capturado no boot (não `term.native()`, pois o startup roda dentro do multishell da ROM).
- `term.redirect` é global: `proc.resume` faz `prev = term.redirect(p.term) ... p.term = term.redirect(prev)`.
- `terminate` ignora filtros de evento; vai só para o processo focado. `os.queueEvent` descarta funções → só ids.
- Programas externos rodam via `os.run(env, "/rom/programs/shell.lua", cmd, ...)`; o env recebe um `multishell` compatível
  para `shell.openTab`/`fg`/`bg` abrirem janelas.
- O app "Terminal" não é um arquivo: é a entrada `action = "shell"` do `apps/registry.lua`, que abre o shell da ROM numa janela.
- `ui.form` rola sozinho: `Form:draw` desloca `w.y` durante o desenho e devolve, e `Form:handle` soma `self.scroll` ao y do mouse.
  Nenhum widget sabe que existe scroll. Só `list` e `text` (com `scrollable = true`) consomem `mouse_scroll`; o resto deixa o form rolar.
- Widget com `pinned = true` não rola nem conta na altura rolável: é como se faz barra de abas/rodapé fixo (ver `apps/reactor.lua`).
- **A área de trabalho é a pasta `/home/desktop`**, não uma grade vinda do `registry`. Quem desenha é o
  widget `ui.iconview` (grade, seleção, teclado, rolagem por linha, `onActivate`/`onContext`/`onEmpty`), o
  mesmo das janelas de pasta (`apps/folder.lua`). As ações e os dois menus de contexto vivem em `lib/fileops`:
  app nenhum deve ter a própria cópia — o `files.lua` tinha, e ela divergiu antes de ser removida.
- **Ícone abre com clique DUPLO**, simples só seleciona. Sem isso não dá para escolher um ícone para renomear
  ou apagar sem abrir o programa junto.
- **Atalho é `.lnk`**: uma tabela Lua serializada (`fsx.readTable`/`writeTable`) com `app` (id do registry),
  ou `path` (+ `args` opcional), mais `name` e `icon`. Quem resolve é `lib/shortcut`; quem decide o que abre
  o quê é `registry.assoc` + `registry.openFile` — nunca um `if/elseif` dentro de um app.
- **`registry.seed()` tem memória** (`/os/var/seeded.json`): atalho que o usuário apagou não volta no próximo
  update. `registry.reseed()` esquece essa memória e só deve ser chamado quando a pasta inteira sumiu.
- **`fs.isReadOnly` não serve de guarda.** Medido no CraftOS-PC 2.8.3: responde `true` para **qualquer subpasta**
  e `false` só na raiz, mesmo onde `fs.move` funciona. Cheque `/rom` (garantido em toda implementação) e deixe
  o resto falhar dentro de `pcall`.
- **O relógio do emulador em JS só anda quando um timer dispara.** Dois cliques separados por `proc.step()`
  ficam a um segundo um do outro e nunca contam como duplo — use `40,4d` no `tools/debug.js`, que enfileira
  os eventos juntos.
- **Tela: 51x19 é o padrão, 80x30 é o alvo.** O tamanho vem do `computercraft-server.toml` do servidor, não do Lua.
  Nada no OS pode assumir 51x19: tudo lê `term.getSize()` e trata `term_resize`. `--size` no craftos.js só
  funciona no modo gráfico (`shot`); o headless sempre roda 51x19.
- Sub-pixel (`lib/pixel`) é 2x3 por célula, e uma célula com sub-pixel só aceita 2 cores e nenhum texto: serve para imagem, não para interface.
- Ícone pequeno é `.nfp` (`lib/icons`, 12x12 = 6x4 células), **não** vetor: nesse tamanho cada ponto é uma decisão
  de desenho e rasterizar borra. `lib/vector` é para o que precisa mudar de tamanho (logo, gráfico).
- Ícone não cabe na taskbar nem na barra de título: ocupa 4 linhas e essas barras têm 1.
- **A calculadora não usa `load`.** `lib/expr` é um analisador descendente recursivo: precedência de verdade,
  multiplicação implícita (`2pi`), fatorial, graus/radianos e variáveis. `expr.compile` prepara uma vez e
  devolve só o avaliador — é o que o gráfico usa, porque reanalisar o texto a cada coluna custaria mais que o desenho.
- **`expr.format` não usa `%g`.** O fengari devolve `100000000000000000000` onde o C devolveria `1e+20`.
  São três implementações de Lua rodando este código; quando o formato importa, decida no Lua e não no `string.format`.
- **O 3D é nosso (`lib/mesh` + `lib/three`), e o Pine3D continua proibido.** A arquitetura foi copiada dele
  (quadro, câmera, objeto, modelo, buffer) mas o código não: ele é dependência externa instalada por pastebin, e
  o nosso instalador é travado por sha1. Diferenças: saída em sub-pixel (102x57 em 51x19), z-buffer por ponto,
  cores pela paleta do Mosaic. `mesh.voxels` emite só a face que dá para fora — a esfera de 15 tem 1791 blocos
  e sai com 2124 triângulos em vez de 10746.
- **Antes de mexer no 3D, rode `node tools/craftos.js bench`** e leia [docs/3d-medidas.md](docs/3d-medidas.md),
  onde cada otimização tem previsão, medida e veredito. Medido no CraftOS-PC: cubo 0,26 ms, círculo 15 maciço
  1,00 ms, esfera oca 15 (3.768 triângulos) 4,70 ms, `canvas:render` 0,48 ms, contra 50 ms de um tique.
  ~877 mil triângulos por segundo. O relatório sai em `/out/bench.txt` e uma cópia fica em `docs/bench-ultimo.txt`.
- **O rasterizador é por varredura de linha, e o caminho comum não encosta em tabela.** Passar os vértices por um
  vetor para dar conta do polígono cortado custou 21 operações de tabela por triângulo e **dobrou** o tempo da cena
  de 10 mil. Em Lua sem JIT, abstração no caminho quente custa medivelmente caro.
- **Descarte de face de costas é propriedade da malha** (`m.closed`), não bandeira global: `mesh.voxels` e
  `mesh.cube` se declaram fechados; `plane` e `grid` não, e com descarte sumiriam vistos por baixo.
- **`pixel.cell6` recebe os seis sub-pixels soltos.** A versão com vetor custava doze operações de tabela por
  célula, e são 765 células numa tela. O laço de contagem é desenrolado de propósito.
- **`w = "fill"` e `w = -3` só viram número quando `Form:layout` roda.** Ler `widget.w` antes disso dá a string,
  e `"fill" - 2` derruba o app. Use `tonumber(w.w) or padrao` em qualquer código que rode antes do primeiro layout.
- **`x` não é chave de ancoragem.** Só `w`, `h`, `right`, `bottom`, `above` e `fillTo` são. `x = -20` não encosta
  nada na direita: desenha fora da tela.
- **O teste de fumaça de app olha a tela, não só se o processo morreu.** Com `holdOnError` o processo fica vivo
  mostrando o erro, então "não morreu" não prova nada.

## Como testar

- `node tools/lint.js` — sintaxe Lua 5.1 (luaparse) + grep de APIs proibidas. Rode antes de dizer que terminou.
- `node tools/test.js` — self-check do kernel no emulador embutido (`tools/emu`, fengari). Não precisa do CraftOS-PC.
- `node tools/debug.js os/apps/files.lua [36x10] [12,18] [fake]` — abre um app no emulador: tamanho de tela, cliques, e `fake` instala um reator do Powah de mentira (`tools/test/fake-reactor.lua`) para conferir o painel com dados variando.
- `node tools/emu/emu.js --show` — boota o OS de verdade e imprime a tela final; bom para conferir layout.
- `node tools/svg.js <arquivo.svg>` — converte SVG para o formato vetorial de `os/lib/vector` em `os/share/vectors/`. Le viewBox, rect, circle, polygon e path com M/L/H/V/Z; **nao le** transform, curva nem grupo (achate no editor antes).
- `node tools/icons.js` — regera os icones de `os/share/icons` a partir da arte em texto dentro do proprio script. `--from <pasta>` converte uma pasta de PNG (precisa de `npm install pngjs`).
- `node tools/craftos.js bench` — mede compositor, icone, vetor e passo do kernel. Otimizar com numero, nao com palpite.
- `node tools/manifest.js` — regenera `manifest.json` (usado por `install.lua` e pelo app `pkg`).
- `node tools/craftos.js <test|boot|app <nome>|exec "<lua>"|run <arquivo>>` — roda no **CraftOS-PC**
  instalado na máquina (implementação real do CC: ROM, shell, `edit`, `paint` e API `window` de verdade).
  Acha o executável sozinho no Windows, ou use a variável `CRAFTOS`.
  - `test` roda o mesmo `tools/test/run.lua` do emulador, mas contra a ROM verdadeira;
  - `boot` liga o OS e devolve a tela composta; `app <nome>` abre um app de `os/apps` e fotografa.
  - Como o relógio redesenha a cada segundo, a foto vem de dentro do OS (`mosaic.screenshotText`
    gravado em `/out`, via um app de autostart) e não do despejo do headless.
- **Cuidado com a versão do CraftOS-PC**: da 2.8 em diante ele traz uma ROM mais nova que a do alvo
  (Lua 5.2, CC:T 1.109+). Ele pega bugs de integração, mas **não** acusa API nova demais nem sintaxe
  de 5.2 — isso é papel do `tools/lint.js`, que continua sendo a autoridade. Para testar na ROM exata
  da 1.16.5, extraia `assets/computercraft/lua` do jar do mod e passe `--rom <pasta>`.
- Relay: `cd relay && npm install && node relay.js` → `http://localhost:8765`.
- `node tools/test-relay.js` — teste de integração do relay (sobe o servidor, conecta, fecha).
