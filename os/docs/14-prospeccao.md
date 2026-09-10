# Prospeccao

O app **Prospeccao** le o Geo Scanner do Advanced Peripherals e responde tres
perguntas diferentes - por isso ele tem tres modos.

| modo | pergunta que responde |
|---|---|
| Analise | vale a pena cavar aqui? |
| Lista | o que existe em volta, e quanto? |
| 3D | **onde** exatamente isso esta |

## Analise

Le o chunk inteiro de uma vez e devolve os tipos de bloco com a contagem de
cada um. E a visao de cima: serve para escolher onde montar a mina, nao para
achar uma veia.

Nao gasta energia e nao depende de raio.

## Lista

Varre um raio em volta do scanner e agrupa o que achou. Aqui aparece a veia:
quantos blocos de cada minerio, e a que distancia.

## 3D

A mesma varredura, desenhada em tres dimensoes, com filtro por tipo de bloco e
corte por fatia. Se a posicao da turtle for conhecida, ela aparece dentro da
cena.

E o unico modo que responde "onde" - os outros dois so contam.

## Energia: existe um raio de graca

Isto custou tempo para descobrir, entao esta escrito:

**Raio 1 a 8 nao gasta nada.** Acima disso o custo dispara - raio 9 custa 330,
raio 12 custa 1821, raio 16 custa 5274.

E o scanner comeca com capacidade **zero**. Ou seja: enquanto ele nao estiver
ligado na energia, **qualquer raio acima de 8 e impossivel**, e a varredura
falha.

Por isso o app pergunta ao proprio scanner ate onde da para ir sem energia, em
vez de oferecer um raio que vai dar erro na sua cara.

## O scanner mede em volta de si, nao de voce

Ligado por cabo, ele e uma estacao parada. Todas as coordenadas saem relativas
ao **bloco dele** - nao de quem esta olhando a tela, e nao da turtle.

Para uma turtle que anda, o scanner precisa estar equipado nela.

## Na parede

Num monitor nao existe teclado, e o toque e so clique de botao direito. Entao,
quando o app esta numa parede, a camera do 3D **gira sozinha** e todo filtro se
resolve com um toque na legenda.

Na janela do computador o teclado manda, porque ali ele existe.

## O 3D no jogo e lento

Medido no servidor: 5204 triangulos custaram 247 ms por quadro. Sao ~21 mil
triangulos por segundo - **quarenta vezes menos** que o mesmo motor rodando no
emulador de PC.

Por isso a cena tem teto de 800 blocos, e o giro automatico se regula pelo custo
do ultimo quadro: cena leve gira macio, cena pesada gira devagar em vez de comer
o computador. Girar mais rapido do que se consegue desenhar so enfileira
trabalho.
