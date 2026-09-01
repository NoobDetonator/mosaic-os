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
