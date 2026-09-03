# Plano: expandir o 3D do Mosaic

## Contexto

O `lib/three` e o `lib/mesh` foram escritos numa onda só, para uma pré-visualização que gira em
volta de um objeto parado. Fazem isso bem — esfera de 15 (3768 triângulos) em 6,6 ms contra 50 ms
de um tique. Mas uma auditoria linha a linha achou o teto: **o motor não aguenta a câmera se
mexer**, e o caminho por pixel gasta muito mais do que precisa.

O achado que trava tudo: **não existe corte no plano próximo**. Em `three.lua:79`, vértice com
`bz <= 0.05` devolve `nil`, e o encadeamento `if ax / if bx / if cx` joga o **triângulo inteiro**
fora. Um triângulo com um vértice atrás da câmera deveria virar dois; hoje vira nada. Isso nunca
apareceu porque o único uso é uma órbita a distância fixa de um modelo normalizado, onde `bz` fica
entre 1,3 e 3,1. Qualquer câmera que ande faz a geometria perto sumir aos pedaços.

Fui atrás das referências e elas confirmam o caminho. O **Pine3D** — a biblioteca 3D mais rápida do
CC, que roda 20 mil polígonos a 20 fps em Lua normal — faz exatamente as quatro coisas que a
auditoria recomendou: rasteriza **por linha com passo de aresta** (não teste por pixel), profundidade
em **1/z**, **corta no plano próximo interpolando ao longo da aresta**, e **escreve direto na tabela**
(`colorsY[x] = c`, sem chamada de função). O `betterblittle`, que ele usa para a saída em sub-pixel,
guarda uma **matriz 16x16 de distância de cor em Oklab** e escolhe a segunda cor da célula pelo menor
erro — o nosso `pixel.cell` escolhe por frequência e joga a terceira cor na dominante.

Resultado pretendido: um motor 3D que aguenta câmera livre, mede várias vezes mais rápido, tem
iluminação, lê modelo feito no Blender, e um punhado de demos para provar cada coisa.

## Decisões tomadas com você

- **Conversor .obj**, no mesmo padrão do `tools/svg.js` que já existe.
- **Paleta própria vira experimento**, com print antes e depois. Se brigar com a barra de tarefas ou
  piscar, eu descarto — e digo que descartei.
- **Sem textura.** Nessa densidade ela vira chuvisco; o investimento vai para iluminação.
- **Demos em `/os/demos`**, invisíveis no Iniciar e em Programas, abertos pelo Arquivos.

---

## Onda 0 — A balança, antes de qualquer mudança

Não dá para testar hipótese sem régua, e a régua de hoje mente. Os três números do 3D no
`bench.lua` **incluem o `frame:clear`**, que sozinho é ~11.600 escritas de tabela e 57 alocações por
quadro — para o cubo de 12 triângulos, o clear provavelmente custa mais que o desenho. E o
`canvas:render`, que a calculadora paga todo quadro, **não é medido em lugar nenhum**.

`tools/test/bench.lua` ganha:

- medidas separadas de `frame:clear`, rasterização pura e `canvas:render`;
- a mesma cena com e sem descarte de face de costas;
- varredura de contagem de triângulos (100 / 1.000 / 10.000 com a mesma cobertura de tela), para
  separar o custo por triângulo do custo por pixel;
- **mediana em vez de média** e `collectgarbage()` entre medidas — hoje uma pausa do coletor dentro
  de um laço de 5 iterações domina o número;
- um "quadro completo como o app faz", com `pixel.new` + `three.frame` + `render`, porque o
  benchmark reutiliza canvas e quadro e o `calc.lua` **recria os dois todo quadro**.

`docs/3d-medidas.md` (só no repositório, não instala) vira o caderno: cada hipótese com o ganho
previsto, o ganho medido, e o veredito. **Hipótese que não se confirmar entra na tabela como não
confirmada** — é para isso que a tabela existe.

## Onda 1 — Correção: a câmera pode andar

**Corte no plano próximo** em `three.lua`, no espaço da câmera, antes da divisão de perspectiva:
zero, um ou dois vértices atrás → zero, dois ou um triângulo de saída, interpolando na aresta. É o
que o Pine3D faz. Sem isso nenhum demo com câmera livre existe.

Junto, três acertos pequenos que a auditoria achou:

- **`cam.rz` é guardado e nunca lido** — `setCamera(...,rz)` é um nada silencioso. Implementar (dá
  inclinação de voo) ou apagar. Vou implementar: são duas linhas na projeção.
- **A imagem inteira está meio sub-pixel acima e à esquerda**: `cx = canvas.w / 2`, mas o buffer
  começa em 1, então o centro é `(w + 1) / 2`. O próprio teste consagra o erro.
- **`frame:begin()`** devolvendo a tabela de senos e cossenos, para `map3dTo2d` parar de alocar uma
  tabela e chamar quatro trigonométricas **por ponto** — hoje qualquer legenda ou HUD em laço é
  proibitivo.

Teste: triângulo atravessando o plano próximo pinta pixel, e pinta do lado certo; câmera dentro de
um cubo vê as paredes de dentro em vez de nada.

**Demo `os/demos/terreno.lua`** — grade de altura com ruído e câmera que voa com WASD. É o demo que
prova o corte: sem ele, o chão some quando você chega perto.

## Onda 2 — Velocidade, uma hipótese por vez

Cada item vira um commit com número antes e depois. A previsão é minha; quem decide é a medida.

| # | Hipótese | Previsão |
|---|---|---|
| 1 | Ligar o descarte de face de costas. A auditoria conferiu o sinal na mão e os 6 lados do cubo e os 6 do voxel têm a mesma ordem de canto — **é seguro ligar hoje**. | ~50% dos triângulos saem antes de rasterizar |
| 2 | Escrever direto no buffer (`local row = buf[py]`, `row[px] = cor`) em vez de `canvas:set`, e invalidar o cache uma vez por quadro em vez de uma vez por pixel. | ~12 operações de tabela + 2 chamadas C viram 1 escrita |
| 3 | Rasterizar por linha com passo de aresta e `1/z` incremental, no lugar da caixa envolvente com teste baricêntrico por pixel. As duas coordenadas baricêntricas são afins em x e y: o corpo de 21 operações vira 3 somas. E só visita pixel coberto, em vez da caixa inteira. | 5x no laço interno |
| 4 | Guardar canvas e quadro entre desenhos no `calc.lua`. Hoje ele recria os dois todo quadro: limpa a tela duas vezes e faz o z-buffer crescer de zero a 4.590 entradas, com uma dúzia de recópias do vetor. | tira metade do custo fixo |
| 5 | `Canvas:clear` reaproveitar as tabelas de linha em vez de alocar 57 novas por quadro. | −57 alocações/quadro |
| 6 | `pixel.cell` reaproveitar as tabelas de contagem, e `Canvas:render` montar a linha inteira e mandar um `blit` por linha, como o `betterblittle`. | −~2.900 alocações por tela cheia |
| 7 | Cor do triângulo em `tri[10]` em vez de `t.c`, e normais em `tri[11..13]`. Hoje toda tabela de triângulo tem parte de vetor **e** parte de hash. | menos memória e menos coletor |
| 8 | `mesh.voxels` passar coordenada como número em vez de montar `{x,y,z}`. Hoje são milhares de tabelas descartáveis por malha. | montagem da malha mais rápida |

**Referência para saber se chegamos lá:** o Pine3D faz 20 mil polígonos a 20 fps em Lua normal, ou
~400 mil triângulos por segundo. Hoje estamos em ~570 mil triângulos por segundo no CraftOS-PC — mas
com triângulos minúsculos, então a comparação só fecha depois da varredura da onda 0.

**Demo `os/demos/bancada.lua`** — a bancada de teste: liga e desliga descarte, troca o rasterizador,
muda a contagem de triângulos, e mostra ms por quadro na tela. É o "testar hipótese" virando coisa
que você mesmo roda.

## Onda 3 — Iluminação, e o experimento da paleta

**`os/lib/shade.lua`** — Lambert por face: normal do triângulo (pré-calculada no modelo, não por
quadro) contra uma direção de luz, e o resultado escolhe um degrau da rampa.

As rampas que a paleta permite, medidas:

- **cinza**: `#000000` / `#808080` / `#C0C0C0` / `#FFFFFF` — luminância 0 / 128 / 192 / 255
- **quente**: marrom / vermelho / laranja / amarelo — 105 / 112 / 172 / 207
- **lavanda**: roxo / magenta / rosa — 124 / 163 / 194
- **verde**: só dois tons, 28 de diferença — inutilizável como rampa

**O problema, dito com número:** o degrau preto→cinza é 128 e os outros dois são 64 e 63. A paleta
do Win95 **piorou** isso: o CC de fábrica dá 17 / 76 / 153 / 240, com degraus de 59, 77 e 87. Uma
esfera sombreada vai ficar lisa na luz e em faixa dura na sombra.

**O experimento:** `kernel/palette.lua` ganha um mapa `render3d` que troca alguns slots pouco usados
por uma rampa de cinza uniforme. Um demo em tela cheia aplica ao entrar e restaura ao sair — o mesmo
`apply`/`restore` que o boot já usa. Print com e sem, lado a lado.

**Onde isso pode dar errado, e como eu vou saber:** a API `window` fotografa a paleta do pai ao ser
criada e a reempurra a cada `redraw()` — é a armadilha que já derrubou a paleta do Win95 uma vez e
está no CLAUDE.md. Se a barra de tarefas piscar de cor, ou se a paleta não voltar ao sair, o
experimento morre e vai para o `docs/3d-medidas.md` como não confirmado.

Uma coisa que **não** adianta: mais tons. Célula de sub-pixel aceita duas cores, e o `pixel.cell`
joga fora a terceira — rampa mais fina aumenta o número de células com três cores e pode ficar
**pior**. O caminho certo para gradiente é pontilhado ciente da grade 2x3, e isso fica anotado, não
feito.

**Demo `os/demos/cubo.lua`** — cubo girando com temporizador, contador de quadros por segundo e a
luz mudando de direção. É o "olá mundo" do motor e o print da onda.

## Onda 4 — Modelo de verdade

**`tools/obj.js`** — lê `.obj` do Blender (`v`, `vn`, `f`, `usemtl`) e o `.mtl` ao lado para pegar a
cor difusa de cada material, casa cada cor com a paleta do Mosaic (que difere da do CC em 7 slots) e
grava `os/share/models/*.lua` no nosso formato. Triangula face de 4 lados ou mais; avisa e pula o
que não entender, como o `svg.js` faz.

**`mesh.load(caminho)`** com o mesmo cuidado do `vector.load`: `loadfile` com ambiente restrito e a
volta para o `loadfile` antigo em CC pré-1.109.

**Demo `os/demos/modelo.lua`** — visualizador: lista o que está em `os/share/models`, abre, gira,
mostra contagem de triângulos e ms por quadro.

## Onda 5 — Sair da janelinha

Duas coisas que multiplicam o alcance e são baratas depois das ondas anteriores:

- **Desenhar em monitor.** `hal.monitor()` já existe e o `reactor.lua` já tem o padrão de "renderiza
  em qualquer terminal". Um monitor avançado 8x6 dá 131x79 caracteres, ou **262x237 pontos** — quatro
  vezes a área da tela do computador. Uma parede de monitores com 3D rodando é o tipo de coisa que
  justifica o motor inteiro.
- **Modo arame**, usando `Canvas:line`. Antes disso, **cortar a linha no retângulo do canvas**: hoje
  o Bresenham do `pixel.lua` anda ponto a ponto mesmo fora da tela, e uma linha que sai muito longe
  trava o computador nos 7 segundos.

## Onda 6 — Fechamento

- `tools/test/run.lua`: os demos entram no teste de fumaça; `three.demo()` ganha os casos de corte.
- `os/docs/`: capítulo sobre o 3D e os demos.
- `CLAUDE.md`: as convenções do motor (mão esquerda, +z para dentro, ordem de canto, `cull` ligado)
  e os números novos do bench.
- `docs/3d-medidas.md` fechado, com o que se confirmou e o que não.
- `node tools/manifest.js`, commit e push.

---

## Arquivos

**Novos:** `os/lib/shade.lua`, `os/demos/{cubo,bancada,terreno,voxel,modelo}.lua`, `tools/obj.js`,
`os/share/models/`, `docs/3d-medidas.md`, doc em `os/docs/`.

**Reescritos por dentro:** `os/lib/three.lua` (corte, rasterizador por linha, escrita direta,
`begin`), `os/lib/pixel.lua` (clear, `cell`, `render`, corte de linha).

**Alterados:** `os/lib/mesh.lua` (normais, `tri[10]`, menos alocação, `load`), `os/apps/calc.lua`
(canvas e quadro guardados), `os/kernel/palette.lua` (mapa `render3d`), `tools/test/bench.lua`,
`tools/test/run.lua`, `tools/craftos.js`, `CLAUDE.md`.

**Reaproveitado sem mexer:** `pixel.Canvas` como formato de saída, `mcmath.build` como fonte de
voxel, o padrão de temporizador do `clock.lua`/`reactor.lua` para animação, `hal.monitor()`,
`ui.form` com `f.onDraw` para o desenho, e o `palette.apply`/`restore` do boot.

## Verificação

```bash
node tools/lint.js && node tools/test.js && node tools/craftos.js test
node tools/craftos.js bench          # antes e depois de cada hipotese da onda 2
node tools/craftos.js shot cubo      # cenario novo por demo
```

Regra da onda 2: **nenhuma otimização entra sem número antes e depois**, e o desenho tem de sair
idêntico — o teste do z-buffer que já existe (o cubo da frente ganha do de trás em qualquer ordem)
é a rede de segurança contra rasterizador novo com bug.

Lembrete que vale repetir: o CraftOS-PC é mais rápido que o computador do jogo, e a ROM dele é mais
nova que a da 1.16.5. Os números medem proporção, não o que você vai sentir no servidor.

## Fora de escopo

Textura com UV (vira chuvisco nessa densidade — decidido com você), sombra projetada, nível de
detalhe automático, transparência (não existe alfa no CC), pontilhado ciente da célula (anotado na
onda 3, não feito), e física.


---

# Estado em 03/09/2026

`node tools/lint.js` limpo (54 arquivos), `node tools/test.js` e
`node tools/craftos.js test` com **165 checagens e 0 falhas**.

O caderno de medidas com previsao, medida e veredito de cada hipotese esta em
[docs/3d-medidas.md](docs/3d-medidas.md). A ultima medida fica em `docs/bench-ultimo.txt`,
e `docs/bench-base.txt` guarda a linha de base para dar diff.

## Ondas 0 a 5: prontas

**Onda 0 — a balanca.** `tools/test/bench.lua` reescrito: mediana de 5 rodadas com
`collectgarbage()` antes de cada uma, min e max no relatorio, `clear` e `render` medidos
sozinhos, descarte de face ligado e desligado, e varredura de 98 / 968 / 10.082 triangulos com a
**mesma cobertura de tela** (separa custo por triangulo de custo por pixel). O relatorio passou
das 19 linhas do terminal e sumia: agora sai em `/out/bench.txt` e o `craftos.js` imprime inteiro.

**Onda 1 — corte no plano proximo.** Sutherland-Hodgman contra `z = NEAR` no espaco da camera.
Junto: `cam.rz` implementado (era guardado e nunca lido), meio sub-pixel de deslocamento
corrigido, e `frame:begin()` para quem desenha em laco.

**Onda 2 — velocidade.** Cinco commits, cada um com numero antes e depois:

| Medida | base | agora | ganho |
|---|---:|---:|---:|
| `canvas:render` | 1,68 | 0,48 | 3,5x |
| cubo, 12 tri | 1,22 | 0,26 | 4,7x |
| circulo 15, 828 tri | 2,20 | 1,00 | 2,2x |
| esfera oca, 3.768 tri | 11,80 | 4,70 | 2,5x |
| grade, 10.082 tri | 17,45 | 11,70 | 1,5x |
| quadro completo | 4,35 | 1,55 | 2,8x |

Custo por triangulo: 1,69 -> 1,14 us (~877 mil por segundo).

**Onda 3 — iluminacao.** `os/lib/shade.lua`: Lambert por face, normal pre-calculada em
`tri[11..13]` (uma vez por malha, nao por quadro), e o resultado caindo num degrau de rampa.
`shade.applyTinted` para malha que ja tem cor propria. O experimento da paleta foi
**confirmado**: `palette.render3d` preenche os buracos da rampa de cinza (marrom, roxo, magenta e
rosa viram 48, 90, 160 e 224) sem tocar em preto, cinza, cinza claro e branco, entao a barra de
tarefas e o relevo nao mudam. Tecla P no demo do cubo liga e desliga; a paleta volta ao sair,
inclusive pelo X da janela.

Tres resultados negativos, todos no caderno: o degrau mais escuro da rampa e' preto e o fundo
tambem (as faces de costas sumiam), luz direcional **piora** forma de voxel (revertida na
calculadora), e agrupar float por `string.format("%.0f")` passava no emulador e falhava na ROM.

**Onda 4 — modelo de verdade.** `tools/obj.js` le `.obj` do Blender com o `.mtl` ao lado, casa cada
`Kd` com a paleta do Mosaic e grava `os/share/models/*.lua`. Duas conversoes que ele faz calado:
inverte o sinal de `z` (o `.obj` e' de mao direita, o Mosaic de mao esquerda) e confere a ordem
dos cantos de cada face contra o `vn` do arquivo, dizendo quantas corrigiu. `closed` nao e'
declarado, e' **medido**: toda aresta usada por exatamente duas faces significa casca fechada, e so'
ai o descarte de face e' seguro.

O arquivo e' **indexado**: `v` com tres numeros por vertice, `t` com tres indices e a cor por
triangulo. Repetir os vertices da Suzanne (507 para 968 triangulos) dava **105 KB** contra **33 KB**
assim, e o computador do jogo tem 1 MB de disco no total.

`mesh.load()` le esse arquivo com ambiente restrito, como o `vector.load`, desdobra os indices uma
vez, e recusa modelo estragado com mensagem em vez de derrubar o app no meio do rasterizador —
indice fora da lista, lista pela metade, cor que nao existe. `mesh.list()` diz o que esta instalado.

Os dois modelos que acompanham: a `casa` e a **Suzanne do Blender** (`monkey`, 968 triangulos,
exportada da 5.2 com Forward -Z / Up Y). A Suzanne desenha em **3 ms**, dentro dos 50 ms de um
tique, e o conversor nao teve nenhuma face para corrigir nela.

O modelo de prova e' `tools/test/fixtures/casa.obj`: 16 triangulos, quatro materiais, escrito a mao
para caber numa conferencia na mao, com quad e triangulo, `v//vn` e `v/vt/vn`, indice negativo, e
**uma parede com a ordem dos cantos invertida de proposito** — o conversor tem de achar as duas
faces pela normal e corrigir. O self-check carrega a casa convertida e cobra os 16 triangulos, a
marca de fechada e a caixa envolvente.

**Onda 5 — sair da janelinha.** Primeiro o pre-requisito: `Canvas:line` corta no retangulo do
canvas (Liang-Barsky) **antes** do Bresenham. Sem isso o laco anda ponto a ponto fora da tela e o
`Canvas:set` descarta em silencio — uma aresta com vertice logo atras da camera projeta a milhoes
de pontos e trava o computador nos 7 segundos.

Com o corte no lugar, `three` ganhou `draw(objetos, { wire = true })`: as tres arestas em vez do
preenchimento, com o descarte de face ainda valendo e **sem** z-buffer (a linha passa por cima de
tudo; esconder aresta e' remocao de linha escondida, outro assunto). No poligono cortado no plano
proximo o que sai e' o contorno, e nao as arestas dos dois triangulos, senao a diagonal interna
aparece.

E o `modelo.lua` desenha na parede: tecla M liga um monitor. Medido no CraftOS-PC grafico, um
monitor 102x38 na escala 0,5 da **204x114 pontos** e custa **7 ms**, contra 3 ms da janela — por
isso ele desenha a cada quarto quadro. Tudo em `pcall`, e o monitor sai fora na primeira falha.

Junto veio um conserto que so' o arame revelou: a camera ficava a uma distancia fixa, e
`normalizeScale` poe a MAIOR dimensao em 1, o que nao e' o mesmo que caber. Agora a distancia sai
da esfera que envolve o modelo, contra a **menor** metade do canvas.

**Demos prontos:** `os/demos/cubo.lua` (cubo girando, 20 fps, com luz que gira; C liga o descarte, R troca a rampa, P a paleta) e
`os/demos/terreno.lua` (ruido de valor, 1.152 triangulos, camera WASD, iluminado com applyTinted) e `os/demos/modelo.lua`
(visualizador: lista `/os/share/models`, N troca de modelo, A liga o arame, M joga no monitor,
setas giram, espaco para). Nao aparecem
no Iniciar nem em Programas de proposito: abrem pelo Arquivos em `/os/demos`. Os tres entram no
teste de fumaca, num laco proprio.

## Falta fazer, nesta ordem

1. **Onda 6 — fechamento.** Doc em `os/docs/`, `CLAUDE.md`, manifest, push.

## Armadilhas ja encontradas (nao repetir)

- **Heredoc do bash come barra invertida.** Ja aconteceu tres vezes: `"[/\:...]"` virou escape
  invalido, e `"
"` virou quebra de linha de verdade dentro de string Lua. Escrever arquivo Lua
  com a ferramenta Write, nao com `cat <<EOF`.
- **O `tools/lint.js` nao pega escape invalido de string.** So aparece no CraftOS-PC.
- **Abstracao no caminho quente custa caro em Lua sem JIT.** Passar os vertices por um vetor para
  dar conta do poligono cortado dobrou o tempo da cena de 10 mil triangulos. O caminho comum tem
  de ser plano.
- **Contar operacao no papel nao substitui medir.** Previ 50% no descarte de face (deu 25%, hoje
  22%) e metade do custo fixo em guardar canvas e quadro (deu 11%, hoje 0,15 ms).
- **Geometria de teste ruim reprova codigo bom.** O primeiro teste do corte usava uma parede
  inclinada cuja parte visivel projetava toda fora do canvas: falhava por geometria, nao por bug.
- **O relatorio do bench nao cabe em 19 linhas** — por isso ele sai em arquivo.
- **Nunca agrupar float por `string.format("%.0f")`.** O zero negativo vira `"-0"` numa
  implementacao de Lua e `"0"` noutra: um teste passava no emulador em JS e falhava na ROM.
- **O degrau mais escuro da rampa de cinza e' preto, e o fundo do canvas 3D tambem.** Face que cai
  nele some. Ambiente 0,3 numa rampa de quatro ja resolve.
- **Luz direcional piora forma de voxel.** Seis normais so', e a rampa de quatro degraus joga as
  terracas em tons muito diferentes. O topo/lado/base do `mesh.voxels` e' orientacao, nao direcao.
- **Paleta se aplica no terminal RAIZ** (`term.native()`), nunca na janela: janela do CC guarda a
  paleta so' para si. Funciona porque o compositor nao reempurra paleta, so' faz `blit`.
- **`applyTinted` sozinho apaga a cor de um modelo colorido.** A queda ia direto para cinza claro e
  cinza, entao a casa com quatro materiais aparecia monocromatica. A saida foi a tabela
  `shade.darker`, com o parente mais escuro de cada cor dentro das 16 (vermelho -> marrom, lima ->
  verde). O piso continua sendo o cinza, nunca o preto.
- **Luz parada no mundo estraga visualizador.** Quem gira e' o modelo, entao metade das voltas
  mostra so' o lado escuro. A luz do `modelo.lua` sai da mesma formula do `orbit` mais um ombro.
  Duas tentativas de escrever um angulo de luz solto deram a casa toda cinza — a segunda com o
  sinal trocado, que poe a luz exatamente atras do modelo.
- **Luz muito de cima nao sobra para os lados.** O vetor e' normalizado: com altura 0,8, as duas
  paredes visiveis (90 graus uma da outra, 45 para a luz) caiam as duas em 0,55, exatamente no
  corte do `applyTinted`, e o modelo saia chapado. Com 0,5 as duas ficam na cor propria.
- **Pose ruim reprova modelo bom.** A casa parecia uma caixa com a tampa vermelha por causa da
  camera: alta demais, a agua do telhado enchia a tela e escondia a empena. Antes de suspeitar do
  conversor, gire o modelo.
- **Malha de verdade repete vertice seis vezes.** Gravar triangulo com os nove numeros e' o formato
  certo para o rasterizador e o errado para o disco: 105 KB de Suzanne num computador de 1 MB.
  Indexado no arquivo, desdobrado no carregamento.
- **Lasca quase degenerada engana a conferencia de normal.** A Suzanne tem duas faces de area 0,0006
  cujo produto vetorial fica quase perpendicular a normal declarada: o sinal ali e' ruido de
  arredondamento. O conversor so' inverte a ordem quando o desacordo passa de uns 6 graus, senao o
  aviso de "faces corrigidas" vira barulho e perde a serventia.
- **A Suzanne sai do Blender de costas para a camera do `orbit`.** Ela olha para +z depois da
  inversao de mao, e a camera de `giro = 0` fica em -z. Nao e' bug de conversor; e' so' virar.
- **Silhueta em ASCII resolve o que print de 100x51 nao resolve.** Passei quatro prints achando que a
  Suzanne estava torta ou espelhada. Desenhar a malha num canvas de 48x15 e imprimir com pontos
  mostrou orelha, cranio e pescoco simetricos em dois segundos.
- **Arame se le com pouco poligono.** A Suzanne em arame vira mancha cinza: 968 triangulos e as
  arestas se encostam a 100x51 sub-pixels. E' tambem mais LENTA que preenchida (6 ms contra 3),
  porque cada aresta interna sai duas vezes e nao ha z-buffer para pular pixel.
- **`normalizeScale` nao e' enquadramento.** Maior dimensao em 1 nao quer dizer que cabe: um cubo
  visto de canto ocupa 1,73, e a escala sai de w/2 nos dois eixos, entao numa janela mais larga que
  alta quem aperta e' a altura. A casa em arame saiu com os cantos para fora da tela.
- **O CraftOS-PC headless nao cria monitor.** `periphemu.create` responde "Monitors are not available
  in this mode"; so' o modo grafico cria. E la' o `term.screenshot` fotografa so' o computador, entao
  a prova do monitor vem do `getSize()` e de o app nao estourar, nao de um print.
- **Rodar o `craftos.js test` ANTES de commitar, nao depois.** Ja subi um commit com o self-check
  vermelho na ROM por ter conferido so' o emulador.
