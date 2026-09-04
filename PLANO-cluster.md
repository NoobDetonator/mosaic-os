# Plano: o cluster — vários computadores como um sistema só

## Contexto

Você perguntou o que deixaria os projetos maiores. A resposta honesta foi: dentro do jogo, o
teto não é a linguagem, é o computador. Cada computador do CC tem 1 MB de disco, uma fila de
256 eventos e um orçamento de tempo próprio — e a **única** forma de levantar isso sem
depender do seu PC ligado é ter mais computadores.

Hoje o Mosaic já enxerga os outros: o `netd` acha computadores Mosaic pela rede e o app Rede
manda comando para um, na mão, um de cada vez. O que falta é a camada em cima — eles se
comportarem como **um sistema** em vez de ilhas que você visita.

Decidido com você: **a base inteira primeiro** (painel, grupos, gerência, espalhar programa),
com a mineração de verdade vindo depois em cima dela. O mestre é **escolhido na configuração**,
não eleito. E espalhar atualização entra agora, porque sem isso cada turtle nova exigiria
instalação na mão.

---

## O que a pesquisa mudou no desenho

**1. Chunk descarregado mata o programa.** Quando ninguém está perto, o computador não pausa:
ele perde o estado de execução e volta para o shell vazio. A comunidade resolve isso escrevendo
programas *sem estado na memória* — tudo que importa vai para disco, e o programa recomeça
lendo o disco. Isso não é um detalhe de implementação, é a forma de toda a camada:

- **o nó empurra, o mestre não pergunta.** Nó que renasce simplesmente volta a bater ponto;
- **quem manda em tarefa é o mestre**, e a tarefa é gravada em disco dos dois lados;
- nada guarda estado importante só na memória.

(A documentação oficial não fala disso; é achado de comunidade. Confirmar no servidor.)

**2. `rednet` não garante entrega nem ordem, e é falsificável.** A própria documentação diz que
`send` devolver `true` "não garante que a mensagem foi recebida", e avisa que outro computador
pode fingir ser você. Então: toda troca é pedido/resposta com correlação por `id` e prazo, e
nada depende de uma mensagem única chegar.

**3. Alcance do modem sem fio: 64 blocos**, crescendo com a altitude até 384 no teto do mundo.
Modem *ender* não tem limite e atravessa dimensão. Para uma frota espalhada, ender é
praticamente obrigatório — e o mesmo vale para GPS, que precisa de **quatro** hosts.

**4. O `manifest.json` já tem `sha1` de cada arquivo, e nenhum código Lua usa.** O
`install.lua` baixa tudo e compara byte a byte; o `pkg.lua` faz o mesmo. Isso é a peça que
falta para "atualize um e espalhe" — mas calcular sha1 em Lua é lento demais (foi por isso que
foi evitado). O plano usa **versão + tamanho** como discriminador, que é de graça.

**5. Um bug que trava tudo:** `mosaic.net.password` e `mosaic.net.name` **não têm interface
nenhuma**, apesar de `os/docs/03-rede-e-relay.md` mandar configurar em Config. E sem senha, um
nó só responde consulta — não aceita comando. Sem consertar isso, nenhum cluster funciona.

**6. `ask()` já existe duas vezes**, copiado em `netcenter.lua:63` e `remote.lua:34`, com
prazos diferentes. E o `netcenter` varre os vizinhos **um por vez, um segundo cada** — com dez
nós isso é dez segundos de tela travada. Um painel de cluster não pode nascer assim.

**7. A tela da turtle.** A documentação diz **39×13** (o inventário come o resto). Se for isso,
`wm.tiny` liga sozinho (`W < 40`) e o Mosaic já se adapta: janela sempre cheia, sem arrastar,
botão " M ". **Conferir no jogo** — é o único número deste plano que não consegui medir.

---

## Onda 1 — a base compartilhada, e o conserto que destrava

**`os/lib/netx.lua`** — o que hoje está copiado, num lugar só:

- `netx.PROTOCOL` (hoje a string `"mosaic"` está escrita em três arquivos);
- `netx.ask(id, msg, prazo)` — pedido/resposta com correlação por `id` **e** por remetente;
- `netx.askAll(msg, prazo)` — transmite e colhe todas as respostas dentro de **um** prazo.
  É isto que substitui a varredura de um segundo por vizinho.

**Interface para senha e nome do computador** em `os/apps/settings.lua`, na caixa Rede. É
pequeno e é o que destrava o resto.

**E a senha passa a ser lida na hora**, não uma vez no boot — hoje trocar a senha em Config não
faz efeito até reiniciar, e ninguém adivinha isso.

## Onda 2 — papéis, grupos e batida de ponto

O `netd` vira o agente do nó. **Um daemon só**, não dois: o `rednet_message` chega por difusão
para todos os processos, e dois daemons respondendo o mesmo pedido seria confusão.

Chaves novas em `boot.lua`, junto das outras:

| chave | o que é |
|---|---|
| `mosaic.cluster.role` | `mestre` ou `no` |
| `mosaic.cluster.master` | o ID do mestre (para os nós) |
| `mosaic.cluster.group` | o grupo deste nó — `mina-norte`, `fazenda`... |

**O nó bate ponto** a cada poucos segundos, empurrando para o mestre: nome, grupo, tipo
(computador / turtle / pocket), versão do Mosaic, periféricos ao lado, e — se for turtle —
combustível, posição e o que está na mão.

**O mestre guarda a lista** com a hora do último contato, marca como fora do ar quem falhou
três batidas, e **grava em disco** (`/os/var/cluster/nos.json`) para que reiniciar o mestre não
apague a frota.

Tipo do nó sai de `turtle ~= nil` / `pocket ~= nil` — não precisa configurar.

**Grupo é um campo só, de texto livre.** Foi o que você pediu: separar as turtles da mina das
turtles da fazenda. Um nó pertence a um grupo; comando pode ir para um nó, para um grupo, ou
para todos.

## Onda 3 — o painel

**`os/apps/cluster.lua`**, no mestre. Lista com **cabeçalho por grupo** (o `ui.list` já sabe
desenhar cabeçalho de seção), e por linha: nome, tipo, versão, estado, e para turtle o
combustível.

Ações, por nó **ou pelo grupo inteiro**: ver detalhes, mandar comando, abrir terminal remoto
(o `remote.lua` já existe), reiniciar, atualizar.

Aproveita o padrão de layout da casa — barra de botões em `bottom = 0`, estado `above` dela,
lista com `fillTo`. Igual ao `netcenter` e ao `pkg`.

## Onda 4 — espalhar o software

O mestre é o único que precisa de internet. Ele lê o `manifest.json` como o `pkg.lua` já faz, e
compara com o que cada nó relata.

**O discriminador é versão + tamanho de arquivo**, e não sha1: calcular sha1 em Lua é lento
demais para 95 arquivos, e essa conclusão já estava anotada no `install.lua`. Versão diferente
manda tudo; versão igual manda só o que difere em tamanho.

Isso erra num caso: dois conteúdos diferentes com exatamente o mesmo tamanho. Por isso existe
um botão **"reinstalar tudo"**, e a limitação fica escrita na documentação em vez de escondida.

O transporte já existe: `netd.sendFile` empurra arquivo e até cria a pasta. Falta um handler de
**reiniciar** — hoje só há `shutdown` — porque `mosaic.lib` guarda módulo em cache e um arquivo
novo só vale depois do boot.

**Arquivo grande vai picado.** O `sendFile` de hoje põe o corpo inteiro numa mensagem, e o
`ui.lua` tem 1234 linhas. O limite de tamanho de mensagem do rednet não é documentado em lugar
nenhum — então o envio passa a ser em pedaços, com o nó montando em disco.

## Onda 5 — a turtle vira nó de verdade

**`os/lib/turtlex.lua`**:

- detecção e capacidades (tem picareta? tem modem? tem combustível?);
- movimento seguro: tenta, e se falhar diz por quê (bloco, mob, sem combustível);
- **posição gravada em disco a cada passo.** É a consequência direta do chunk descarregado:
  a turtle tem que saber onde está depois de renascer. GPS quando houver quatro hosts por
  perto, e conta própria como reserva;
- combustível: `getFuelLevel` pode devolver `"unlimited"`, que não é número — tratar.

**Um app de estado da turtle**, que abre sozinho nela: onde está, quanto de combustível, que
grupo, que tarefa. Numa tela de 39×13 não cabe desktop, cabe um painel.

Proibido nesta versão: `turtle.getEquippedLeft/Right` (é 1.116) e o prazo do `rednet.lookup`
(1.118).

## Onda 6 — fechamento

Documentação em `os/docs`, `CLAUDE.md` com os fatos medidos, manifest, plano atualizado, push.

---

## Arquivos

**Novos:** `os/lib/netx.lua`, `os/lib/turtlex.lua`, `os/apps/cluster.lua`, app de estado da
turtle, `os/share/icons/cluster.nfp`, doc em `os/docs/`.

**Reescritos por dentro:** `os/net/netd.lua` (papéis, batida de ponto, tabela de nós, envio
picado, handler de reiniciar, senha lida na hora).

**Alterados:** `os/apps/netcenter.lua` e `os/apps/remote.lua` (passam a usar o `netx` em vez da
cópia local), `os/apps/settings.lua` (senha e nome), `os/boot.lua` (chaves novas),
`os/apps/registry.lua`, `tools/test/fake-periph.lua` (rednet falso), `tools/test/run.lua`,
`tools/craftos.js` (modo de dois computadores), `CLAUDE.md`.

**Reaproveitado sem mexer:** `netd.sendFile`/`getFile` como transporte, `hal.list()` como
inventário de periféricos do nó, o `manifest.json` e o `pkg.lua` como fonte da verdade de
versão, `remote.lua` como terminal remoto, e o padrão de daemon do `musicd` — que já resolveu a
lição certa: **pergunta sobre o mundo se responde na hora, não se guarda**.

## Verificação

```bash
node tools/lint.js && node tools/test.js && node tools/craftos.js test
```

O teste de cluster sobe em três degraus, do mais barato ao mais caro:

1. **`rednet` falso** em `fake-periph.lua`, no molde do `http` falso que já está lá: um
   barramento em memória. Cobre protocolo, correlação por `id`, senha, prazo e a tabela de nós.
2. **Dois computadores de verdade no CraftOS-PC.** Ele suporta vários, cada um com disco e
   periféricos próprios, e o modem aceita número de rede. **Falta confirmar se o headless
   permite** — ele recusa monitor ("not available in this mode"), e pode recusar computador
   também. Se recusar, o degrau 1 é o que sobra fora do jogo.
3. **No servidor.** Inevitável para alcance de modem sem fio, topologia de cabo e o
   comportamento real do chunk descarregado.

Regras que continuam valendo: `craftos.js test` **antes** de commitar; app novo entra na lista
de fumaça; nada de rede pode travar o OS; print depois de cada onda.

## Fora de escopo

Mineração e fila de trabalho (é a próxima empreitada, sobre esta base), eleição automática de
mestre, criptografia do rednet, pathfinding, e qualquer coisa que dependa de mod de chunk
loader.
