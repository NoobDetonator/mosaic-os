# Navegador

Da para abrir paginas da internet dentro do jogo. Nao e um navegador de
verdade - nao tem imagem, video nem botao - mas le texto, segue link e
busca.

## Como usar

O campo de cima aceita tres coisas, e ele adivinha qual e:

| voce digita | ele faz |
|---|---|
| `tweaked.cc/module/http.html` | abre a pagina |
| `alto falante computercraft` | busca |
| `7` | abre o link numero 7 da pagina atual |

Enter em qualquer um deles.

## Links viram numeros

No meio do texto os links aparecem como `[7]`. Para seguir um, digite `7`
no campo de cima e tecle Enter.

Quando um link e uma linha inteira - resultado de busca, item de menu - da
para so selecionar com as setas e apertar Enter.

E o jeito antigo dos navegadores de texto, e numa tela de 51 colunas ele
ganha de qualquer outro: nao gasta cor, nao gasta linha, e funciona sem
mouse.

## Voltar

O botao **Voltar** desfaz um passo. O historico vive enquanto a janela
estiver aberta.

## Ler na parede

O botao **Monitor** manda a pagina para o primeiro monitor conectado. Uma
pagina de texto numa parede de monitores fica bem mais confortavel do que
numa janela de 48 colunas.

## Por que precisa do relay

Uma pagina da internet e um monte de HTML, e um computador do Minecraft nao
tem como interpretar isso: 51 colunas, memoria curta, e sete segundos antes
de o jogo desligar o programa por demorar demais.

Entao quem le a pagina e o **relay**, no seu PC. Ele busca, joga fora o que
nao e texto, e manda uma lista simples de blocos: titulo, paragrafo, lista,
codigo. O computador so quebra linha e desenha.

Ele tambem tira os acentos - o terminal do ComputerCraft desenha byte a
byte e nao entende UTF-8; sem isso qualquer pagina em portugues viraria
lixo na tela.

**Sem o relay** o navegador ainda abre arquivo de texto puro e JSON por
conta propria, e diz que esta nesse modo. Busca e pagina normal precisam
dele.

## O que ele nao faz

- **Imagem e video**: nao.
- **Botao, formulario, login**: nao. Paginas que dependem de JavaScript
  chegam vazias ou pela metade.
- **Pagina gigante** e cortada, e ele avisa no fim.

A busca usa o DuckDuckGo por raspagem, sem cadastro nem cota. Se um dia
eles mudarem o formato do site, a busca para de achar resultado - e nesse
caso o navegador diz isso, em vez de mostrar uma lista vazia sem explicacao.
