# Armazem em rede

O Armazem transforma varios baus numa colecao pesquisavel. Voce procura um
item, escolhe a quantidade e manda para o bau de saida. Para devolver, poe os
itens no bau de entrada; o servico distribui o conteudo pelos baus da rede.
O catalogo e a coleta automatica continuam funcionando com a janela fechada.

## Montagem

1. Ligue um **modem com fio** ao computador.
2. Ligue um modem com fio em cada bau de armazenamento e conecte todos pelo
   mesmo cabo. Ligue tambem um bau exclusivo para **Entrada** e outro para
   **Saida** nessa mesma rede.
3. Abra **Armazem** no menu Iniciar. Na aba **Baus**, escolha o papel Entrada
   de um bau e Saida de outro. Atribua Armazenar a um inventario que nao foi
   reconhecido automaticamente como bau, se voce realmente quiser inclui-lo.
4. Confira os totais na aba **Itens**. Use F5 para atualizar imediatamente.

Os baus reconhecidos na rede entram no armazenamento automaticamente. Maquinas
e inventarios de tipo desconhecido ficam de fora ate voce escolher Armazenar.
Os nomes locais como `left` e `top` tambem ficam de fora: um mesmo bau pode
aparecer por lado e pela rede, e so a rota da rede permite transferir entre
perifericos remotos.

## Usar

- Digite parte do nome exibido ou do ID do item na busca. Variantes com NBT
  diferente aparecem separadas para nao misturar itens encantados ou modificados.
- Selecione o item e escolha **Sacar**. A quantidade solicitada vai para o
  bau de Saida; se nao houver espaco ou estoque suficiente, so a parte que
  couber sera movida e a tela mostrara o total real.
- Para guardar, coloque itens na Entrada. A coleta automatica tenta mover ate
  256 unidades por rodada, priorizando pilhas iguais e depois espacos livres.
  O botao **Depositar** faz uma rodada sob demanda.
- Para devolver algo retirado, passe da Saida para a Entrada. A Saida nunca e
  tratada como parte do estoque, evitando que o sistema recolha o item antes
  de voce pega-lo.

## Painel Baus

Cada inventario mostra papel, ocupacao e estado de leitura. Voce pode marcar
um inventario como **Ignorar** para impedir que o Armazem mova itens nele.
Use isso para baus de producao ou do reator. A opcao **Auto** liga ou desliga
a coleta periodica da Entrada; depositar manualmente continua disponivel.
As escolhas ficam em `/os/var/storage.json` e sobrevivem ao reinicio.

## Se nada se move

- Verifique se computador, Entrada, Saida e baus estao na **mesma rede de
  modems com fio**. Apenas encostar um bau no computador nao basta.
- Confira os papeis na aba Baus e se a Saida tem espaco livre.
- Use F5 apos instalar um modem ou adicionar um bau. O servico tambem percebe
  perifericos novos e atualiza periodicamente.
- O numero mostrado depois de cada operacao e a quantidade realmente movida;
  o servico confere de novo o estoque apos cada transferencia.
