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
