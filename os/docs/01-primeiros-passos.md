# Primeiros passos

O Mosaic OS e um sistema de janelas para o computador do CC:Tweaked.
Precisa ser um computador avancado (advanced) para ter mouse e cores.

## A area de trabalho

Os icones abrem os programas com um clique. Clique com o botao
DIREITO em qualquer lugar vazio para o menu de contexto: abrir um
terminal, criar um programa novo, atualizar os icones ou ver a versao.

Pelo teclado, as setas andam pelos icones e Enter abre o selecionado.

O nome do computador aparece no canto superior direito. Para trocar,
va em Config.

## As janelas

A barra de titulo tem tres botoes na ponta direita:

- _ minimiza para a taskbar
- + maximiza, e vira - para restaurar
- x fecha

Arraste pela barra de titulo para mover, e arraste com o botao DIREITO
para redimensionar. A taskbar embaixo mostra tudo que esta aberto:
clique para trazer para frente, clique de novo para minimizar. A janela
em foco aparece com o botao afundado.

## O menu Iniciar

O botao Iniciar no canto inferior esquerdo abre a lista completa de
programas, mais o cursor por teclado, Desligar, Reiniciar e Sair para o
shell.

Nem todo programa tem icone na area de trabalho. Notas, Calculadora,
Relogio, Controle remoto e Atualizar OS ficam so no menu.

## Teclado

O sistema inteiro funciona sem mouse.

- Ctrl+Esc abre o menu Iniciar
- Alt+Tab troca de janela
- Alt+F4 fecha a janela em foco
- Alt+M liga o cursor por teclado
- Tab e Shift+Tab andam pelos campos de um programa
- Enter aciona o botao padrao, Esc o de cancelar
- Segure Alt para acender a letra de atalho de cada botao, e aperte a
  letra para acionar

Ctrl+T, Ctrl+R e Ctrl+S nao sao usados de proposito: o proprio
CC:Tweaked os intercepta quando segurados, e desliga ou reinicia o
computador.

## O cursor por teclado

O CC nao avisa quando o mouse se move, so quando voce clica ou arrasta.
Por isso nao existe um cursor que siga o mouse.

O que existe e um cursor que anda no teclado: Alt+M liga, as setas
movem (segure a tecla para andar mais rapido), Enter clica,
Shift+Enter faz o clique direito e Esc desliga. Enquanto estiver
ligado, um marcador aparece na taskbar e as setas pertencem ao cursor,
nao ao programa em foco.

Serve para usar o sistema em computador sem mouse, e para alcancar
qualquer canto da tela sem tirar a mao do teclado.

## Aparencia

Em Config voce escolhe o tema: win95 (o padrao), classic (as cores
originais do CC) ou dark.

O tema win95 remapeia algumas das 16 cores do CC para os tons do
Windows 95. Isso vale para o computador inteiro, entao programas da ROM
como o paint aparecem com essas cores enquanto o Mosaic estiver
rodando. Ao sair pelo menu Iniciar as cores voltam ao normal. Se
preferir nao mexer nas cores, desligue a opcao de paleta em Config.

## Se alguma coisa travar

Todo programa e uma corrotina cooperativa. Se um deles entrar em laco
sem esperar evento, o computador inteiro para e o CC aborta em cerca de
7 segundos.

Abra Tarefas pelo menu para ver o que esta rodando e fechar o culpado.

## Se o sistema nao subir

Crie o arquivo /os/safemode e reinicie: o startup pula o Mosaic e te
deixa no shell da ROM. Apague o arquivo para voltar ao normal.

Dali da para rodar o instalador de novo ou usar o edit para investigar.
