# Arquivos e atalhos

A area de trabalho e uma pasta de verdade: /home/desktop. O que estiver
dentro dela aparece na tela, e o que voce apagar de la some mesmo.

## Onde ficam as coisas

  /home/desktop      a area de trabalho
  /home/programas    os atalhos dos programas
  /home/downloads    /home/imagens    /home/documentos
  /apps              os seus programas em .lua

Sem acento nos nomes de proposito: a fonte do CC e byte a byte, e um nome
em UTF-8 aparece como lixo na tela.

## Clique simples e clique duplo

Um clique SELECIONA. Dois cliques ABREM. E assim para que voce consiga
escolher um icone para renomear, copiar ou ver propriedades sem abrir o
programa junto.

Pelo teclado: as setas andam pela grade e Enter abre o selecionado.

## Atalho

Atalho e um arquivo .lnk comum. Ele pode apontar para tres coisas:

  um programa do sistema     Arquivos, Config, Terminal
  uma pasta                  a pasta Programas e um atalho assim
  um arquivo qualquer        um .lua seu, com argumentos se quiser

Para criar: clique com o botao direito no vazio da area de trabalho e
escolha Novo atalho. Ou clique com o direito num programa do menu
Iniciar e escolha Criar atalho.

Renomear um atalho muda o nome que aparece E o nome do arquivo, para os
dois nao ficarem diferentes.

Apagar um atalho e definitivo: ele NAO volta na proxima atualizacao do
sistema. Isso e de proposito, para a area de trabalho ser sua. Se a
pasta inteira sumir, ai sim o sistema recria tudo do zero.

## Clique direito

Funciona em todo lugar:

  em cima de um icone     Abrir, Recortar, Copiar, Renomear, Excluir,
                          Propriedades, e Atalho na area de trabalho
                          (quando voce ja nao esta nela)
  no vazio                Nova pasta, Novo arquivo, Novo atalho, Colar,
                          Atualizar. Na area de trabalho vem tambem
                          Novo programa, Terminal, Configuracoes e Sobre
  no menu Iniciar         Abrir, Criar atalho, Propriedades

## Recortar, copiar e colar

Funciona entre janelas: recorte no Arquivos, abra outra pasta e cole.
As duas janelas enxergam o mesmo recorte.

  Ctrl+X   recortar        Ctrl+C   copiar        Ctrl+V   colar
  F2       renomear        Del      excluir       F5       atualizar

Nome repetido no destino vira "nota (2).txt" em vez de sobrescrever.
Colar uma pasta dentro dela mesma e recusado, senao o sistema entraria
em recursao infinita.

## O que abre cada arquivo

  .nfp .nft            Paint
  .lua                 pergunta: Executar ou Editar
  .txt .md .json       Editor
  .cfg .log .lst       Editor
  pasta                janela de pasta
  o resto              use Abrir com...

## O Arquivos

A coluna da esquerda tem Lugares (as pastas de sempre) e Discos (o disco
do computador e cada disquete que estiver montado). Em tela estreita ela
some sozinha para o painel caber; F9 liga e desliga na mao.

Backspace sobe um nivel. Ir para abre qualquer caminho digitado.

## Disquete

Inserir ou tirar um disquete atualiza a lista de Discos e mostra um
aviso na tela. Se voce estava dentro do disquete que saiu, o Arquivos
volta para /home em vez de ficar preso numa pasta que nao existe mais.
