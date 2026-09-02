# Escrever seus programas

Qualquer arquivo .lua dentro de /apps vira um icone na area de
trabalho, sozinho. Use o menu do botao direito, opcao Novo programa,
que ja cria e abre no editor.

## O que voce ganha de graca

Dentro de um programa do Mosaic existe a tabela global mosaic:

- mosaic.ui       o toolkit de janelas
- mosaic.theme    as cores do tema atual
- mosaic.lib(n)   carrega uma biblioteca de /os/lib
- mosaic.notify   mostra um aviso na tela
- mosaic.version  nome e versao do sistema
- mosaic.setTitle muda o titulo da janela
- mosaic.launchWith  abre outro programa numa janela
- mosaic.altHeld  se o Alt esta segurado agora
- mosaic.pointer  o estado do cursor por teclado

## Um exemplo inteiro

  local ui = mosaic.ui
  local f = ui.form()
  f:add(ui.label { x = 2, y = 2, text = "Quantos?" })
  local box = f:add(ui.textbox { x = 2, y = 3, w = 10 })
  f:add(ui.button { x = 2, y = 5, text = "Somar",
    onClick = function()
      mosaic.notify("Deu " .. (tonumber(box.text) or 0) * 2)
    end })
  f:run()

## Os widgets

label, text (paragrafo com quebra), button, textbox, list, checkbox,
dropdown e progress. Para dialogos: ui.msgbox, ui.confirm, ui.prompt e
ui.menu.

O formulario rola sozinho quando fica mais alto que a janela, entao
voce pode empilhar widgets sem se preocupar com o tamanho da tela.

## Interface que se ajusta sozinha

Em vez de dar x, y, largura e altura fixos, declare onde o widget deve ficar
e o form resolve a cada mudanca de tamanho:

  w = "fill"      largura inteira da janela
  w = -3          largura menos 3
  bottom = 0      ultima linha
  right = 2       duas colunas antes da borda direita
  above = outro   logo acima de outro widget
  fillTo = outro  altura ate onde outro widget comeca

E para uma fila de botoes existe o ui.row, que QUEBRA para cima quando os
botoes nao cabem, em vez de deixar o ultimo sumir:

  local bar = ui.row(f, { bottom = 0, items = {
    { text = "&Abrir", onClick = abrir },
    { text = "&Novo", onClick = novo, alt = true },
  } })
  local rodape = f:add(ui.label { x = 1, above = bar, w = "fill" })
  f:add(ui.list { x = 1, y = 2, w = "fill", fillTo = rodape })

A ordem importa: cada ancora so enxerga widgets ja adicionados. Por isso a
fila entra antes do rodape, e o rodape antes da lista.

Com isso o app nao precisa mais tratar term_resize para reposicionar nada.

## Agrupar campos

Campos do mesmo assunto ficam melhor dentro de uma caixa com titulo:

  f:add(ui.group { x = 1, y = 1, w = -1, h = 4, text = "Aparencia" })
  f:add(ui.label { x = 3, y = 2, text = "Tema:" })

A caixa e so a moldura: ela nao captura clique nem foco, e os campos continuam
sendo filhos do form, posicionados por dentro dela. A moldura gasta uma linha
em cima, uma embaixo e duas colunas nas laterais.

## Atalho por letra

Coloque & antes da letra no texto do botao ou do checkbox:

  f:add(ui.button { x = 2, y = 5, text = "&Somar", onClick = ... })

A letra acende enquanto o Alt esta segurado, e Alt+S aciona. Nao existe
sublinhado na grade de caracteres, entao cor foi o jeito encontrado.

Enter aciona o botao marcado como f.defaultButton e Esc o
f.cancelButton. Nos dialogos prontos isso ja vem configurado. Textbox e
list ficam com o Enter para si (marcam takesEnter), para nao roubar o
Enter de quem esta digitando.

## A regra que nao da para quebrar

Todo laco precisa esperar um evento. Um while true sem os.pullEvent ou
sleep trava o computador inteiro, e o CC aborta em cerca de 7 segundos.

Se voce usa f:run(), isso ja esta resolvido: ele espera evento a cada
volta.

## Desenho em alta resolucao

A biblioteca pixel divide cada caractere em 2 x 3 sub-pixels usando os
caracteres de teletexto. Uma tela de 51 x 19 vira 102 x 57.

  local pixel = mosaic.lib("pixel")
  local c = pixel.new(51, 19)
  c:clear(colors.blue)
  c:line(1, 1, 102, 57, colors.white)
  c:render(term.current(), 1, 1)

Cada celula so aceita duas cores, e nao cabe texto legivel junto. Serve
para imagem, grafico e papel de parede, nao para interface.

## Icones

Icone e um .nfp de 12 x 12 em /os/share/icons, onde cada pixel do
arquivo vale um sub-pixel: 6 x 4 celulas na tela.

  local icons = mosaic.lib("icons")
  icons.draw(term.current(), "files", 2, 3, colors.black)

O ultimo argumento e a cor de tras, porque o transparente do arquivo
precisa virar alguma cor na hora de montar a celula.

Para o seu programa em /apps aparecer com icone proprio, grave o
arquivo com o mesmo nome do programa. Sem arquivo, aparece a plaquinha
de duas letras.

## Desenho que muda de tamanho

Para logo e grafico, que precisam servir em qualquer tamanho, existe o
vector: figuras descritas por coordenadas, rasterizadas na hora.

  local vector = mosaic.lib("vector")
  local logo = vector.load("/os/share/vectors/logo.lua")
  vector.draw(term.current(), logo, 2, 3, 6, 4, colors.black)

O desenho e uma tabela Lua com vb (a caixa de coordenadas) e as figuras:
rect, circle, ou d com os comandos M, L e Z. Da para converter de SVG
com o tools/svg.js do repositorio.

Para icone pequeno prefira o .nfp: em 12 x 12 cada ponto e uma decisao
de desenho, e rasterizar de um desenho grande sempre borra.
