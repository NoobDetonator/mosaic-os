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

## Onda 2 — apps na parede: pronta, e MENOR que o planejado

O plano previa um registro de telas dentro do compositor: `wm.screens[n]`, cada um com seu
`root`, `canvas`, `W`, `H`, `last` e paleta. **Nao foi preciso, e o motivo importa:** aquele
desenho servia a "area de trabalho inteira no monitor", que nao foi a opcao escolhida.

Para um app por monitor em tela cheia, o compositor **nao entra**. Um app na parede e' um app
cujo `p.term` e' o monitor. Duas pecas ja existiam:

- `p.term` sempre pode ser qualquer terminal (o `net/relay.lua` ja usava isso para um shell
  sem janela), e o `proc.resume` devolve o redirect de volta a cada passo;
- `Form:draw` refaz o layout sozinho quando o terminal muda de tamanho, sem nem precisar de
  `term_resize`.

Entao: `proc.toMonitor(p, nome)` troca o terminal, aplica a paleta no monitor, encaixa a
escala e manda um `term_resize`. `proc.toScreen(p)` desfaz. O `wm.render` pula quem tem
`p.monitor` (senao a area de trabalho mostraria a janela congelada), e a barra de tarefas
poe o numero do monitor na frente do nome.

**A interface e' o botao direito no botao da barra de tarefas** — na barra de titulo o botao
direito ja redimensiona, e o Windows tambem poe o menu da janela ali.

**`hal.monitors()` e `hal.fitMonitor()`**: a politica de escala saiu do `reactor.lua`, onde
tinha sido decidida medindo no servidor, e virou compartilhada. O reator passou a usar a
versao comum — e de quebra ganhou a paleta no monitor, que ele nunca aplicava.

**Testado com dois monitores falsos de tamanhos diferentes**, no emulador e na ROM: ida,
volta, troca de monitor, monitor ocupado que expulsa o anterior, toque virando clique, foco
do teclado que nao pode ser roubado, e o bloco quebrado no jogo (`peripheral_detach`)
trazendo o app de volta.

## Tres correcoes que sairam no caminho

**Aviso tapava menu.** Toast e popup nascem no mesmo canto, em cima da barra de tarefas, e o
aviso era desenhado por ultimo. Um aviso de passagem cobria o menu que a pessoa acabou de
abrir. Agora popup vem depois do aviso: entre informar e deixar clicar, ganha deixar clicar.

**O `check()` do teste nao fotografava a tela ao falhar.** O `snap()` tinha que ser posto na
mao antes da checagem, ou seja, era preciso adivinhar qual ia quebrar. Agora ele fotografa
sozinho na primeira falha — foi o que explicou as duas falhas desta onda em um minuto.

**`toMonitor` relia o tamanho errado.** O `fitMonitor` mexe na escala, e a escala muda o
tamanho em caracteres: o que o `hal.monitors()` mediu antes ja estava velho.

## Onda 3 — o relay olha para fora: pronta

`relay/webdoc.js` (HTML -> blocos), `relay/gateway.js` (busca com teto e filtro de endereco) e
`relay/musica.js` (yt-dlp + ffmpeg -> DFPWM em pedacos). Cinco rotas novas: `/api/web`,
`/api/busca`, `/api/musica`, `/api/audio/<id>/<n>` e `/api/deps`.

Do lado do OS, `httpx` ganhou `getBinary` (audio nao sobrevive ao modo texto), e
`httpx.gateway()`, que **deduz o endereco HTTP do relay do websocket ja configurado** - duas
configuracoes dariam duas chances de discordar, e o app Configuracoes ja fazia essa conversao
escondida dentro do botao Testar.

**Sem dependencia nova no Node.** O relay continua com `ws` e mais nada: um analisador de HTML
de verdade (jsdom) custa dezenas de megabytes para um ganho que 51 colunas nao mostram.

### O que so' apareceu testando em pagina de verdade

O parser passou nos 32 testes de unidade e mesmo assim entregava lixo na Wikipedia. Tres
descobertas, cada uma virou codigo:

1. **`<main>` nao e' o artigo.** A Wikipedia poe o seletor de 143 idiomas dentro do `<main>`.
   Regra nova: entre os candidatos, o maior em texto ganha - mas um candidato **dentro** dele
   que guarda 60% do texto ganha, porque so' perdeu a moldura. Isso exigiu extrair `<div>`
   contando aninhamento: `[\s\S]*?</div>` para no primeiro fechamento, que e' de um filho.
2. **Nome de idioma em alfabeto nao latino vira uma linha de '?'.** Bloco com mais de 40% de
   interrogacao, ou sem nenhuma letra, e' descartado.
3. **Link sem texto virava a URL crua**, tres linhas numa tela de 51 colunas. Agora vira o
   ultimo pedaco do caminho.

Conferido em example.com, Hacker News, tweaked.cc e Wikipedia.

### O que nao deu para testar aqui

**`yt-dlp` e `ffmpeg` nao estao instalados nesta maquina.** Entao a cadeia de conversao esta
escrita mas nao foi exercitada de ponta a ponta. O que **foi** testado: a divisao em pedacos
(com arquivo sintetico), o teto de tamanho, o id que nao pode virar caminho de arquivo, e o
recado de dependencia faltando. O relay nao morre sem eles - `/api/deps` diz o que falta e as
outras rotas continuam de pe'.

## Onda 4 — musica: pronta, e provada de ponta a ponta

`os/net/musicd.lua` (a fila e o som) e `os/apps/music.lua` (a cara). A fila mora no servico:
fechar a janela nao para a musica, so' o botao Parar para.

**Medido de verdade, com yt-dlp e ffmpeg instalados:** 31 segundos do termo "c418 sweden
minecraft" ate' DFPWM tocavel. 216 s anunciados contra 215,6 s pelo tamanho do arquivo - a
conta fecha em 0,2%. 79 pedacos, o ultimo com a sobra (15.632 bytes), e o seguinte devolvendo
nada, que e' como o app sabe que acabou.

### Quatro coisas que so' apareceram tentando

1. **`yt-dlp -o -` para o ffmpeg nao funciona.** O formato sai fragmentado e o ffmpeg nao le
   isso de um cano sem busca: "Invalid data found when processing input". Arquivo
   intermediario, apagado depois.
2. **O YouTube devolveu HTTP 403** no download. Nao era o nosso codigo: o `yt-dlp` puro na
   linha de comando falhava igual. Medido: padrao, `tv` e `ios` deram 403; `web_safari` e
   `mweb` baixaram.
3. **Lista de clientes separada por virgula tambem falha.** O yt-dlp escolhe o formato com um
   cliente e baixa com outro. E' um cliente por tentativa, cada uma completa.
4. **A consulta de metadados tem que usar o cliente padrao.** Fixar um cliente ali quebrou com
   "Requested format is not available": nem todo cliente enxerga todos os formatos.

Se o YouTube mudar de novo, o conserto e' a variavel `MOSAIC_YT_CLIENTS`, nao o codigo.

### O desenho que a medida mudou

Preparar leva de 20 a 60 s e uma requisicao do CC morre em 30. Entao `/api/musica` **nao
espera**: dispara o trabalho, responde `{estado, espere=true}` na hora, e o servico pergunta
de novo ate' ficar pronto. O app mostra "Preparando: baixando..." enquanto isso.

### Teste

`tools/test/fake-periph.lua` ganhou um `http` falso por evento - o emulador nao tem rede e o
CraftOS tem rede **de verdade**, e nenhum dos dois serve para cobrar resposta conhecida. Com
ele o teste cobre: o "espere" que nao entra na fila, a musica pronta que entra sozinha pela
batida, tirar da fila, e o recado de relay ausente.

O trecho que toca audio de verdade **so' roda no CraftOS-PC**, onde existe `cc.audio.dfpwm`.
No emulador ele e' pulado - sem gancho falso, porque um teste que sempre passa nao e' teste.

### Um bug meu que valeu a licao

Sobrescrever `onKey` numa instancia de widget **mata a navegacao inteira**: o `onKey` vem da
classe (setas, Enter, PageUp). Guardar o original e chamar no fim.

## Onda 5 — browser: pronta

`os/apps/browser.lua`. A barra de endereco aceita as tres coisas que a pessoa digita
naturalmente e adivinha qual e': endereco abre, texto busca, e **um numero sozinho abre o
link daquele numero** - o jeito do lynx, que numa tela de 51 colunas ganha de qualquer
alternativa.

A quebra de linha e' feita no APP, nao no relay: so' o app sabe a largura da janela, e a
janela pode ser redimensionada ou mandada para um monitor.

Sem relay ele ainda abre texto puro e JSON por `http.get` direto, e diz que esta nesse modo -
melhor que uma janela que nao abre nada e nao explica por que.

Provado contra paginas de verdade, pelo relay, de dentro do CraftOS: `tweaked.cc` com 133
links, e uma busca com 10 resultados do DuckDuckGo.

## Onda 6 — fechamento: pronta

Tres capitulos novos em `os/docs` (som e musica, telas e monitores, navegador), README com os
quatro prints novos, `CLAUDE.md` com os fatos medidos, e o modo `live`.

---

# O bug que so' o uso encontrou

Depois da onda 4 pronta e testada, a musica **nao tocou** no primeiro uso de verdade. A fila
enchia e nada acontecia.

Nao era o daemon nem o relay: **faltava o alto-falante**. Mas dois defeitos meus faziam disso
um misterio em vez de um recado:

1. **Falta de hardware virava erro guardado.** O `ultimoErro` ficava com "sem alto-falante" e
   tapava a frase do app que ensina o que fazer. Erro velho na tela e' pior que nenhum: a
   pessoa conserta a coisa errada.
2. **Nada tentava de novo.** Grudar o alto-falante depois nao adiantava - era preciso
   descobrir sozinho que tinha que apertar Tocar. No jogo isso e' o caso NORMAL: gruda-se
   periferico com o computador ligado.

Agora falta de alto-falante nao e' erro, e a batida do servico religa a musica sozinha quando
ele aparece. Reproduzido e virou teste: tirar o alto-falante, conferir que nao virou erro,
grudar de volta, e cobrar que a musica comece sem ninguem mandar.

## Mais duas licoes de teste

**Contar passos nao serve nos dois mundos.** No emulador o relogio e' virtual e um
`proc.step()` custa nada; no CraftOS ele espera evento de verdade. Um laco de 80 passos
passava num e estourava o tempo no outro. Agora se espera pela CONDICAO.

**O `.settings` do CC e' tabela Lua, nao JSON** - e a falha e' silenciosa: o OS abre sem
relay e ninguem sabe por que.

## Falta

Nada do plano. O que ficou anotado de proposito, para depois:

- **Imagem no navegador.** O `lib/pixel` ja faz sub-pixel 2x3, entao o dificil esta pronto;
  falta um decodificador de imagem no relay, que e' dependencia nova.
- **Video.** A conta fecha na janela (~29 KB/s a 10 quadros), mas no monitor grande da
  ~310 KB/s e eu nao sei se aguenta. So' entra com numero medido.
- **Area de trabalho inteira no monitor**, sobre a mesma base da onda 2.
