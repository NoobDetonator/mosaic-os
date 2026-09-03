# Estado e limites

Vale saber onde este sistema foi construido e testado, para voce nao
perder tempo achando que a culpa e sua quando algo sair diferente.

## Onde ele foi testado

O Mosaic foi desenvolvido e testado no CraftOS-PC, que e o CC:Tweaked
rodando fora do jogo. Ele traz a ROM de verdade, o shell de verdade, o
edit, o paint e a API de janela de verdade, entao pega quase tudo.

Mas ele nao e o Minecraft. Pode haver problema dentro do jogo que aqui
nunca apareceu.

## O que muda dentro do jogo

O computador do jogo e mais lento. Ele roda um Lua diferente (Cobalt) e
divide tempo com o servidor, entao coisa que aqui leva 7 milissegundos
pode levar bem mais la. Onde isso aparece primeiro e no 3D da
calculadora e em forma de bloco muito grande.

A versao do CC tambem e outra. O CraftOS-PC de hoje traz uma ROM mais
nova que a da 1.16.5, e ele aceita coisa que o jogo nao aceitaria. Do
lado do desenvolvimento existe um conferidor que barra isso antes, mas
nenhum conferidor pega tudo.

## O que so se prova no jogo

Periferico. Drive de disquete, chat box, player detector, ME bridge,
reator do Powah, monitor: o codigo deles existe e tem guarda para nao
quebrar quando o periferico nao esta la, mas "nao quebra sem ele" nao e
a mesma coisa que "funciona com ele".

Rede entre computadores e o relay tambem so se provam de verdade num
servidor.

## O que fazer quando der errado

Se o sistema nao subir, crie o arquivo /os/safemode pelo shell da ROM
(edit /os/safemode e salve vazio). O boot passa direto e voce cai no
shell. Apague o arquivo para voltar ao normal.

Se um programa travar, o Gerenciador de Tarefas fecha ele. Se a janela
inteira ficar estranha, Ctrl+Esc abre o menu Iniciar e da para
reiniciar por la.

Problema encontrado no jogo vira correcao nas proximas atualizacoes. O
app Atualizar OS existe para isso: ele compara com o repositorio e baixa
so o que mudou.
