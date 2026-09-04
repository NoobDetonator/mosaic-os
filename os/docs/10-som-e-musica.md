# Som e musica

O Mosaic faz barulho. Abrir e fechar janela tem som, erro tem som, e ligar
tem som. E existe um tocador de musica que aceita link do YouTube.

Tudo isso precisa de uma coisa so: um **alto-falante** encostado no
computador (ou ligado por modem com fio). Sem ele nada quebra, so fica
quieto.

## Ligando e desligando

Em **Config** ha uma caixa **Som**, com uma chave para ligar os sons do
sistema e um volume de 0 a 3. Se nao houver alto-falante por perto, a
propria caixa avisa - o aviso e medido na hora, nao e palpite.

Volume 0 cala de verdade, sem precisar desligar a chave.

## O tocador

O app **Musica** tem um campo onde voce cola um link ou digita o nome da
musica, e uma fila embaixo.

- **Enter** no campo poe na fila. Se nada estiver tocando, comeca sozinho.
- **Del** na fila tira a musica selecionada.
- **Enter** numa musica da fila pula direto para ela.
- Os botoes fazem o obvio: Tocar, Pausar, Proxima, Parar.

Fechar a janela **nao para a musica**. Quem para e o botao Parar. A fila
mora num servico, nao na janela - assim da para fechar o tocador e
continuar ouvindo enquanto usa outra coisa.

E como qualquer app, o tocador pode ir para um monitor: botao direito no
botao dele na barra de tarefas.

## Por que precisa do relay

O computador do Minecraft nao fala com o YouTube. Ele nao teria como: nao
sabe o que e um video, e nao aguentaria converter audio.

Quem faz isso e o **relay**, o programa que roda no seu PC. Ele baixa,
converte para o formato que o alto-falante entende, e serve em pedacos.
O computador so pede pedaco e empurra para o alto-falante.

Entao, para o tocador funcionar:

1. o relay tem que estar ligado no seu PC;
2. o endereco dele tem que estar em **Config > Relay**;
3. o PC precisa ter o `yt-dlp` e o `ffmpeg` instalados.

Se faltar alguma coisa, o app diz qual - em vez de ficar mudo.

## A primeira vez demora

Cerca de **meio minuto**: o relay tem que baixar a musica e converter. O
app mostra "Preparando: baixando..." nesse tempo. Nao esta travado.

Da segunda vez em diante a mesma musica comeca na hora, porque fica
guardada no seu PC.

## O que esperar do som

O formato e mono, e a qualidade e parecida com radio AM. Nao e limitacao
nossa: e o unico formato de audio que o ComputerCraft toca, um bit por
amostra.

Cada pedaco de musica que chega vale 2,7 segundos de som e custa 38
milissegundos para o computador decodificar. Ou seja, tocar musica gasta
perto de 1% do computador - da para ouvir e trabalhar ao mesmo tempo.
