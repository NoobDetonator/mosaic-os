# Rede e relay

Sao duas redes diferentes, e elas nao dependem uma da outra.

## Rede local (rednet)

Liga computadores Mosaic entre si dentro do jogo. Precisa de um modem
no computador. Ligue em Config, na opcao Rede entre computadores.

O app Rede procura os vizinhos e mostra ID, nome e versao de cada um.
Com o Controle remoto voce roda codigo Lua num deles.

Se voce definir uma senha em Config, os comandos remotos passam a
exigir ela. Sem senha, qualquer computador Mosaic da rede pode mandar
comando: so use assim numa base fechada.

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
