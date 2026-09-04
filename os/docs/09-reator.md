# Reator

O gerenciador do reator do Powah: mostra o que esta acontecendo, abastece
sozinho, avisa no chat e joga o painel num monitor na parede.

Ele nao precisa de nada alem do reator para funcionar. Cada peca a mais
que voce ligar acende uma parte a mais da tela.

## O que ligar

- **O reator**: encoste o computador numa peca do reator, ou ligue os dois
  na mesma rede com modem com fio. Sem isso o app so mostra erro.
- **Um bau** com os itens que o reator come, na mesma rede. E de onde sai o
  abastecimento.
- **Chat Box** (Advanced Peripherals): os avisos vao para o chat do
  servidor.
- **Energy Detector** na linha de saida: mostra quanto esta saindo de FE/t.
- **Monitor**: o mesmo painel na parede, adaptado ao tamanho dele.

Importante: `pushItems` e `pullItems` so funcionam **dentro da mesma rede**.
Um bau encostado no computador nao serve se o reator vier por cabo. A aba
Config so lista os inventarios que dao para usar, entao se a lista vier
vazia, falta um modem com fio no bau.

## As abas

### Painel

Uma barra por recurso: os itens que estao dentro do reator, a agua, a
energia do buffer e o balanco.

- O numero fica sempre na mesma coluna, para bater o olho e comparar.
- Quando da para calcular, aparece do lado quanto tempo falta (`~7min`).
  Nao e chute: e a velocidade com que o valor esta caindo agora.
- **Balanco** e o numero mais util da tela. Ele tem sinal: `+1.2k FE/t`
  quer dizer que o buffer esta enchendo, `-270 FE/t` que esta esvaziando.
  A vazao sozinha nao responde "estou produzindo mais do que gasto?".
- Embaixo, os graficos. Eles preenchem toda a altura que sobra, entao num
  monitor alto voce ve tres ou quatro series em vez de uma.

O titulo de cada grafico traz o valor de agora e a faixa que o desenho
esta usando (`Buffer FE: 9.71M   0..9.71M`). Sem isso o desenho mostra a
forma e esconde a escala.

### Controle

As tres alavancas, cada uma com o que faz escrito do lado.

O reator do Powah **nao tem liga e desliga**. O que liga e desliga e haver
ou nao uraninita dentro dele. Por isso:

- **Iniciar** poe uraninita do bau no reator.
- **Abastecer** completa tudo que estiver faltando, nao so o combustivel.
- **Parar** tira toda a uraninita e manda para o bau.

Embaixo, em palavras, o estado: ligado ou parado, qual bau esta escolhido,
se a reposicao automatica esta ligada, e a lista do que tem dentro.

### Config

- **Bau com os itens do reator**: de onde vem o abastecimento e para onde
  vai o combustivel quando voce manda parar.
- **Repor sozinho quando faltar**: liga a reposicao automatica.
- **Completar cada item ate**: o alvo. Vale para todo item que estiver
  dentro do reator, nao so para a uraninita.
- **Alertas**: abaixo de quanto avisar, e se manda para o chat.

### 3D

O mesmo painel em barras de tres dimensoes, num circulo, cada recurso na
sua cor, com a legenda ao lado.

- **Setas** giram a camera
- **Espaco** para e volta o giro

E enfeite, e esta numa aba propria por isso: quem esta operando le numero.
Mas e enfeite honesto, porque a altura de cada coluna e a mesma fracao que
a barra do painel mostra.

### Registro

Tudo que aconteceu, com hora: alerta que disparou, alerta que normalizou,
item reposto e de onde veio.

## Como o abastecimento decide

Quem diz do que o reator precisa e **o proprio reator**: o app olha o que
esta dentro dele e completa cada coisa ate o alvo, puxando do bau.

Isso quer dizer que:

- ele repoe uraninita, gelo seco, carvao, redstone, ou o que mais o mod
  aceitar, sem precisar saber o que cada slot significa;
- ele **nao** poe no reator um item que ainda nao esta la dentro. Para
  comecar a usar um item novo, ponha um dele na mao primeiro;
- item que falta no bau simplesmente nao entra, e isso aparece no
  registro como nada.

## Os avisos

Vao para a area de trabalho, para o registro e, se houver Chat Box, para o
chat do servidor:

- item abaixo do minimo, um aviso por item;
- agua abaixo do minimo;
- reator desmontado;
- combustivel ou agua que **vao** acabar no ritmo atual, antes de acabarem;
- buffer que vai zerar no ritmo atual;
- o que foi reposto, com quanto entrou de cada coisa.

Cada aviso so fala uma vez, e fala de novo quando normaliza. Ele so
desliga com 25% de folga acima do limite, senao um valor tremendo na borda
encheria o chat de liga e desliga.

## Sobre temperatura

Nao tem, e nao vai ter. A temperatura do Powah mora no nucleo do
multiblock, e o nucleo fica cercado de pecas no meio do reator: nao da
para encostar um Block Reader nele sem desmontar tudo.

O sinal util no lugar dela e o prazo que aparece nas barras. Saber que o
combustivel acaba em sete minutos e mais acionavel que saber a temperatura
de agora.
