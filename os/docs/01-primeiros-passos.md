# Primeiros passos

O Mosaic OS e um sistema de janelas para o computador do CC:Tweaked.
Precisa ser um computador avancado (advanced) para ter mouse e cores.

## A area de trabalho

Os icones abrem os programas com um clique. Clique com o botao
DIREITO em qualquer lugar vazio para o menu de contexto: abrir um
terminal, criar um programa novo, atualizar os icones ou ver a versao.

O nome do computador aparece no canto superior direito. Para trocar,
va em Config.

## As janelas

A barra de titulo tem tres botoes na ponta direita:

- _ minimiza para a taskbar
- + maximiza, e vira - para restaurar
- x fecha

Arraste pela barra de titulo para mover. A taskbar embaixo mostra tudo
que esta aberto: clique para trazer para frente, clique de novo para
minimizar.

## O menu Iniciar

O botao M no canto inferior esquerdo abre a lista completa de
programas, mais Desligar, Reiniciar e Sair para o shell.

Nem todo programa tem icone na area de trabalho. Notas, Calculadora,
Relogio, Controle remoto e Atualizar OS ficam so no menu.

## Se alguma coisa travar

Todo programa e uma corrotina cooperativa. Se um deles entrar em laco
sem esperar evento, o computador inteiro para e o CC aborta em cerca de
7 segundos.

Abra Tarefas pelo menu para ver o que esta rodando e fechar o culpado.

## Se o sistema nao subir

Crie o arquivo /os/safemode e reinicie: o startup pula o Mosaic e te
deixa no shell da ROM. Apague o arquivo para voltar ao normal.

Dali da para rodar o instalador de novo ou usar o edit para investigar.
