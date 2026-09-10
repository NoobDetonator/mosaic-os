# Cluster: varios computadores como um sistema so

Um computador do Minecraft e pequeno: 1 MB de disco, e um orcamento de tempo
que o jogo corta em sete segundos. Trocar de linguagem nao levanta isso -
o limite e do mod, nao do Lua.

O jeito de crescer sem depender de nada fora do jogo e ter **mais
computadores**. Cada um traz o proprio disco e o proprio tempo de CPU.

O cluster faz eles se comportarem como um sistema, em vez de ilhas que voce
visita uma por uma.

## Como montar

Cada computador precisa de um **modem** ao lado (ou equipado, no caso de uma
turtle) e da rede ligada.

Em **Config**, caixa "Rede entre computadores":

1. ligue a rede;
2. de um **nome** ao computador;
3. ponha a mesma **senha** em todos - sem senha, um computador so responde
   consulta e recusa qualquer comando;
4. escolha o **papel**: um deles e `mestre`, todos os outros sao `no`;
5. escreva o **grupo**, se quiser separar a frota (`mina-norte`, `fazenda`).

Reinicie. Em segundos o painel do mestre mostra todo mundo.

## O painel

O app **Cluster** so faz sentido no mestre. Ele lista a frota agrupada, com
nome, tipo, versao do Mosaic, ha quanto tempo cada um falou, e o combustivel
das turtles.

Com um no selecionado, **Acoes** oferece:

| acao | o que faz |
|---|---|
| Detalhes | perifericos, espaco em disco, o que ele esta rodando |
| Terminal remoto | abre um terminal naquele computador |
| Executar Lua | manda um pedaco de codigo |
| Atualizar este no | deixa ele igual ao mestre |
| Atualizar o grupo | o mesmo, para todos do grupo |
| Limpar o que sobra | apaga arquivo que o mestre nao tem mais |
| Reiniciar | um, ou o grupo inteiro |
| Esquecer este no | tira da lista (ele volta se bater ponto de novo) |

## Grupos

Grupo e so um nome que voce escreve. Serve para nao misturar: as turtles da
mina nao recebem a ordem que era da fazenda.

Um computador pertence a um grupo, e as acoes de grupo alcancam todos de uma
vez.

## Espalhar o Mosaic

O mestre e o unico que precisa de internet. **Atualizar este no** compara os
arquivos dele com os do mestre, manda so o que difere, e reinicia o outro.

Assim uma turtle nova entra na frota com o Mosaic instalado na mao **uma vez**,
e daí em diante ela se atualiza sozinha junto com o resto.

## Por que o no fala primeiro

Cada computador **empurra** uma batida de ponto para o mestre a cada poucos
segundos. O mestre nao sai perguntando.

Isso parece detalhe e nao e. Quando ninguem esta por perto, o pedaco de mundo
descarrega e o computador **nao pausa**: ele perde tudo que estava fazendo e
volta ao shell vazio. Um computador que renasce assim simplesmente volta a bater
ponto, e ninguem precisa perceber que ele sumiu.

E por isso, tambem, que a lista do mestre vai para disco: reiniciar o mestre nao
apaga a frota.

Tres batidas perdidas contam como fora do ar. Uma e rede, duas e azar, tres e
ausencia.

## Turtles

Turtle e um computador que anda. Instale o Mosaic nela como em qualquer outro,
ponha um modem equipado, e ela vira um no como os demais - com combustivel e
posicao aparecendo no painel.

A tela de uma turtle e pequena demais para area de trabalho, entao ela abre o
app **Turtle**: onde esta, quanto de combustivel tem, e o que da para mandar
fazer.

**A posicao vai para disco a cada passo**, e nao no fim da tarefa. E a mesma
razao de sempre: a turtle pode morrer entre um passo e o seguinte, e precisa
saber onde estava ao acordar.

Se houver GPS montado por perto, ela se acha sozinha. Sem GPS, ela conta os
proprios passos - e aí voce precisa dizer onde ela comecou.

## O que atrapalha, e nao tem conserto no codigo

**Chunk descarregado.** Se ninguem estiver perto, o computador para de existir
ate alguem voltar. Numa base espalhada esse e o problema numero um, e a solucao
e chunk loader ou aceitar que o braco distante dorme.

**Alcance do modem.** Sem fio alcanca 64 blocos, e mais conforme sobe. Modem
*ender* nao tem limite e atravessa dimensao - para uma frota espalhada, ele e
praticamente obrigatorio.

**A rede e aberta.** Qualquer computador no alcance ouve o que passa. A senha
do Mosaic assina os comandos, entao ninguem manda ordem no seu lugar - mas o
conteudo das mensagens viaja a vista.
