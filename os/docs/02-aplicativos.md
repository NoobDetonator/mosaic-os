# Os aplicativos

## Terminal

O shell da ROM do CC dentro de uma janela. Todos os programas de
sempre funcionam aqui: ls, edit, lua, pastebin, wget.

## Arquivos

Navega pelo disco. Abre, renomeia, copia, move e apaga. Arquivo .lua
abre no editor; .nfp abre no paint.

## Editor

Pergunta o arquivo e entrega para o edit da ROM, na mesma janela.

## Rede

Mostra o estado do relay e lista os outros computadores Mosaic na rede
local. Precisa de um modem no computador para achar os vizinhos.

## Perifericos

Lista tudo que esta conectado, de que lado, e quais metodos cada um
oferece. Serve para descobrir o nome certo antes de escrever codigo.

## Tarefas

O que esta rodando, quanto de memoria, e o botao de fechar. E aqui que
voce mata um programa travado.

## Config

Nome do computador, tema (claro ou escuro), relogio da taskbar (hora
real ou hora do jogo), relay, rede e papel de parede.

O botao Ver todas as opcoes lista tudo que comeca com mosaic. e deixa
editar na mao. A tela rola: use a roda do mouse.

## Notas, Calculadora, Relogio

Notas guarda texto em /home. A calculadora entende expressoes Lua e
guarda o ultimo resultado em ans. O relogio mostra hora real e do jogo.

## Controle remoto

Manda codigo Lua para outro computador Mosaic pela rede local. Pede o
ID do destino. O outro lado precisa estar com a rede ligada, e com
senha se tiver sido configurada.

## Atualizar OS

Compara os arquivos daqui com o repositorio e baixa so o que mudou.
Clique em Verificar, depois em Atualizar. Reinicie no fim.

## Papel de parede

Aponte para um .nfp em Config. Uma imagem do tamanho da tela em
caracteres (51 x 19) desenha normal. Uma imagem MAIOR que isso e lida
em alta resolucao, com cada pixel do arquivo virando um sub-pixel:
102 x 57 numa tela padrao.
