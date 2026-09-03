# Caderno de medidas do 3D

Onde cada hipótese sobre desempenho do motor 3D é anotada com a previsão, a medida e o veredito.
**Hipótese que não se confirma fica aqui como não confirmada** — é para isso que a tabela existe.

Todos os números saem de `node tools/craftos.js bench`, no CraftOS-PC, tela 51x19, canvas de
desenho 51x15 células = 4.590 pontos. O computador do jogo é mais lento e a ROM dele é mais velha:
o que vale aqui é a **proporção**, não o valor absoluto. Referência: um tique do Minecraft = 50 ms.

O bench usa **mediana de 5 rodadas** com `collectgarbage()` antes de cada uma, e imprime min e max.
Antes era média de uma rodada só, e uma pausa do coletor dentro de um laço de 5 iterações dominava
o número.

---

## Linha de base (antes de qualquer otimização)

| Medida | ms |
|---|---:|
| `frame:clear` (canvas + z-buffer) | 0,13 |
| `canvas:render` (a saída para a tela) | **1,68** |
| cubo, 12 triângulos, clear+draw | 1,22 |
| grade 7x7, 98 triângulos | 0,55 |
| grade 22x22, 968 triângulos | 2,05 |
| grade 71x71, 10.082 triângulos | 17,45 |
| círculo 15 maciço, 828 triângulos | 2,20 |
| esfera oca 15, 3.768 triângulos | 11,80 |
| esfera oca 15, com descarte de face | 8,90 |
| montar a malha da esfera | 5,60 |
| quadro completo do jeito que o `calc` faz | 4,35 |

### O que a linha de base já ensina

**O `canvas:render` é o maior custo fixo, e ninguém sabia.** 1,68 ms, treze vezes o `clear`. Para o
cubo de 12 triângulos, mandar o resultado para a tela custa mais que desenhar. Ele não era medido
em lugar nenhum — as três linhas de 3D antigas somavam clear e desenho num número só.

**Custo por triângulo: 1,69 µs.** As três grades cobrem a mesma área de tela com 98, 968 e 10.082
triângulos, então a diferença entre elas é puro custo por triângulo:
`(17,45 − 2,05) / (10.082 − 968) = 1,69 µs`. Isso dá **~590 mil triângulos por segundo**.

Para comparar: o Pine3D anuncia 20 mil polígonos a 20 fps em Lua normal, ou ~400 mil por segundo.
Estamos na mesma ordem de grandeza — mas ele mede num computador do jogo e nós no CraftOS-PC, que é
mais rápido. A comparação honesta ainda não dá para fazer.

**Cena pequena é limitada por pixel; cena grande, por triângulo.** O cubo tem 12 triângulos e leva
1,09 ms de desenho, porque esses 12 cobrem quase o canvas inteiro. A grade de 98 triângulos cobre a
mesma área em 0,42 ms. Otimizar o laço de pixel ajuda a primeira; otimizar a transformação por
vértice ajuda a segunda.

---

## Hipóteses

| # | Hipótese | Previsão | Medido | Veredito |
|---|---|---|---|---|
| 1 | Descarte de face de costas corta metade do trabalho | ~50% | 11,80 → 8,90 = **25%** | **Parcial.** Ver abaixo. |
| 4 | Guardar canvas e quadro entre desenhos tira metade do custo fixo | ~50% do fixo | 4,35 contra 3,88 somando as partes = **0,47 ms**, ~11% | **Superestimada.** Ver abaixo. |

### 1 — Descarte de face de costas: previ 50%, deu 25%

O erro foi meu e é instrutivo. Metade das faces de uma casca fechada aponta para longe da câmera,
então metade **da rasterização** some — mas a face descartada **já pagou a transformação dos três
vértices** antes do teste de área, porque o descarte acontece dentro do rasterizador. O que sobra
é: transformação inteira, rasterização pela metade.

Isso muda a ordem do que vale a pena atacar: **a transformação por vértice pesa tanto quanto o
preenchimento**, e o caminho por vértice hoje é caro — despacho por metatabela em `self:project`,
uma closure por objeto, e onze buscas de tabela por vértice.

### 4 — Guardar canvas e quadro: previ metade, deu 11%

O quadro completo do jeito que o app faz custa 4,35 ms. As partes somadas — desenho do círculo com
clear (2,20) mais a saída (1,68) — dão 3,88. A diferença, **0,47 ms**, é tudo que criar canvas e
quadro novos custa por quadro. Vale corrigir porque é barato, mas eu tinha previsto muito mais.

O que eu não tinha percebido ao prever: o `clear` custa 0,13 ms, não os "11.600 escritas de tabela"
que a contagem estática sugeria. Contar operação no papel não substitui medir.

---

## Onda 1 — corte no plano proximo

| Medida | base | com corte (1a tentativa) | com corte (final) |
|---|---:|---:|---:|
| grade 71x71, 10.082 tri | 17,45 | **35,55** | 17,90 |
| grade 22x22, 968 tri | 2,05 | 3,85 | 2,15 |
| circulo 15, 828 tri | 2,20 | 4,25 | 2,05 |
| esfera oca 15, 3.768 tri | 11,80 | 13,60 | **9,70** |
| quadro completo do `calc` | 4,35 | 4,95 | 4,10 |

### A primeira tentativa dobrou o tempo, e o motivo vale guardar

Para cortar, o triangulo precisa virar um poligono de ate 4 vertices, e o jeito obvio de
escrever isso e passar os vertices por um vetor: `poly[1..9]`, depois um laco projetando para
`px[k]`, `py[k]`, `pw[k]`. Sao **21 operacoes de tabela por triangulo** — e eu as pagava em
**todo** triangulo, mesmo nos 99,9% que nao precisam de corte nenhum.

A cena de 10 mil triangulos foi de 17,45 para 35,55 ms. Exatamente o dobro.

A correcao foi separar os dois caminhos: quando os tres vertices estao na frente da camera — o
caso comum — os valores vao direto das variaveis locais para os argumentos do rasterizador, sem
encostar em tabela nenhuma. O vetor so' existe no ramo raro.

**E ai o quadro ficou mais rapido que antes do corte.** A esfera caiu de 11,80 para 9,70 ms, 18%.
O ganho nao veio do corte: veio de a reestruturacao ter tirado `pcx`, `pcy` e `escala` de dentro
da tabela `pre` para variaveis locais, e de `camX/camY/camZ` deixarem de ser tres leituras de
hash em `self.cam` por vertice.

**Licao:** em Lua sem JIT, o custo de uma abstracao no caminho quente e' medivel e grande. O
caminho comum precisa ser plano.

---

## Onda 2, hipotese 6 — o `canvas:render`

**Previsao:** tirar as alocacoes por celula ajuda. **Medido: 1,68 → 0,49 ms, 3,4 vezes.**
**Confirmada, e era o maior custo fixo do quadro.**

| Medida | antes | depois |
|---|---:|---:|
| `canvas:render` | 1,68 | **0,49** |
| quadro completo do `calc` | 4,35 | **2,80** |

O que estava caro, por celula, numa tela de 765 celulas:

- `pixel.cell` alocava **duas tabelas** (contagem e ordem) e **uma closure** (`near`);
- os seis sub-pixels iam e voltavam por um vetor `px[1..6]` — doze operacoes de tabela;
- `string.char(128 + code)` e **duas** chamadas a `colors.toBlit`;
- as tres tabelas de linha (`chars`, `fgs`, `bgs`) eram novas a cada linha.

Agora: `pixel.cell6` recebe os seis valores soltos, o rascunho de contagem e' reaproveitado e
limpo no proprio laco que escolhe as duas cores, e ha duas tabelas montadas uma vez — o
caractere de cada combinacao de bits e a letra de blit de cada cor.

**Uma tentativa intermediaria nao deu em nada, e vale registrar.** Ao tirar o vetor `px`, escrevi
o laco de contagem como `for i = 1, 6 do local c = (i == 1 and p1) or (i == 2 and p2) or ... end`.
Isso troca doze operacoes de tabela por trinta comparacoes: anula o ganho. Desenrolar as seis
linhas na mao e feio de ler e e' o que faz o numero acontecer.

Este ganho **nao e' so' do 3D**: papel de parede, icone montado do zero, grafico da calculadora
e pre-visualizacao de blocos passam todos pelo mesmo caminho.

---

## Onda 2, hipoteses 2 e 3 — o rasterizador

**2. Escrever direto no buffer** em vez de passar por `canvas:set`. **Confirmada.**
**3. Varredura de linha com passo de aresta** em vez de caixa envolvente com teste por ponto.
**Confirmada, e foi a maior das duas.**

| Medida | base | +render | +escrita direta | +varredura | ganho total |
|---|---:|---:|---:|---:|---:|
| cubo, 12 tri | 1,22 | 1,25 | 0,80 | **0,36** | **3,4x** |
| grade 7x7, 98 tri | 0,55 | 0,60 | 0,60 | **0,35** | 1,6x |
| grade 22x22, 968 tri | 2,05 | 2,30 | 2,30 | **1,40** | 1,5x |
| grade 71x71, 10.082 tri | 17,45 | 17,75 | 17,55 | **12,15** | 1,4x |
| circulo 15, 828 tri | 2,20 | 2,20 | 2,00 | **1,35** | 1,6x |
| esfera oca 15, 3.768 tri | 11,80 | 9,50 | 9,00 | **6,10** | **1,9x** |
| esfera oca 15 com cull | 8,90 | 8,50 | 6,10 | **5,30** | 1,7x |
| quadro completo do `calc` | 4,35 | 2,80 | 2,70 | **2,10** | **2,1x** |

### O que cada uma fez

**Escrita direta** ajuda onde o preenchimento manda e quase nada onde manda o triangulo: o cubo
caiu 36%, a grade de 10 mil triangulos caiu 1%. Faz sentido — `canvas:set` custava dois
`math.floor`, quatro testes de limite e um `blitCache = nil` **por ponto**, para um trabalho que
e' uma vez por quadro.

**Varredura de linha** ajuda em tudo, porque tira duas coisas ao mesmo tempo: as 21 operacoes de
teste de cobertura por ponto candidato, e os pontos da caixa envolvente que o triangulo nao
cobre (perto da metade, num triangulo qualquer). O laco interno virou `if w > zb[i] then ... end;
w = w + A`.

Tambem sumiu um contador de pontos pintados que era incrementado **por ponto** e cujo valor de
retorno ninguem lia.

### Onde chegamos

Custo por triangulo agora: `(12,15 − 1,40) / (10.082 − 968) = 1,18 µs`, ou **~847 mil triangulos
por segundo**, contra 1,69 µs e 590 mil da linha de base.

O quadro do cubo no demo mede **0 ms** — abaixo da resolucao de milissegundo do `os.epoch`.

---

## Onda 2, hipoteses 1 e 4 — descarte de face e quadro guardado

**1. Descarte de face de costas.** Agora quem decide e' a **malha**, pela marca `closed`, e nao
uma bandeira global: `mesh.voxels` e `mesh.cube` se declaram fechados, `plane` e `grid` nao. Com
z-buffer o descarte so' economiza tempo — desde que a malha seja mesmo fechada, e quem sabe
disso e' ela. Plano e grade com descarte sumiriam vistos por baixo, o que e' certo para um
terreno e errado para uma parede.

Medido na esfera: **6,00 sem, 4,70 com** — 22%. Antes das outras otimizacoes era 25%; conforme
o rasterizador barateou, a fatia que o descarte economiza encolheu, porque a transformacao dos
tres vertices continua sendo paga antes do teste.

**4. Guardar canvas e quadro entre desenhos** (`calc.lua` e os demos). Medido: **1,70 criando,
1,55 reaproveitando**. Sao 0,15 ms, contra os 0,47 da linha de base — o proprio ganho encolheu
porque tudo em volta ficou mais barato. Vale porque custa oito linhas.

---

## Onde a onda 2 terminou

| Medida | base | agora | ganho |
|---|---:|---:|---:|
| `canvas:render` | 1,68 | 0,48 | 3,5x |
| cubo, 12 tri | 1,22 | 0,26 | **4,7x** |
| grade 7x7, 98 tri | 0,55 | 0,35 | 1,6x |
| grade 22x22, 968 tri | 2,05 | 1,30 | 1,6x |
| grade 71x71, 10.082 tri | 17,45 | 11,70 | 1,5x |
| circulo 15, 828 tri | 2,20 | 1,00 | 2,2x |
| esfera oca 15, 3.768 tri | 11,80 | 4,70 | **2,5x** |
| quadro completo | 4,35 | 1,55 | **2,8x** |

Custo por triangulo: **1,69 → 1,14 µs**, ou de 590 mil para **~877 mil triangulos por segundo**.

O desenho nao mudou: o print do cubo antes e depois e' o mesmo, e o teste do z-buffer continua
passando nas duas ordens de desenho.

---

## Onda 3 — iluminacao

`os/lib/shade.lua`: Lambert por face, normal pre-calculada no modelo (`tri[11..13]`, uma vez por
malha e nao por quadro), e o resultado caindo num degrau de uma rampa.

Por face e nao por vertice de proposito: com 16 cores nao existe degrade, e interpolar tom entre
vertices so' aumentaria o numero de celulas com tres cores. A celula de sub-pixel aceita duas —
o resultado seria pior, nao melhor.

### O degrau mais escuro era o fundo

A rampa de cinza comeca no **preto**, e o fundo do canvas 3D e' preto. Com ambiente 0,2, as faces
de costas caiam no primeiro degrau e **sumiam no fundo**: o cubo do demo virou um losango
achatado, porque so' o topo sobrava. Levei um print para perceber.

Correcao: ambiente 0,3 nunca alcanca o primeiro degrau numa rampa de quatro, e isso virou teste.
O `applyTinted` passou a medir os niveis **depois** de tirar o ambiente, entao a face mais escura
possivel cai no cinza e nunca no preto.

### O experimento da paleta: **confirmado**

A rampa que a paleta do Win95 oferece e' 0, 128, 192, 255 — o primeiro salto e' o dobro dos
outros dois. Na pratica, com o arredondamento para degrau, duas faces vizinhas do cubo caiam no
mesmo tom e o cubo parecia chapado.

O mapa `palette.render3d` **preenche os buracos em vez de substituir**: marrom, roxo, magenta e
rosa — quatro cores que o tema nao usa — viram 48, 90, 160 e 224. A rampa passa a ser
**0, 48, 90, 128, 160, 192, 224, 255**, oito degraus, maior salto de 48 em vez de 128.

Preto, cinza, cinza claro e branco ficam onde estavam, entao **a barra de tarefas, o relevo dos
botoes e a barra de titulo nao mudam de cor** — confirmado no print, com a taskbar e o teal da
area de trabalho intactos ao lado do cubo.

A paleta e' aplicada no terminal **raiz**, nao na janela: janela do CC guarda a paleta so' para
si. Funciona porque o compositor nao reempurra paleta — ele so' faz `blit`. E volta ao sair,
tanto pelo Q quanto pelo X da janela (o `terminate` tambem restaura). Conferido com um print da
area de trabalho depois de sair: icones normais.

### O que NAO funcionou: luz direcional em voxel

Apliquei a mesma iluminacao na pre-visualizacao de blocos da calculadora e **ficou pior**. As
faces de um voxel sao todas alinhadas aos eixos, entao existem seis normais so'; uma rampa de
quatro degraus joga as terracas em tons muito diferentes e a esfera vira listra dura.

O `topo / lado / base` que o `mesh.voxels` ja pintava e' **orientacao, nao direcao**: os quatro
lados ficam no mesmo tom, entao nao ha assimetria entre esquerda e direita e a terraca nao
salta. Para forma escalonada, isso e' melhor que Lambert.

Revertido na calculadora, mantido nos demos de cubo e terreno, onde ajuda.


## Onda 4 — modelo do Blender

Sem hipotese de velocidade nesta onda: o gargalo aqui e' **disco**, nao quadro.

### Formato do arquivo: 105 KB -> 33 KB

A Suzanne exportada da 5.2 tem **507 vertices e 968 triangulos**. Gravar cada triangulo com os
nove numeros repete cada vertice em media seis vezes:

| Formato | Tamanho | Suzanne |
|---|---:|---|
| triangulos com os nove numeros | 105 KB | o primeiro que escrevi |
| indexado (`v` + `t`) | 33 KB | 3,2x menor |

Nao e' detalhe: o computador do CC:T tem **1 MB de disco no total** e o OS inteiro ocupa ~610 KB.
No formato antigo, um modelo comia 10% do disco da maquina.

O desdobramento acontece uma vez, no `mesh.load`, e nao aparece na medida de quadro: o custo esta
no carregamento e o rasterizador continua recebendo triangulos planos, do jeito que ele quer.

### Desenho: 3 ms para 968 triangulos

Bate com a varredura da onda 0 (o circulo de 828 triangulos dava 1,00 ms; a Suzanne tem mais
cobertura de tela por triangulo). Dentro dos 50 ms de um tique com folga larga.

### O que NAO funcionou: `applyTinted` sozinho num modelo colorido

A casa de teste tem quatro materiais e apareceu **monocromatica**. O `applyTinted` mandava toda
face fora da luz direta para cinza claro e cinza, entao vermelho, marrom e cinza viravam a mesma
coisa assim que saiam do degrau mais claro.

A saida foi `shade.darker`: o parente mais escuro de cada cor **dentro das 16** (vermelho ->
marrom, lima -> verde, rosa -> magenta, azul claro -> ciano). O piso continua sendo o cinza e
nunca o preto — cor ja escura demais para o fundo (azul, roxo, marrom) cai nele mesmo sendo mais
clara, porque sumir no fundo e' pior que clarear.

### O que NAO funcionou: luz parada num visualizador

Tentei duas vezes deixar a luz girando por conta propria enquanto o modelo gira. Nas duas a casa
apareceu **inteira cinza** no print — a segunda porque o sinal do angulo poe a luz exatamente
atras do modelo. Num visualizador quem gira e' o modelo: a luz tem de sair da **mesma formula da
camera** (`-sin`, `-cos`) mais um ombro.

Junto: a componente vertical da luz precisou cair de 0,8 para 0,5. O vetor e' normalizado, entao
luz muito de cima nao sobra para os lados, e as duas paredes visiveis (90 graus uma da outra, 45
para a luz) caiam **as duas em 0,55** — exatamente em cima do corte do `applyTinted`.

### Falso positivo na conferencia de normal

O conversor confere a ordem dos cantos de cada face contra o `vn` do arquivo. Na Suzanne ele
acusou duas faces invertidas; conferindo, sao duas lascas de **area 0,0006** cujo produto vetorial
fica a 4 graus da normal declarada — ruido de arredondamento, nao erro de exportador.

Corrigido com um corte: so' inverte com desacordo acima de uns 6 graus. Sem ele o aviso de "faces
corrigidas" vira barulho e perde a serventia de apontar exportador estranho. A casa, que tem uma
parede invertida de proposito, continua acusando as duas faces dela.

## Onda 5 — arame e monitor

### O corte de linha, medido pelo que ele evita

O `Canvas:line` andava ponto a ponto mesmo fora da tela, com o `Canvas:set` descartando em
silencio. Uma unica chamada `line(-100000, 3, 100000, 3)` faz **200 mil passos** de Bresenham num
canvas de 8 pontos de largura: os 7 segundos do CC acabam antes. Com Liang-Barsky na frente, sao
8 passos.

Nao ha "antes e depois" em milissegundos aqui porque o antes **nao termina**. Esse e' o numero.

### Arame e mais lento que preenchido: 6 ms contra 3

Contrariou a intuicao, e o motivo e' simples depois de visto:

- cada aresta entre duas faces e' desenhada **duas vezes**, uma por triangulo;
- nao ha z-buffer para pular pixel ja coberto — no preenchido, metade dos pixels da Suzanne sai
  no teste de profundidade;
- e o descarte de face nao ajuda tanto: ele tira a face, mas as arestas dela costumam ser
  compartilhadas com uma face visivel.

Arame serve para ver a topologia de uma malha pequena, nao para ganhar velocidade.

### Monitor: 204x114 pontos por 7 ms

| Alvo | Pontos | Suzanne |
|---|---:|---:|
| janela 50x17 | 100x48 | 3 ms |
| monitor 102x38 na escala 0,5 | 204x114 | 7 ms |

Area 4,8x maior por 2,3x o tempo — o custo por ponto **cai**, porque o custo fixo por triangulo
(transformar tres vertices, projetar, testar area) e' o mesmo nos dois. Ainda assim, 7 ms a cada
quadro de 50 ms e' caro para um demo que tambem desenha na janela: o `modelo.lua` desenha no
monitor a cada quarto quadro.

### Enquadramento: `normalizeScale` nao e' o que parece

Ele poe a **maior dimensao** em 1. Isso nao quer dizer que o modelo cabe: um cubo visto de canto
ocupa a diagonal, 1,73. E a escala do `three` sai de `w/2` nos **dois** eixos (o sub-pixel do CC e'
quadrado), entao numa janela mais larga que alta quem aperta e' a altura.

Com distancia fixa de 1,7 a casa em arame saiu com os quatro cantos para fora da tela. A conta
certa e' pela esfera que envolve o modelo, contra a **menor** metade do canvas:

    dist = raio * begin().escala / (min(w, h) / 2) * 1,08

Esfera e nao caixa: a caixa daria um enquadramento mais justo, mas mudaria a cada angulo, e
enquadramento que respira e' pior que enquadramento folgado.


## O preco do modo arame no caminho quente, e um aviso sobre a maquina

O `wire` entrou como um `if` por triangulo dentro do laco mais quente do motor. Medido:

| Cena | sem o `if` | com o `if` |
|---|---:|---:|
| grade 71x71, 10.082 triangulos | 15,25 ms | 15,95 ms |
| circulo 15, 828 triangulos | 1,35 ms | 1,40 ms |

**4,5% no pior caso**, 0,07 us por triangulo. Da' para zerar duplicando o laco inteiro em duas
versoes, e nao vale: sao 60 linhas do codigo mais delicado do motor para ganhar 4,5% num cenario
que ninguem desenha. Passar a decisao por uma funcao seria pior — a onda 2 ja mostrou que chamada
por triangulo custa mais que ramo por triangulo.

**Aviso para quem der diff no `bench-ultimo.txt`:** as medidas de hoje estao ~30% acima das da onda
2 **no mesmo codigo**. Rodei o `three.lua` de antes do arame para conferir: a grade de 10 mil deu
15,25 ms hoje contra 11,70 ms registrados na onda 2. O que subiu junto foi coisa que ninguem
tocou — `um passo do kernel` (0,23 -> 0,28) e `icone montado do zero` (0,25 -> 0,35) —, entao e' a
maquina, nao o codigo.

A licao vale mais que o numero: **este bench mede proporcao, nao valor absoluto**. Comparar duas
medidas tiradas em dias diferentes nao diz nada. Antes e depois na mesma sessao, sim.
