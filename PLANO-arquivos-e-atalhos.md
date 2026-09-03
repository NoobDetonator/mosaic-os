# Plano: Mosaic OS — Arquivos, atalhos e área de trabalho como pasta

## Contexto

O que existe hoje: a área de trabalho desenha uma grade fixa vinda de `registry.builtin`
(9 apps com `desktop = true`), e o `os/apps/files.lua` é uma lista simples com quatro botões.
Não dá para tirar um ícone da área de trabalho, não existe atalho, não existe recortar/colar,
o clique direito só funciona em cima de um item da lista (nunca no vazio), a associação de
arquivo é um `if/elseif` cravado dentro do Files, e nada no OS sabe que existe drive de disquete
(`hal.types.drive` está declarado e nunca é usado).

Isso trava três coisas que você pediu: **criar atalho na área de trabalho** (não há onde guardar),
**mover apps para uma pasta** (não há mover), e **economizar espaço na área de trabalho conforme
o OS cresce** (cada app novo que eu adicionar entra na grade fixa).

Resultado pretendido: a área de trabalho vira a pasta `/home/desktop`, os apps moram numa pasta
`Programas`, atalho é um arquivo `.lnk` comum, o Files ganha barra lateral estilo Explorer com
Lugares e Discos (disquete incluído), e clique direito funciona em todo lugar — item, vazio,
ícone da área de trabalho e entrada do menu Iniciar.

## Decisões tomadas com você

- **Área de trabalho = pasta de verdade** (`/home/desktop`). Ícone é atalho, pasta ou arquivo.
- **Pasta Programas abre em janela de ícones**, igual pasta do Win95 — a grade vira um widget
  compartilhado (`ui.iconview`) usado pela área de trabalho e pelas janelas de pasta.
- **Apps do usuário (`/apps/*.lua`) vão para Programas**, não para a área de trabalho.
- **Disquete**: entra na seção Discos da barra lateral e a taskbar avisa; não abre janela sozinho.

Sem acento em nome de arquivo: a fonte do CC mapeia byte a byte e UTF-8 vira lixo na tela.
`/home/desktop`, `/home/programas`, `/home/downloads`, `/home/imagens`, `/home/documentos`.

---

## Onda 1 — Base invisível

Nada muda na tela. É a fundação de tudo que vem depois.

**`os/lib/shortcut.lua`** (novo) — atalho é uma tabela Lua serializada (`fsx.readTable`/`writeTable`),
extensão `.lnk`:

```lua
{ name = "Arquivos", app = "files" }                              -- aponta para um id do registry
{ name = "Programas", path = "/home/programas", icon = "folder" } -- aponta para uma pasta
{ name = "Rodar teste", path = "/apps/teste.lua", args = { "-v" } }
```

API: `read(path)`, `create(dir, spec)` (nome único via `fsx.uniqueName`), `resolve(tbl)`
(devolve `{ kind = "app"|"dir"|"file", path, name, icon }`), `open(tbl)`, `iconFor(entry)`
(dir → `folder`, `.lua` → `lua`, `.nfp` → `image`, `.lnk` → ícone do alvo, resto → `file`), `demo()`.

**`os/lib/clip.lua`** (novo) — área de transferência. `set(mode, paths)` com mode `"copy"`/`"cut"`,
`get()`, `clear()`, `paste(destDir)`. Duas guardas obrigatórias: colar pasta dentro dela mesma
(`dest:sub(1, #src) == src`) e destino somente-leitura (`/rom`). Conflito de nome resolve com
`fsx.uniqueName`. Vive na cache compartilhada do `mosaic.require`, então duas janelas do Files
enxergam o mesmo recorte.

**`os/lib/props.lua`** (novo) — diálogo de propriedades, usado por Files, área de trabalho e menu
Iniciar. Monta um `ui.dialog` com `ui.group`: nome, caminho, tipo, tamanho (`fsx.treeSize` para
pasta), somente-leitura, modificado em (`fs.attributes(path).modified` — **não** usar
`.isReadOnly`, é mais nova que 1.101). Para atalho, mostra também o alvo.

**`os/apps/registry.lua`** — passa a ser o único lugar que decide o que abre o quê:
```lua
registry.assoc = { nfp = { id = "paint" }, lua = { ask = true }, txt = { id = "editor" }, ... }
registry.byId(id)
registry.openFile(path, x, y)   -- resolve .lnk, pasta abre janela de icones, senao a associacao
registry.openWith(path, x, y)   -- menu "Abrir com"
```
O `if/elseif` de `files.lua:75-85` some e vira chamada a `registry.openFile`. O menu
Executar/Editar do `.lua` continua, mas aparece onde você clicou em vez de fixo em (4,4).

**`os/lib/hal.lua`** — `hal.drives()` sobre `peripheral.getType(name) == "drive"`, devolvendo
`{ side, present, mount, label, hasData, hasAudio }` via a API `disk`. Guarda `if not disk then
return {} end` porque o emulador em JS só tem o stub `disk.isPresent`.

**`os/kernel/ui.lua`** — suporte a `widget.hidden`: pular no `Form:draw`, no `widgetAt` e no
ciclo de foco. São ~5 linhas em três pontos, e é o que deixa a barra lateral sumir em tela
estreita sem gambiarra de largura zero.

*Verificação:* `lint` + `test.js` + `craftos test`; abrir um `.lua`, um `.nfp` e um `.txt` pelo
Files continua fazendo o mesmo de hoje.

## Onda 2 — Pastas padrão e a área de trabalho virando pasta

**`os/boot.lua`** — a lista da linha 48 ganha `/home/desktop`, `/home/programas`,
`/home/downloads`, `/home/imagens`, `/home/documentos`, e chama `registry.seed()` logo depois.

**`registry.seed()`** — idempotente e com memória. Guarda os ids já semeados em
`/os/var/seeded.json`; app que ganhou atalho uma vez e foi apagado por você **não volta** no
próximo update. Semeia builtins (`desktop = true` → `/home/desktop`, resto → `/home/programas`)
e um `.lnk` por `/apps/*.lua` em Programas. É chamado no boot e também no evento
`mosaic:apps_changed`, para app criado com o OS ligado aparecer sem reiniciar.

**`registry.builtin`** — `desktop = true` fica só em `files`, `terminal`, `settings`, `help`.
Editor, Rede, Perifericos, Tarefas e Reator saem para Programas. Mais o atalho semeado
`/home/desktop/Programas.lnk` → 5 ícones na área de trabalho, contra 9 hoje.

**`ui.iconview`** (em `os/kernel/ui.lua`) — a grade de ícones extraída de `desktop.lua`, agora
widget: `ICON_W/ICON_H`, `layout()` por largura, seleção, setas/Home/End/Enter, `onActivate`,
`onContext`, `onClickEmpty`, e **rolagem por linha** (hoje ícone que não cabe some calado).
`setEntries(list)` recebe `{ name, icon, path, isDir, lnk }`.

**`os/apps/desktop.lua`** — reescrito: lê `/home/desktop` com `fsx.listDetailed`, monta as
entradas com `shortcut.iconFor`, e entrega ao `ui.iconview`. Papel de parede, nome do computador
e o "não morre com terminate" continuam iguais. Sai a plaquinha de duas letras
(`desktop.lua:74-77`), que é código morto — `icons.draw` sempre cai no `app.nfp` e nunca devolve
`false`. Sai também `app.icon_file`, que nada no repositório define.

**`os/apps/folder.lua`** (novo, ~70 linhas) — janela de pasta: `ui.iconview` + rodapé com
contagem. É o que abre ao clicar em Programas.

**`tools/icons.js`** — arte nova de 12x12: `folder`, `file`, `image`, `disk` (disquete),
`drive` (disco do computador). `node tools/icons.js` regera; `node tools/manifest.js` já pega
qualquer arquivo novo sob `os/`.

*Verificação:* `craftos shot` da área de trabalho a 51x19 e 80x30 — cinco ícones, um deles pasta.
Abrir Programas mostra a grade com todos os apps.

## Onda 3 — Clique direito para valer

**Área de trabalho, em cima do ícone:** Abrir, Renomear, Excluir, Propriedades.
**Área de trabalho, no vazio** (via `onClickEmpty` do iconview): Nova pasta, Novo atalho,
Novo programa, Colar (só quando há recorte), Atualizar, Terminal, Configuracoes, Sobre.
O `ui.menu` corta em 10 linhas por padrão — a lista fica em 8.

**`os/apps/launcher.lua`** — `list.onContext` no menu Iniciar: "Criar atalho na area de trabalho"
e "Propriedades". *Ponto a conferir na implementação:* o launcher é popup que fecha ao perder o
foco; o menu de contexto é um `ui.dialog` no mesmo processo, então em tese o foco não sai, mas
isso precisa de teste real no CraftOS-PC, não só no emulador.

**Renomear atalho** renomeia o arquivo `.lnk` e o campo `name` dentro dele, senão o nome mostrado
e o nome do arquivo divergem.

*Verificação:* `craftos shot` com o menu aberto; criar atalho pelo Iniciar e conferir que ele
aparece na área de trabalho sem reiniciar (o desktop já escuta `mosaic:apps_changed`).

## Onda 4 — Explorer: barra lateral e discos

`os/apps/files.lua` ganha uma coluna esquerda de 13 colunas (`ui.list`, `x = 1`,
`fillTo = bar`), e o painel passa a `x = 14, w = -13`. As âncoras já resolvem isso sozinhas;
a ordem de inserção continua sendo: rodapé → fila de botões → lateral → painel.

Conteúdo: cabeçalho **Lugares** (Inicio, Area de trabalho, Programas, Downloads, Imagens,
Documentos, Apps), regra, cabeçalho **Discos** (Disco `/` e um item por disquete montado via
`hal.drives()`). Cabeçalho não seleciona.

**Disquete:** o Files trata `disk` e `disk_eject` recarregando a lateral; se a pasta aberta era
o disquete ejetado, volta para `/home`. O aviso da taskbar sai do `desktop.lua`, que é o processo
sempre ligado — `mosaic.notify("Disquete inserido")`. Eventos genéricos chegam a todos os
processos (é assim que o `periph.lua` já escuta `peripheral`).

**Tela estreita:** com `W < 46` a lateral fica `hidden` e o painel ocupa tudo; **F9** liga e
desliga. Sem isso, a 51 colunas sobrariam 38 para o painel e a 36 colunas (o caso do
`tools/debug.js`) o app ficaria inutilizável.

*Verificação:* `craftos shot files` a 80x30 e `node tools/debug.js os/apps/files.lua 36x10`.
Disquete só dá para testar no CraftOS-PC ou no jogo — o emulador tem `disk.isPresent` fixo em
`false`, e isso vai no relatório em vez de virar "testado".

## Onda 5 — Operações de arquivo

Menu de contexto do item, completo: Abrir, Abrir com…, Recortar, Copiar, Colar, Renomear,
Excluir, **Criar atalho na area de trabalho**, Propriedades.
Menu do vazio (`Form.onClickEmpty`, que existe em `ui.lua:758` e hoje nenhum app usa):
Colar, Nova pasta, Novo arquivo, Atualizar.

Teclado: **F2** renomear, **Del** excluir, **Ctrl+X/C/V**, **Backspace** subir (já existe),
**F5** atualizar. Ctrl+X/C/V são livres — os que o CC rouba são Ctrl+T, Ctrl+R e Ctrl+S.

Cópia de pasta grande passa por `ui.busy`. Erro de `fs.copy`/`fs.move` sempre em `pcall` com
`ui.msgbox`, como já é feito hoje.

*Verificação:* seção nova no `tools/test/run.lua` — recortar em uma pasta e colar em outra move
mesmo; colar pasta dentro dela mesma é recusado; colar em `/rom` dá erro tratado, não crash.

## Onda 6 — Testes, documentação e fechamento

- `tools/test/run.lua`: `demo()` de `shortcut`, `clip` e `props` (a convenção da casa — ver
  `lib/icons.lua:56`); `folder` entra na lista de smoke test da linha 166; checagens de
  semeadura idempotente, dispatch de associação, teclado do iconview e lateral escondida.
- `os/docs/`: guia "Arquivos e atalhos" para o app Ajuda.
- `CLAUDE.md`: formato do `.lnk`, tabela de associação, área de trabalho como pasta, `ui.iconview`,
  e o aviso de que `disk` não é testável no emulador.
- `node tools/manifest.js`, commit e push.

---

## Arquivos

**Novos:** `os/lib/shortcut.lua`, `os/lib/clip.lua`, `os/lib/props.lua`, `os/apps/folder.lua`,
`os/share/icons/{folder,file,image,disk,drive}.nfp`, doc em `os/docs/`.

**Reescritos:** `os/apps/desktop.lua`, `os/apps/files.lua`.

**Alterados:** `os/apps/registry.lua` (assoc, `openFile`, `byId`, `seed`), `os/kernel/ui.lua`
(`iconview`, `hidden`), `os/lib/hal.lua` (`drives`), `os/apps/launcher.lua` (contexto),
`os/boot.lua` (pastas + seed), `tools/icons.js`, `tools/test/run.lua`, `CLAUDE.md`.

**Reaproveitado sem mexer:** `fsx.listDetailed/uniqueName/treeSize/readTable/writeTable`,
`ui.menu/prompt/confirm/msgbox/busy/dialog/group/row`, âncoras `w="fill"`/`bottom`/`fillTo`,
`icons.draw`, `pixel.fromImage`, `mosaic.launchWith`, `mosaic.emit("apps_changed")`.

## Verificação (a cada onda)

```bash
node tools/lint.js && node tools/test.js && node tools/craftos.js test && node tools/craftos.js shot
```

`lint.js` continua sendo a autoridade sobre compatibilidade com a 1.16.5 — o CraftOS-PC 2.8 tem
ROM mais nova e não acusa API nova demais. Print a cada onda, para você julgar o rumo antes de eu
seguir para a próxima.

## Fora de escopo

Ícone com posição livre e salva (a grade continua automática; volta ao assunto se incomodar),
arrastar e soltar (o CC não manda evento de movimento do mouse), multi-seleção, lixeira,
busca de arquivo, visão de ícones dentro do Files (a lateral + lista é a visão de Explorer; a
grade fica nas janelas de pasta), e formatar/renomear disquete.


---

# Estado em 02/09/2026 — onde a obra parou

Commit feito no meio da onda 2, para trocar de PC. `node tools/lint.js` limpo (45 arquivos),
`node tools/test.js` e `node tools/craftos.js test` com 122 checagens e 0 falhas.

## Pronto e verificado

**Onda 1 inteira.**
- `os/lib/shortcut.lua` — le/grava/nomeia `.lnk`, `iconFor`, `sanitize`, `demo()`.
- `os/lib/clip.lua` — recortar/copiar/colar com as duas guardas (pasta dentro dela mesma,
  destino somente leitura), `demo()`.
- `os/lib/props.lua` — `props.lines()` (testavel sem tela) e `props.show()` (dialogo), `demo()`.
- `os/apps/registry.lua` — reescrito: `assoc`, `byId`, `openFile`, `openShortcut`, `openFolder`,
  `openEditor`, `openWith`, `seed`. As constantes `DESKTOP_DIR`, `PROGRAMS_DIR`, `SEED_FILE`.
- `os/lib/hal.lua` — `hal.drives()`.
- `os/apps/files.lua` — o `if/elseif` de associacao saiu; agora chama `registry.openFile`.

**Onda 2, metade.**
- `tools/icons.js` + `os/share/icons/` — arte nova: `folder`, `file`, `image`, `disk`, `drive`
  (22 icones no total, ja regerados).
- `os/kernel/ui.lua` — widget `ui.iconview` (grade, selecao, teclado, rolagem por linha,
  `onActivate`, `onContext`, `onEmpty`).
- `os/lib/fileops.lua` — entradas de pasta, acoes (nova pasta, novo arquivo, novo atalho,
  renomear, excluir, atalho na area de trabalho, colar) e os dois menus de contexto
  (`itemMenu`, `emptyMenu`). Ninguem chama ainda.

**Onda 2 fechada** (02/09, no PC de casa) — 123 checagens, 0 falhas no emulador E no CraftOS-PC.
- `os/apps/desktop.lua` — reescrito sobre o `ui.iconview` lendo `/home/desktop`. Cinco icones,
  um deles a pasta Programas. Papel de parede, nome do computador e o "nao morre com terminate"
  continuam. `disk`/`disk_eject` viram `mosaic.notify`.
- `os/apps/folder.lua` — janela de pasta com rodape de contagem, Backspace sobe um nivel na
  mesma janela e F5 atualiza.
- `os/boot.lua` — cria as cinco pastas de `/home` e chama `registry.seed()`.
- `registry.reseed()` — novo. Ver a armadilha do `seeded.json` abaixo.

**Ondas 3 e 4 fechadas** (02/09) — 135 checagens, 0 falhas no emulador E no CraftOS-PC.
- `launcher.lua` com `onContext`: Abrir, Criar atalho, Propriedades. O Iniciar SOBREVIVE ao
  proprio menu de contexto (era a duvida do plano), e tem teste que falha se deixar de sobreviver.
  O rotulo e "Criar atalho" e nao "Atalho na area de trabalho": o popup tem 24 colunas.
- `files.lua` com barra lateral: Lugares (7) + Discos, `hal.drives()`, F9, e ela some sozinha
  abaixo de 46 colunas. O painel se reposiciona pelo gancho `w.onLayout` do form.
- `api.screenSize()` novo, e `ui.list` ganhou `header` (cabecalho de secao que nao seleciona).

## Falta fazer, nesta ordem

1. Onda 5: menus e teclas do `files.lua` (F2, Del, Ctrl+X/C/V) sobre o `fileops` — hoje o
   `files.lua` ainda tem o menu de contexto ANTIGO, escrito na mao, em vez do `fileops.itemMenu`.
   F5 e Backspace ja existem.
2. Onda 6: `tools/test/run.lua` (demos de shortcut/clip/props/fileops), doc em `os/docs/`,
   `CLAUDE.md`, `node tools/manifest.js`. O smoke test do `folder` ja entrou.

**Nao testado, e nao da para testar aqui:** disquete. O emulador em JS tem `disk.isPresent`
fixo em `false` e o CraftOS-PC precisaria de uma imagem de disquete montada. O codigo trata
`disk`/`disk_eject` e volta para `/home` se a pasta aberta sumir, mas isso so' se confirma
no jogo.

## Armadilhas encontradas (nao repetir)

- **Heredoc do bash come barra invertida.** `cat > x.lua <<'EOF'` transformou `"[/\:*?...]"` em
  `"[/\:*?...]"`, criando o escape invalido `\:`. Escrever arquivo Lua com a ferramenta Write.
- **O `tools/lint.js` nao pega escape invalido de string** — o `\:` passou pelo luaparse e so'
  apareceu no CraftOS-PC. Vale melhorar o lint um dia.
- **`ui.lua` ja tem `visible ~= false`** em `draw`, `widgetAt`, `focusNext`, `contentHeight` e
  `pressMnemonic`. O `widget.hidden` que o plano previa nao precisa existir: basta
  `widget.visible = false`.
- **`registry.builtin` ja perdeu `desktop = true`** de Editor, Rede, Perifericos, Tarefas e
  Reator. Enquanto o `desktop.lua` nao for reescrito, a area de trabalho mostra so' 4 icones e
  a pasta Programas nao existe. Nao e' bug, e' obra no meio.
- **O `ui.iconview` abre com clique duplo**, e antes a area de trabalho abria com clique simples.
  Foi de proposito (sem isso nao da para selecionar um icone para renomear sem abrir o programa).
  **Confirmado com o usuario em 02/09: fica duplo mesmo.**

- **O `craftos.js` monta `/os` da propria pasta do repositorio** (`--mount-rw /os=<repo>/os`),
  entao tudo que o OS grava em `/os/var` cai no REPO e sobrevive ao `resetComputer()`. O
  emulador em JS mapeia `os/var` para o sandbox dele, que e' apagado — por isso os dois
  discordavam: no emulador a area de trabalho aparecia semeada e no CraftOS-PC vinha vazia,
  porque o `seeded.json` do repo dizia "ja semeei" e o `/home` tinha acabado de ser apagado.
  O `resetComputer()` agora limpa `os/var` tambem.

- **Isso expos um problema de verdade, nao so' de teste:** perder `/home` com o `seeded.json`
  intacto deixava a area de trabalho vazia PARA SEMPRE. Dai o `registry.reseed()`, que esquece
  a memoria e semeia de novo. Ele so' e' chamado quando a pasta inteira sumiu; apagar UM atalho
  continua sendo definitivo, como combinado.

- **O relogio do emulador so' anda quando um timer dispara** (`clock = bestAt`). Dois cliques
  separados por `proc.step()` ficam a um segundo um do outro e nunca passam pela janela de
  0,5 s do clique duplo. No `tools/debug.js` use `40,4d`: ele enfileira os quatro eventos antes
  de rodar o kernel, que e' o que acontece de verdade quando alguem clica rapido.
