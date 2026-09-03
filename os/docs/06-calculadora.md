# Calculadora

Cinco modos na mesma janela. A barra de baixo troca de aba.

## Conta

Digite a conta e aperte Enter. A seta para cima traz a conta anterior de volta,
como num terminal.

- Operadores: + - * / % ^ e ! (fatorial)
- O ^ associa a direita: 2^3^2 e 512, nao 64
- -2^2 e -4, porque o menos vem depois da potencia
- Multiplicacao implicita: 2(3+4), 3pi, 2pi raio
- % e resto de divisao, nao porcentagem. Para porcentagem escreva 50/100

Variaveis: escreva raio = 12 e use raio nas contas seguintes. O resultado da
ultima conta fica sempre em ans. O rodape mostra o que esta definido.

F3 troca entre graus e radianos. O rodape mostra qual esta valendo.

F2 abre o teclado de botoes. Ele encolhe o historico em vez de cobrir.

O botao Funcoes lista tudo que da para usar, com uma linha de explicacao cada:
sqrt, abs, floor, ceil, round, min, max, sin, cos, tan, asin, acos, atan, ln,
log, exp, hypot, gcd e lcm.

## Blocos

Escolhe a forma, as medidas, e mostra o desenho bloco a bloco junto com a conta.

- Formas: retangulo, caixa, circulo, elipse, cilindro, esfera, elipsoide,
  cupula, cone, losango e triangulo
- Oco deixa so a parede; Esp e a espessura dela
- PageUp e PageDown andam pelas camadas nas formas de mais de uma
- A caixa 3D mostra a forma montada, e as setas giram a camera

O circulo usa o criterio classico de construtor: o centro do bloco contra o
raio. E o que da 37 blocos no diametro 7 e 177 no 15, os mesmos numeros dos
geradores de fora do jogo.

Os campos voltam com o que a forma realmente usou. Circulo ignora profundidade e
esfera iguala os tres eixos, entao deixar o que voce digitou seria mentir sobre
o desenho.

## Grafico

Desenha y = f(x). Use x como variavel.

- Ate duas funcoes ao mesmo tempo, em cores diferentes
- Auto ajusta a altura sozinho; desmarque para mandar na escala
- Setas arrastam o grafico, PageUp e PageDown aproximam e afastam
- A barra vermelha no meio e a leitura: o rodape mostra o valor ali

Onde a funcao nao existe o desenho abre um buraco em vez de riscar uma linha
vertical. Um salto maior que a tela e assintota, nao curva.

## Baus

Converte item em stack e em recipiente, nos dois sentidos.

- Itens: quantos voce tem, e ele diz quantos baus da
- Recip: quantos recipientes voce tem, e ele diz quantos itens cabem
- St escolhe o tamanho da pilha: 64, 16 ou 1
- Rec escolhe o recipiente: bau, bau duplo, barril, shulker ou funil
- Ler baus conta o que estiver ligado no computador

O CC nao informa o tamanho maximo de pilha de cada item, entao a conta usa o
tamanho que voce escolheu em cima, e nao o do jogo. Item que empilha ate 16
precisa que voce troque o St na mao.

## Create

- RPM e a rotacao que entra
- Engrenagens aceita uma corrente como 8:24, 24:8 (dentes de entrada e saida)
- A lista mostra geradores com + e maquinas com -
- Quantidade muda quantas pecas voce tem; Base muda o valor da peca
- Salvar grava a tabela; Padrao volta a de fabrica

O rodape soma o que a rede gasta contra o que ela aguenta.

Atencao aos numeros com ? do lado. Sao valores que eu preenchi de memoria e
ninguem conferiu: eles mudam de versao para versao do mod. Abra o jogo com os
Oculos de Engenheiro, veja o impacto real de cada maquina e a capacidade real de
cada gerador, e corrija pelo botao Base. O ? some quando voce confere, e o
rodape conta quantos ainda faltam.

As formulas em si nao dependem de versao nenhuma: a razao de engrenagem e os
dentes de entrada divididos pelos de saida, e o stress e o valor base
multiplicado pela rotacao, tanto para gasto quanto para capacidade.
