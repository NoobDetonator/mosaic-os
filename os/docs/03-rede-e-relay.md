# Rede e relay

Sao duas redes diferentes, e elas nao dependem uma da outra.

## Rede local (rednet)

Liga computadores Mosaic entre si dentro do jogo. Precisa de um modem
no computador. Ligue em Config, na opcao Rede entre computadores.

O app Rede procura os vizinhos e mostra ID, nome e versao de cada um.
Com o Controle remoto voce roda codigo Lua num deles.

A senha fica em Config, em Rede entre computadores, e e' ela que libera
comando remoto. SEM senha o computador so' responde consulta: ele diz
quem e', qual versao tem e o que esta ligado nele, e recusa qualquer
coisa que mude alguma coisa. Para mandar nele, os dois lados precisam
ter a MESMA senha.

A senha nunca viaja pela rede. O que vai junto do pedido e' uma
assinatura (HMAC-SHA1) feita com ela: quem nao tem a senha nao consegue
produzir a assinatura, e quem estiver escutando a rede nao aprende a
senha ouvindo. O pedido tambem leva a hora e um numero unico, e o
computador recusa pedido velho ou repetido - senao bastaria gravar uma
mensagem da rede e reenviar depois para mandar no computador dos outros.

Consequencia pratica: computador com Mosaic antigo nao conversa com um
atualizado quando ha senha. O recado e' "pedido sem assinatura". Atualize
os dois.

## Relay (fora do jogo)

O relay e um servidor que roda no seu PC, fora do Minecraft. Com ele
voce ve e controla o computador pelo navegador, e o Claude Code
consegue operar a maquina direto.

No PC:

  cd relay
  npm install
  node relay.js

Ele imprime o endereco e um token. Em Config, preencha:

  ws://SEU_IP:8765/ws/computer

e o token. Clique em Testar antes de salvar, e reinicie depois: o
servico do relay so sobe se a URL ja estiver definida no boot.

## Qual endereco usar

Quem faz a conexao e o computador do jogo, saindo de dentro do
servidor ate o seu PC. Entao o endereco tem que ser um que o SERVIDOR
enxergue, nao um que so funcione no seu PC.

- Mundo local: use localhost.
- Servidor na mesma rede da sua casa: o IP da sua maquina na rede.
- Servidor remoto com Radmin ou Hamachi: o IP da VPN.
- Servidor remoto sem VPN: porta liberada no roteador, ou um tunel.

## Quando o Testar falha

O botao Testar troca ws por http e chama /api/ping. Ele testa a rede
sem depender do websocket, entao separa os problemas:

- Sem resposta: o servidor nao alcanca o seu PC, ou o firewall barra.
- A API http esta desativada: o admin precisa ligar no servidor.
- Responde, mas a conexao nao sobe: e o websocket especificamente.

Atencao a uma armadilha: o CC:Tweaked bloqueia faixas de IP privadas
por padrao (192.168, 10., 172.16 a 31, 127.). Num servidor na mesma
rede da casa isso barra a conexao ate o admin liberar aquele endereco.
IP de Radmin (26.) e de Hamachi (25.) nao caem nessa faixa e passam.
