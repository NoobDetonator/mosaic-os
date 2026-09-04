# Plano: o Mosaic sai do computador — som, monitores, internet

## Contexto

O Mosaic hoje é uma ilha. Fala com periféricos ao lado, fala com o relay para eu te ajudar
de fora, e para. Não faz som, não usa mais de uma tela, e não lê nada da internet que não
seja um `.lua` do próprio repositório.

Você quer três coisas que na verdade são uma só: **o computador deixar de ser um computador
e virar a casa inteira**. Um monitor na parede mostrando uma coisa, outro mostrando outra,
música tocando, e uma janela onde dá para abrir um link. Hoje isso custa um computador por
tela; a ideia é custar um computador só.

Decidido com você: **um app por monitor** (não área de trabalho completa), **o relay traduz
as páginas** (com `http.get` direto como reserva), **YouTube completo com yt-dlp + ffmpeg**,
e nesta ordem: som → monitores → relay → música → browser.

---

## O que a pesquisa mudou no desenho

Cinco fatos que eu não sabia quando você pediu, e que mexem no plano:

**1. Monitor dá para testar — só não no CraftOS-PC.** O headless recusa (`periphemu.create`
responde "Monitors are not available in this mode"), e o modo gráfico fotografa só a janela
do computador. Mas o `tools/emu/bios.lua` é nosso, e lá o `peripheral` é um toco de sete
linhas que devolve `nil` para tudo (`bios.lua:745-747`). Monitor falso e alto-falante falso
entram ali, com o mesmo padrão do `tools/test/fake-reactor.lua`. É teste de verdade, com
asserção, não "abriu e não quebrou".

**2. `window.reposition` aceita um pai novo desde a 1.85.0.** Quinto argumento, `new_parent`.
Isso significa que mandar uma janela existente para outra tela é **uma chamada**, sem recriar
processo. Nada em `os/` usa esse argumento hoje — vou provar que existe antes de me apoiar
nele.

**3. As janelas já se re-ajustam sozinhas a um tamanho novo.** `Form:draw` (`ui.lua:851-853`)
compara `t.getSize()` com o último tamanho e refaz o layout se mudou — sem precisar de evento
`term_resize`. Ou seja: apontar um form para uma superfície de outro tamanho **já funciona**.
As âncoras (`w`, `h`, `right`, `bottom`, `above`, `fillTo`) fazem o resto. Metade do "janelas
muito responsivas" que você pediu já está construída; o que falta é usar.

**4. Monitor só recebe clique de botão direito.** `monitor_touch` dá `(lado, x, y)` e nada
mais: **não existe arrastar nem soltar**, e teclado não existe de jeito nenhum. Foi o que me
fez recomendar um app por monitor — arrastar janela numa parede é impossível, não difícil.

**5. O `Websocket.receive` do 1.101 não diz se a mensagem é binária** (esse retorno é 1.117,
já proibido no `CLAUDE.md:17`). Então **áudio e imagem não vão pelo websocket**: vão por
`http.get(url, headers, true)` em modo binário, que o `httpx.download` já usa. O websocket
fica para controle, que é texto. Essa divisão não é preferência, é a API mandando.

Um detalhe menor para corrigir de passagem: o `CLAUDE.md:12` e o cabeçalho do
`os/lib/httpx.lua:2` dizem que a forma tabela do `http` só existe em 1.105+. Na verdade a
forma tabela do `get`/`post`/`request` é de 1.80pr1.6 e está liberada; o que é 1.105 é o
campo `timeout` e a forma tabela do **websocket**. Continuamos com argumento posicional de
qualquer jeito, mas a frase está errada e engana quem ler depois.

---

## Onda 1 — Som

Pequena, independente, e o retorno aparece no primeiro clique. `speaker.playAudio` e
`cc.audio.dfpwm` entraram na 1.100, então estão dentro do nosso alvo. Hoje o repositório
inteiro tem **um** uso de alto-falante: `clock.lua:58`, um sino no despertador.

**`os/lib/audio.lua`** — a camada única:

- `audio.speakers()` — todos, por nome, via `peripheral.getNames()` + `getType` (o
  `hal.findAll` existe mas perde o nome, e o nome é obrigatório: o evento
  `speaker_audio_empty` diz **qual** alto-falante vagou, e o laço canônico da documentação
  ignora isso e quebra com mais de um).
- `audio.note(nome, volume, tom)` e `audio.sound(evento)` — um envelope com `pcall` por cima
  de `playNote`/`playSound`. Limites reais: 8 notas por tique, e `playSound` só um som por
  vez.
- `audio.play(fonte)` — a fila de PCM. Recebe uma função que devolve o próximo pedaço de
  DFPWM; decodifica com **um decodificador por fluxo** (a documentação avisa em caixa que
  reaproveitar decodificador entre músicas estraga o som) e empurra em blocos de 16 KiB, que
  viram exatamente 128×1024 amostras — o máximo de uma chamada, ~2,7 s.
- Silêncio quando não há alto-falante. Nunca erro.

**Sons do sistema** — `os/lib/sfx.lua`, uma tabela de eventos → nota: abrir janela, fechar,
erro, aviso, boot. Chamados do `wm`/`proc`, com uma chave `mosaic.som.enabled` (padrão
ligado) e `mosaic.som.volume` no `settings`, definidas no `boot.lua` junto das outras.

**O risco medido, não suposto:** decodificar 16 KiB de DFPWM em Lua 5.1 pode ser lento o
bastante para engasgar. A própria documentação avisa que a primeira fornada pode estourar o
limite de 7 s e manda dormir 0,05 s. Entra no `bench.lua` uma linha de "decodificar um bloco
de 16 KiB", e o número vira decisão: se passar de ~50 ms, o daemon de música decodifica em
pedaços menores e mantém um colchão.

Teste: alto-falante falso no emulador que soma as amostras recebidas; a asserção é que
tocar 1 s de silêncio entrega 48.000 amostras.

---

## Onda 2 — Várias telas no kernel

A onda estruturante. Hoje o `wm` tem `root` e `canvas` como **duas variáveis de módulo**
(`wm.lua:22`), um `wm.W`/`wm.H` global, um `wm.last` de diff, uma barra de tarefas, um
`wm.slots`. Tudo singular.

**A mudança:** esse conjunto vira um registro de tela. `wm.screens[0]` é o computador;
`wm.screens[n]` é cada monitor. Cada um tem seu `root`, `canvas`, `W`, `H`, `last`, e sua
paleta.

- `wm.render` passa a receber uma tela e desenhar só os processos dela. O diff por linha
  continua idêntico — é por tela.
- **A paleta vai em cada monitor.** Monitor tem paleta própria; o `mirror.lua:14-17` já
  descobriu isso e o `reactor.lua` **não** aplica — é um bug de cor latente que essa onda
  conserta de graça.
- `p.screen` no processo. Mover = `p.win.reposition(x, y, w, h, outroCanvas)` e um
  `term_resize` para o app se re-ajustar (a documentação do `window` recomenda exatamente
  isso, e o `Form:draw` já reage sozinho).
- Barra de tarefas e menu Iniciar continuam **só na tela 0**. Um app por monitor: ele ocupa
  a parede inteira, sem cromo.

**Roteamento de evento**, seguindo a regra que o guia do Basalt já formulou e que é a única
que fecha: teclado e mouse vão para a tela 0; `monitor_touch` vai para o processo daquele
monitor, com a coordenada como está (o app ocupa a tela toda, então não há o que traduzir);
`monitor_resize` re-ajusta só aquela tela; timer e o resto continuam em difusão. Hoje
`monitor_touch` não é tratado em lugar nenhum do repositório — cai no `broadcast` do
`proc.lua:403` e chega cru em todo mundo.

**A interface:** botão direito na barra de título → "Enviar para monitor", com a lista de
monitores e o tamanho de cada um. E o inverso, "Trazer de volta". Um app na parede continua
na lista da barra de tarefas, marcado, para você não perder um processo de vista.

**Escala de texto:** aproveitar o `fitMonitor` do `reactor.lua:572-591`, que já resolve isso
com uma política pensada — 0,5 se render 56+ colunas, senão a **maior** escala que ainda
couber, porque ler de longe vale mais que caber apertado. Vira `hal.fitMonitor(mon, minW,
minH)` e o reactor passa a usar a versão compartilhada.

**Custo:** o `CLAUDE.md:180` já mediu — desenhar num monitor de 102x38 custa 7 ms contra 3 ms
da janela. Monitor não redesenha todo quadro; redesenha a cada N, como o `demos/modelo.lua`
já faz.

Teste: dois monitores falsos de tamanhos diferentes no emulador, um app mandado para cada,
e a asserção de que o conteúdo saiu no buffer certo, com o tamanho certo, sem sujar a tela 0.

---

## Onda 3 — O relay vira porta de entrada

O relay já é um processo Node no seu PC, com token, API HTTP, servidor de arquivos e
websocket. Falta ele saber olhar para fora.

Rotas novas, todas atrás do token que já existe:

- `GET /api/web?url=` — busca a página e devolve um **documento simples** em JSON: uma lista
  de blocos `{tipo, texto, href}` com título, parágrafo, lista, link, código, imagem. O Node
  faz o trabalho sujo (é onde tem biblioteca boa para isso); o computador só desenha. É a
  diferença entre o nosso browser e os browsers antigos de CC, que a própria pesquisa
  descreve como "bagunçados, sem imagem".
- `GET /api/busca?q=` — busca por texto, devolvida no mesmo formato de blocos.
- `GET /api/img?url=&w=&h=` — imagem já reduzida, já quantizada para os 16 da nossa paleta,
  já no formato de linha de `blit`. **A parte difícil disso já existe:** `lib/pixel` faz
  sub-pixel 2×3, então uma janela de 51x19 são 102x57 pontos e o computador só escreve.
- `GET /api/audio/<id>/<n>` — o enésimo bloco de 16 KiB de DFPWM. Binário.
- `GET /api/musica?q=` — resolve link ou nome, chama yt-dlp, converte com ffmpeg, devolve
  `{id, titulo, duracao, blocos}` e guarda em cache no disco do seu PC.

**Do lado do OS**, `os/lib/httpx.lua` ganha o que falta: `httpx.getBinary` com bloco por
caminho (não uso `Range`; o índice no caminho é menos coisa para dar errado), e
`httpx.stream`, que emite `http_success` para o app tratar no `onEvent` sem travar. A regra
do `CLAUDE.md:24` manda: processo é corrotina cooperativa, todo laço tem que ceder, e o CC
aborta em ~7 s.

**Duas armadilhas que já custaram caro e valem repetir:** o CC:T recusa faixa de IP privada
com "Domain not permitted" mesmo com o websocket funcionando no mesmo endereço — o endereço
do relay tem que ser o público (Radmin). E o computador só roda 16 requisições HTTP ao mesmo
tempo, com fila de 256 eventos: o player e o browser não podem disparar pedido sem limite.

**yt-dlp e ffmpeg** ficam como dependência declarada do relay, conferida na subida: se não
achar, o relay diz qual falta e as outras rotas continuam de pé.

---

## Onda 4 — Música

**`os/net/musicd.lua`** — daemon, no molde do `net/relay.lua`. É ele que segura a fila e
toca; o app é só a cara. Assim a música não para quando você fecha a janela, que é o
comportamento que qualquer um espera e que separa isto de um script.

- Fila de verdade: adicionar por link ou por nome, próxima, anterior, embaralhar, repetir.
- Colchão de dois blocos à frente, para o pedido HTTP não deixar buraco no som.
- Estado exposto como `mosaic.musicStatus()` e evento `mosaic:music_state`, exatamente como
  o relay faz com `mosaic.relayStatus()`.

**`os/apps/music.lua`** — fila na tela, o que está tocando, tempo, botões. Um campo onde
você cola link atrás de link e vai empilhando. Entra no `registry` com ícone e tamanho de
janela, e na lista de fumaça do `tools/test/run.lua:183`.

E como a onda 2 já existe: **mandar o player para um monitor** e ter a fila na parede.

---

## Onda 5 — Browser

**`os/apps/browser.lua`** — o app.

- Barra de endereço que aceita as duas coisas: se parece link, abre; senão, busca.
- O documento em blocos vira tela com quebra de linha, títulos destacados, links numerados e
  clicáveis, imagem desenhada no canvas de sub-pixel.
- Histórico, voltar, favoritos num JSON em `/os/var`.
- **Sem relay ainda funciona**, no modo pobre: `.txt` e JSON por `http.get` direto. O app diz
  em palavras que está sem o relay e o que isso custa — em vez de não abrir.
- E a ligação com a onda 2: **"Abrir no monitor"**, que é a sua ideia de ler uma página na
  parede.

---

## Onda 6 — Fechamento, e o experimento do vídeo

Documentação em `os/docs/` (som, telas, browser), `CLAUDE.md` com as convenções novas e os
números medidos, `manifest.json`, plano atualizado, commit e push.

**O vídeo fica como experimento declarado, não como promessa.** A conta fecha na janela: 51x19
são 969 células, uma tela inteira em `blit` são ~2,9 KB, e a 10 quadros por segundo dá 29 KB/s
— tranquilo, e o computador só escreve porque o relay já mandou quantizado. Num monitor de
131x79 o mesmo cálculo dá ~310 KB/s, e aí eu não sei se aguenta. Então: eu meço na janela
primeiro, e o monitor só entra se o número deixar. Se não deixar, vira linha de resultado
negativo no caderno de medidas, como os outros.

---

## Arquivos

**Novos:** `os/lib/audio.lua`, `os/lib/sfx.lua`, `os/lib/webdoc.lua` (o documento em blocos),
`os/net/musicd.lua`, `os/apps/music.lua`, `os/apps/browser.lua`, `tools/test/fake-periph.lua`
(monitor e alto-falante falsos), docs em `os/docs/`.

**Reescritos por dentro:** `os/kernel/wm.lua` (o registro de tela), `os/kernel/proc.lua`
(`p.screen`, roteamento de `monitor_touch`), `relay/relay.js` (as rotas novas).

**Alterados:** `os/lib/httpx.lua` (binário por bloco, fluxo, e a correção do comentário),
`os/lib/hal.lua` (`hal.monitors()` com nome, `hal.fitMonitor`), `os/kernel/palette.lua`
(aplicar por tela), `os/apps/registry.lua` (as duas entradas novas),
`os/apps/reactor.lua` (usar o `fitMonitor` compartilhado e aplicar a paleta no monitor),
`os/apps/settings.lua`, `os/boot.lua` (as chaves novas), `tools/emu/bios.lua` (periféricos
falsos e `http` mockável), `tools/test/run.lua`, `tools/test/bench.lua`, `CLAUDE.md`.

**Reaproveitado sem mexer:** `lib/pixel` como formato de imagem e vídeo, as âncoras do
`ui.form` para a responsividade, o padrão de daemon do `net/relay.lua`, o `registry.assoc`
para associação de arquivo, e o token e o servidor de arquivos que o relay já tem.

## Verificação

```bash
node tools/lint.js && node tools/test.js && node tools/craftos.js test
```

Regras que valem para todas as ondas:

- **`craftos.js test` ANTES de commitar, não depois.** Já subiu commit vermelho por inverter
  isso, e está anotado no `PLANO-3d.md` por causa disso.
- App novo entra na lista de fumaça do `run.lua`, e a checagem olha a **tela**, não só se o
  processo morreu — `holdOnError` mantém vivo um app que quebrou.
- Nada de rede pode travar o OS: todo pedido é assíncrono, todo laço cede.
- Todo módulo novo tem `demo()`, que o `run.lua` já roda em laço para as bibliotecas.
- Print depois de cada onda.

## Fora de escopo

Área de trabalho completa no monitor (fica para depois da onda 2, sobre a mesma base),
teclado na parede (o monitor não manda tecla), JavaScript e HTML de verdade no browser,
login em site, e vídeo no monitor grande antes de ter número que justifique.

---

# Estado em 04/09/2026

`node tools/lint.js` limpo, `node tools/test.js` e `node tools/craftos.js test` com
**182 checagens e 0 falhas** nos dois.

## Onda 1 — som: pronta

**`os/lib/audio.lua`.** Alto-falantes com nome (`audio.speakers()`), notas
(`audio.note`/`audio.sound`), sons do sistema por apelido (`audio.sfx`) e o fluxo de DFPWM
(`audio.stream`). O fluxo **nao tem laco por dentro**: quem chama e' dono do laco, porque um
`while not playAudio do pullEvent end` aqui dentro comeria os eventos do app.

**Sons ligados no kernel.** Abrir e fechar janela no `proc.lua`, erro no `proc.crash`, e o
sino de boot no `boot.lua`. Chaves `mosaic.som.enabled` e `mosaic.som.volume`, que aparecem
sozinhas no app Configuracoes (ele lista tudo que casa com `^mosaic%.`).

**`tools/test/fake-periph.lua`.** Alto-falante e monitor falsos, no molde do
`fake-reactor.lua`. O `find` devolve varargs, ao contrario do fake-reactor — sem isso
multi-monitor nao teria como ser testado. Ja deixa o monitor pronto para a onda 2.

**A medida que decidiu o desenho:** decodificar um bloco de 16 KiB custa **38 ms e rende
2,7 s de som** — ~1,4% de CPU. Entao o player decodifica o bloco inteiro de uma vez, sem
picar. Era a duvida que podia ter mudado a arquitetura do daemon, e nao mudou.

## Duas correcoes que sairam no caminho

**O `craftos.js test` saia com codigo 0 quando o teste abortava antes do resumo.** Um
`dofile` de arquivo que faltava derrubou o run.lua, a saida nao tinha linha de self-check, e
mesmo assim o comando "passou". E' exatamente o buraco que ja deixou subir um commit
vermelho. Agora, sem a linha do resultado, sai 1.

**`/test` passou a ser montado no CraftOS-PC.** O emulador proprio ja montava; o CraftOS nao,
entao apoio de teste carregado por caminho so' funcionava num dos dois.

**Documentacao corrigida:** o `CLAUDE.md` e o cabecalho do `httpx.lua` diziam que a forma
tabela do `http` e' 1.105. E' o campo `timeout` e a forma tabela do **websocket** que sao
1.105; a do `get`/`post`/`request` e' de 1.80pr1.6. Continuamos posicionais de qualquer jeito.

## Armadilhas ja encontradas (nao repetir)

- **`speaker_audio_empty` diz qual alto-falante vagou.** O laco canonico da documentacao
  ignora o nome e trava com mais de um alto-falante.
- **Um decodificador por fluxo.** Ele guarda estado do fluxo; reaproveitar entre musicas sai
  com o som errado.
- **`playNote` levanta erro em instrumento que nao existe** (e nao devolve false).
- **Um evento tem que tocar UM som.** Um crash chegava a tocar quatro: abrir, fechar do
  processo que caiu, erro, e abrir da janela de erro.
- **O emulador nao tem `cc.audio.dfpwm`** (a ROM dele so' tem `cc.require` e o shell). Por
  isso o decodificador e' injetavel: a logica de fila roda em qualquer lugar, e o codec de
  verdade e' exercitado pelo CraftOS-PC.

## Falta

Ondas 2 a 6: multi-tela no kernel, o relay como porta de entrada, musica, browser e o
fechamento. O plano acima esta inteiro.
