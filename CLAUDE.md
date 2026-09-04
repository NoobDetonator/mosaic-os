# Mosaic OS — regras para IAs e desenvolvedores

Sistema operacional com janelas para **CC:Tweaked** rodando em **Minecraft 1.16.5 (All The Mods 6)**.
Isso significa CC:Tweaked ~1.95–1.101 e **Lua 5.1 (Cobalt)**. Advanced Peripherals 0.7.x (nomes camelCase).

## Regras de código (obrigatórias)

- **Lua 5.1 estrito.** Proibido: `goto`, `//`, `& | ~ << >>`, `_ENV`, `utf8.*`, `string.pack/unpack`, `table.move`,
  `coroutine.isyieldable`, escapes `\u{}`, `%g` em format, `math.tointeger/type/ult`. Bitwise: use `bit32`.
- `load(code, "=name", "t", env)` **sempre com env explícito** (pré-1.109 o `load` usa o env do chamador).
- **APIs do CC:T proibidas** (mais novas que 1.101):
  - Campo `timeout` em `http.get/post/request{...}` (1.105) e a **forma tabela do `http.websocket`/
    `websocketAsync`** (1.105) → use argumentos posicionais em tudo. (A forma tabela do `get`/`post`/
    `request` em si é de 1.80pr1.6 e seria permitida; posicional em tudo é mais fácil de conferir.)
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
os/lib/*           -> audio (alto-falante, sons do sistema, fluxo DFPWM), chart, clip (recortar/colar),
                      fileops (acoes + menus), fsx, hal (periféricos), httpx, icons (.nfp 12x12),
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
- **`.obj` do Blender é de mão direita; o Mosaic é de mão esquerda.** O `tools/obj.js` inverte o sinal de `z`
  na importação — sem isso o modelo sai espelhado, e espelhado quase não se nota num print. Depois dessa
  inversão a ordem dos cantos do `.obj` **já é** a do Mosaic (produto vetorial de mão direita apontando para
  dentro): não inverta de novo. As faces são conferidas uma a uma contra o `vn` do arquivo, e o conversor diz
  quantas corrigiu — se esse número explodir num modelo novo, é o exportador, não o leitor.
- **Modelo em arquivo é indexado, não uma lista de triângulos prontos.** `v` são os vértices (três
  números cada), `t` os triângulos (três índices em `v` mais o índice da cor em `cores`). Repetir os
  vértices da Suzanne — 507 para 968 triângulos — dava **105 KB**; indexado dá **33 KB**, e o computador
  do jogo tem 1 MB de disco no total. Quem desdobra é o `mesh.load`, uma vez, no carregamento.
- **`closed` do modelo importado é medido, não declarado**: toda aresta usada por exatamente duas faces significa
  casca fechada, e só aí o descarte de face é seguro. O leque de triangulação não atrapalha a conta (a diagonal
  aparece duas vezes, uma por triângulo).
- **`shade.applyTinted` escurece pela `shade.darker`**, uma tabela de "parente mais escuro" dentro das 16 cores
  (vermelho→marrom, lima→verde, rosa→magenta). Antes dela a sombra de qualquer cor virava cinza, e um modelo com
  quatro materiais aparecia monocromático. O piso é o **cinza**, nunca o preto: cor já escura demais (azul, roxo,
  marrom) cai nele mesmo sendo mais clara, senão some no fundo preto do canvas.
- **Num visualizador, a luz tem de acompanhar a câmera.** Luz parada no mundo deixa metade das voltas mostrando só
  o lado escuro. O `demos/modelo.lua` tira a direção da **mesma fórmula do `orbit`** (`-sin`, `-cos`) mais um ombro;
  escrever um ângulo de luz solto foi o que deixou a casa cinza duas vezes. E a componente vertical da luz é 0,5 e
  não 0,8: o vetor é normalizado, então luz muito de cima não sobra para os lados e as duas paredes visíveis caem
  as duas em cima do corte do `applyTinted`.
- **O `powah:reactor_part` É um inventário de 5 slots**, e é assim que se abastece o reator: ele responde
  `list`, `getItemDetail`, `getItemLimit`, `pushItems`, `pullItems`, `tanks`, `getEnergy` e
  `getEnergyCapacity`. Medido no servidor (CC:T 1.101.3 / MC 1.16.5): slot 1 vazio, 2 uraninita, 3 bloco de
  carvão, 4 bloco de redstone, 5 gelo seco, todos com limite 64, e o tanque com 1000 mB de água. O gelo seco
  **é consumido**; carvão e redstone ficaram parados no mesmo período.
- **Abasteça por NOME DE ITEM, nunca por índice de slot.** O Powah muda a ordem dos slots entre versões, e o
  slot 1 estar vazio enquanto o combustível mora no 2 já mostra que o número não significa nada. `powah.topUp`
  completa o que **já está** dentro do reator até um alvo: quem diz do que o reator precisa é o reator.
- **`pullItems`/`pushItems` só funcionam dentro da MESMA rede.** Um baú encostado no computador dá
  "Source does not exist" para um reator que vem por cabo. O app só lista inventários que podem funcionar.
- **O reator do Powah não tem liga/desliga**: o que liga é haver uraninita dentro. Por isso "Parar" é tirar o
  combustível e "Iniciar" é pô-lo de volta — o app tinha o primeiro sem o segundo desde o começo, e isso
  confundia todo mundo que abria a tela.
- **Barra cinza no vazio, e nenhum recurso pode ser cinza.** O bloco de carvão era `colors.gray`, a mesma cor
  do trecho vazio da barra: a barra dele ficava invisível. Virou marrom.
- **Gráfico de série que vive perto do máximo não pode ser preenchido.** Com `fill` e escala presa no zero, o
  buffer a 97% e a uraninita em 46 de 47 viravam retângulos sólidos de cor. Linha, escala automática, e a
  faixa escrita no título — aí o desenho mostra a forma sem mentir sobre a escala.
- **Painel de monitor reparte a altura, não desenha e para.** O teto de 7 linhas do gráfico deixava metade de
  um monitor alto cinza. Agora a sobra é dividida entre quantos gráficos couberem (4 linhas cada) e o último
  encosta embaixo.
- **Barras 3D num CÍRCULO, não em fileira**: em fileira, a meia volta da câmera você olha a fila de perfil e as
  colunas se escondem umas atrás das outras. E cor por **orientação da face** (topo na cor, lados um degrau
  abaixo por `shade.darker`), nunca Lambert — é a mesma lição do `mesh.voxels`: caixa alinhada aos eixos tem
  seis normais, e luz direcional joga metade delas no degrau escuro. Com Lambert as colunas saíram quase todas
  cinzas, com um fiapo da cor real.
- **O relay serve `/dev/<token>/<caminho>` a partir do `os/` do repositório**, para o computador do jogo puxar
  um arquivo alterado sem passar pelo GitHub: `http.get("http://<relay>/dev/<token>/apps/reactor.lua")`. Use o
  **IP público** (Radmin/Hamachi), não o da LAN: o CC:T recusa faixa privada com "Domain not permitted", mesmo
  com o websocket do relay funcionando pelo mesmo endereço.
- **`mosaic.lib` guarda o módulo em cache**: sobrescrever um `.lua` no computador não basta, o processo novo
  continua com o antigo. Reinicie o computador depois de trocar arquivo por fora.
- **O modo gráfico do CraftOS-PC NÃO existe no jogo, e é a armadilha mais cara que este projeto tem.**
  `term.setGraphicsMode`, `setPixel`, `drawPixels`, `getPixels`, `setFrozen`, `screenshot`, `showMouse`,
  `relativeMouse`, `periphemu` e `mounter` são extensões do emulador. O `term` do CC:Tweaked **não tem
  nenhuma função de pixel**, em versão nenhuma — a API inteira é `write`, `blit`, `clear`, `setCursorPos`,
  as cores e a paleta. Como o desenvolvimento roda no CraftOS-PC, isso funcionaria aqui e sumiria no
  servidor. O `tools/lint.js` barra todas.
  Números, medidos: modo gráfico dá **306x171 = 52.326 pixels com 256 cores** (6x9 por célula de texto);
  o nosso sub-pixel dá **102x57 = 5.814 com 16 cores, e só 2 por célula**. São 9x mais pixels e 16x mais
  cores que o jogo não tem. O caminho legítimo para mais área in-game é **monitor**, não pixel.
- **`Canvas:line` corta no retângulo ANTES do Bresenham** (Liang-Barsky). Sem isso o laço anda ponto a
  ponto fora da tela e o `Canvas:set` descarta em silêncio: uma aresta com vértice logo atrás da câmera
  projeta a milhões de pontos e **trava o computador nos 7 segundos**. É pré-requisito do modo arame,
  não um refinamento.
- **Modo arame (`draw(objs, { wire = true })`) não usa z-buffer** — a linha passa por cima de tudo. O
  z-buffer guarda a profundidade do que foi *pintado*, e no arame quase nada é pintado; esconder aresta
  seria remoção de linha escondida, outro assunto. O descarte de face continua valendo e já resolve
  metade do problema num modelo fechado.
- **Arame só se lê com pouco polígono.** A Suzanne de 968 triângulos em arame vira uma mancha cinza a
  100x51 sub-pixels: as arestas se encostam. E é mais *lenta* que a versão preenchida (6 ms contra 3),
  porque cada aresta interna é desenhada duas vezes e não há z-buffer para pular pixel.
- **`normalizeScale` não é enquadramento.** Ele põe a maior dimensão em 1, mas um cubo visto de canto
  ocupa a diagonal (1,73), e a escala do `three` sai de `w/2` nos **dois** eixos — numa janela mais larga
  que alta quem aperta é a altura. Enquadre pela esfera que envolve o modelo
  (`raio * begin().escala / (min(w,h)/2)`), que vale em qualquer ângulo e não muda enquanto ele gira.
- **Monitor: 102x38 na escala 0,5 = 204x114 pontos, e custa 7 ms** contra 3 ms da janela (Suzanne, 968
  triângulos). Vale desenhar nele a cada N quadros, não a cada um. Tudo dentro de `pcall`, e o monitor
  sai fora na primeira falha: no jogo alguém quebra o bloco com o computador ligado.
- **O CraftOS-PC headless não cria monitor** (`periphemu.create` responde "Monitors are not available in
  this mode"). Para testar monitor é preciso o modo gráfico, e aí o `term.screenshot` fotografa só o
  computador — a prova vem de `getSize()` e de o app não ter estourado, não de um print.
  **Mas dá para testar com periférico falso:** `tools/test/fake-periph.lua` sobrescreve o `peripheral`
  global (mesmo truque do `fake-reactor.lua`) e monta alto-falante e monitor. O `find` dele devolve
  **varargs**, como o do CC — o do `fake-reactor` devolve um só e não serve para multi-monitor.
- **Descarte de face de costas é propriedade da malha** (`m.closed`), não bandeira global: `mesh.voxels` e
  `mesh.cube` se declaram fechados; `plane` e `grid` não, e com descarte sumiriam vistos por baixo.
- **Não agrupe float por `string.format("%.0f")`.** O zero negativo vira `"-0"` em algumas
  implementações de Lua e `"0"` em outras: um teste de normais passava no emulador em JS e falhava
  na ROM do CraftOS-PC. Compare com `> 0.5` / `< -0.5`.
- **Iluminação: o degrau mais escuro da rampa de cinza é preto, e o fundo do canvas 3D também.**
  Face que cai nesse degrau some no fundo — o cubo do demo virou um losango achatado. Use
  `ambiente >= 0.3` numa rampa de quatro, ou fundo que não seja preto.
- **Luz direcional piora forma de voxel.** As faces são todas alinhadas aos eixos (seis normais),
  e uma rampa de quatro degraus joga as terraças em tons muito diferentes. O `topo/lado/base` do
  `mesh.voxels` é orientação, não direção, e por isso não cria assimetria. Medido e revertido.
- **`palette.render3d` preenche os buracos da rampa de cinza** (marrom, roxo, magenta e rosa viram
  48, 90, 160 e 224) sem tocar em preto, cinza, cinza claro e branco — a barra de tarefas e o relevo
  não mudam. Aplique no terminal **raiz** (`term.native()`), não na janela: janela do CC guarda a
  paleta só para si. Funciona porque o compositor não reempurra paleta, só faz `blit`.
- **`pixel.cell6` recebe os seis sub-pixels soltos.** A versão com vetor custava doze operações de tabela por
  célula, e são 765 células numa tela. O laço de contagem é desenrolado de propósito.
- **`w = "fill"` e `w = -3` só viram número quando `Form:layout` roda.** Ler `widget.w` antes disso dá a string,
  e `"fill" - 2` derruba o app. Use `tonumber(w.w) or padrao` em qualquer código que rode antes do primeiro layout.
- **`x` não é chave de ancoragem.** Só `w`, `h`, `right`, `bottom`, `above` e `fillTo` são. `x = -20` não encosta
  nada na direita: desenha fora da tela.
- **O teste de fumaça de app olha a tela, não só se o processo morreu.** Com `holdOnError` o processo fica vivo
  mostrando o erro, então "não morreu" não prova nada.

Som (`os/lib/audio.lua`, CC:T 1.100+):
- **48 kHz, amostra de 8 bits com sinal, no máximo 128×1024 amostras por `playAudio`** (~2,7 s). O DFPWM
  gasta 1 bit por amostra, então o bloco de 16×1024 bytes dá exatamente esse máximo. Essas três constantes
  são a mesma conta vista de três lados; se uma mudar, as outras mudam junto.
- **Decodificar um bloco custa 38 ms e rende 2,7 s de som** (CraftOS-PC). São ~1,4% de CPU: música toca
  praticamente de graça, e não precisa picar o bloco. No computador do jogo é mais lento, mas o limite dos
  7 s é por *resume*, não por segundo — o que pode aparecer é engasgo no primeiro bloco.
- **O evento `speaker_audio_empty` diz QUAL alto-falante vagou.** O laço canônico da documentação
  (`while not playAudio do pullEvent end`) ignora o nome e trava com mais de um alto-falante. Por isso
  `audio.speakers()` devolve o nome junto, e `hal.findAll` não serve aqui: ele perde o nome.
- **Um decodificador por fluxo.** Ele guarda estado; reaproveitar entre músicas sai com o som errado.
- **`playNote` aceita 8 notas por tique e `playSound` um som por vez.** `false` de volta é fila cheia, não
  erro. Instrumento que não existe **levanta erro** — por isso `audio.instruments` confere antes.
- **Som do sistema nunca pode derrubar o compositor.** No `proc.lua` a chamada é `pcall`, o módulo é
  carregado tarde, e computador sem alto-falante é o caso normal: vira silêncio, não erro.
- **Um evento, um som.** Um crash chegou a tocar quatro (abrir, fechar, erro, abrir da janela de erro).
  `spec.silent` no `proc.spawn` e `p.silent` existem para isso, e o teste conta os sons.

## Como testar

- `node tools/lint.js` — sintaxe Lua 5.1 (luaparse) + grep de APIs proibidas. Rode antes de dizer que terminou.
- `node tools/test.js` — self-check do kernel no emulador embutido (`tools/emu`, fengari). Não precisa do CraftOS-PC.
- `node tools/debug.js os/apps/files.lua [36x10] [12,18] [fake]` — abre um app no emulador: tamanho de tela, cliques, e `fake` instala um reator do Powah de mentira (`tools/test/fake-reactor.lua`) para conferir o painel com dados variando.
- `node tools/emu/emu.js --show` — boota o OS de verdade e imprime a tela final; bom para conferir layout.
- `node tools/svg.js <arquivo.svg>` — converte SVG para o formato vetorial de `os/lib/vector` em `os/share/vectors/`. Le viewBox, rect, circle, polygon e path com M/L/H/V/Z; **nao le** transform, curva nem grupo (achate no editor antes).
- `node tools/obj.js <arquivo.obj>` — converte um `.obj` do Blender (com o `.mtl` ao lado) para uma malha de `os/lib/mesh` em `os/share/models/`. Le `v`, `vn`, `f`, `usemtl` e `Kd`; **nao le** textura, curva nem transformacao. Carregue com `mesh.load()`.
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
