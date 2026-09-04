# Plano: o gerenciador do reator vira um operador

## O que existe hoje

O `apps/reactor.lua` le o reator, desenha barras, guarda historico, avisa no chat e sabe
retirar o combustivel. Funciona, e a foto no servidor mostra tres problemas de cara:

1. **Metade do monitor fica vazia.** O painel desenha o que tem e para; o resto da parede
   fica cinza. Em coluna unica o grafico tem teto de 7 linhas (`math.min(7, ...)`), entao
   quanto maior o monitor, mais area sobrando.
2. **Tem "Parar" e nao tem "Iniciar".** Parar e' tirar a uraninita; ligar de volta seria pol-la
   de volta, e esse botao nunca foi escrito. Meio caminho.
3. **Le cinco slots e mostra dois.** Uraninita e gelo seco viram barra; bloco de carvao e
   bloco de redstone caem num `extras` que ninguem desenha.

E o abastecimento so' sabe repor **uraninita**. O reator consome mais coisa que isso.

## O que foi medido no servidor (nao e' suposicao)

Computador 2, "Powah Manager", CC:T 1.101.3 / MC 1.16.5. Perifericos: `powah:reactor_part_4`,
`minecraft:chest_4`, `chatBox_5`, `energyDetector_4`, `blockReader_4`, monitor em cima.

- O `powah:reactor_part` **e' um inventario de 5 slots** e responde `list`, `getItemDetail`,
  `getItemLimit`, `pushItems`, `pullItems`, `tanks`, `getEnergy`, `getEnergyCapacity`.
- Estado real: slot 1 vazio, 2 uraninita, 3 bloco de carvao, 4 bloco de redstone, 5 gelo seco.
  Todo slot aceita 64. Tanque: 1000 mB de agua.
- **`reactor.pullItems("minecraft:chest_4", slot, n, destino)` funciona**, conferido ao vivo:
  a uraninita foi de 60 para 64.
- O gelo seco **e' consumido** (22 -> 21 em poucos minutos). Carvao e redstone ficaram parados
  no mesmo periodo — sao reserva, nao gasto continuo.
- O `blockReader` numa peca so' entrega `built`, `variant`, `redstone_mode` e `core_pos`.
  **Nao ha temperatura**, e o nucleo fica cercado de pecas. Combinado com voce: some com o
  assunto temperatura da interface em vez de ficar explicando por que ela falta.

## Decisoes

- **Abastecer por NOME DE ITEM, nao por slot.** O que estiver no reator define o que repor:
  cada item ganha um alvo (padrao 64) e e' completado do bau quando cai abaixo do minimo. Isso
  vale para uraninita, gelo seco, carvao, redstone e o que o mod inventar depois — sem
  precisar saber a semantica dos slots do Powah, que muda entre versoes.
- **Iniciar e' o par de Parar.** Mesmo mecanismo, sentido contrario.
- **Nada de temperatura** na interface, nem para dizer que falta.
- **O painel preenche a tela**, seja qual for o tamanho: o que sobra de altura vira grafico.

---

## Onda 1 — Abastecimento de verdade

`lib/powah`:

- `powah.consumables(reading)` — o que o reator tem dentro, por nome, com contagem e slot.
- `powah.topUp(hw, fromName, alvos)` — completa cada item ate' o alvo, puxando do bau. Devolve
  o que moveu, item a item, para o registro e o chat dizerem exatamente o que entrou.
- `powah.stop` / `powah.start` — tirar e por a uraninita, o par completo.

`apps/reactor.lua`: botao **Iniciar** ao lado do **Parar**, e a reposicao automatica passa a
valer para todos os itens, nao so' para o combustivel.

## Onda 2 — Ler tudo, avisar de tudo

Todo item do reator vira barra, historico e alerta, com o nome em portugues quando conhecido
(uraninita, gelo seco, bloco de carvao, bloco de redstone) e o id cru quando nao.

O chat passa a dizer o que foi reposto e de onde, nao so' que algo estava baixo.

## Onda 3 — O painel preenche a parede

O layout deixa de ser "desenha e para" e passa a ser "reparte a altura":

- o que e' fixo (titulo, barras, rodape) mede quanto quer;
- o que sobra vai para os graficos, que crescem ate' encostar embaixo;
- coluna dupla so' quando ha largura para as duas, como hoje, mas o teto de 7 linhas sai.

Conferido em varios tamanhos, do 29x12 ao 102x38, sem area cinza sobrando.

## Onda 4 — Grafico que se le

O `chart.line` de hoje e' uma serie, preenchida, sem escala nenhuma. Ganha:

- **eixo com o valor de cima e o de baixo**, senao o desenho nao diz quanto e';
- **varias series no mesmo quadro**, com cores diferentes;
- **legenda**;
- linha em vez de bloco solido quando ha mais de uma serie.

## Onda 5 — O painel em tres dimensoes

Agora que existe motor 3D, o monitor grande ganha uma vista em barras 3D: uma coluna por
recurso, altura pela porcentagem, cor por recurso, com legenda ao lado. E' enfeite consciente:
entra numa aba propria e so' onde ha tela para isso, nunca no lugar do numero.

## Onda 6 — Fechamento

Self-check do `powah` cobrindo o abastecimento novo, capitulo em `os/docs`, `CLAUDE.md`,
manifest, e o print do monitor de verdade dentro do jogo.

## Verificacao

Como o reator e' de verdade e esta ligado, cada onda e' conferida no servidor pelo relay, com
print da tela e do monitor — nao so' no emulador.


---

# Estado em 03/09/2026

Ondas 1 a 5 prontas e conferidas **no servidor**, pelo relay, com o reator de verdade
ligado. `node tools/lint.js` limpo (58 arquivos), `node tools/test.js` e
`node tools/craftos.js test` com 168 checagens e 0 falhas.

## O que ficou pronto

**Abastecimento.** `powah.consumables` agrupa o que esta dentro do reator por nome de item
e devolve em ordem de slot; `powah.topUp` completa cada um ate' o alvo puxando do bau.
Provado ao vivo: tirei 20 uraninitas do reator (64 -> 44), rodei o topUp, voltou a 64 e o
relatorio disse "Uraninita +20 -> 64".

**Iniciar existe.** O reator do Powah nao tem liga/desliga; o que liga e' haver uraninita
dentro. Agora sao tres botoes com o que cada um faz escrito do lado, numa aba Controle que
tambem diz em palavras se o reator esta ligado ou parado.

**Todo item vira metrica.** Cinco slots lidos, cinco barras, cinco historicos, cinco
alertas. Antes o bloco de carvao e o de redstone caiam num `extras` que ninguem desenhava.

**O painel preenche a parede.** A altura que sobra e' repartida entre quantos graficos
couberem, e o ultimo encosta embaixo. O buraco cinza da foto acabou.

**Grafico que se le.** Linha em vez de mancha preenchida, escala automatica, e o titulo com
o valor de agora e a faixa. Serie constante desenha no meio e nao colada na base.

**3D.** Aba propria: barras num circulo, cor por recurso, legenda com o numero, giro
automatico com temporizador proprio de 0,1 s que so' existe enquanto a aba esta na frente.

## Armadilhas encontradas (nao repetir)

- **`mosaic.lib` guarda o modulo em cache.** Sobrescrever o `.lua` no computador do jogo nao
  basta: o processo novo continua com o codigo antigo. Reinicie o computador.
- **O CC:T recusa faixa de IP privada** com "Domain not permitted", mesmo com o websocket do
  relay funcionando pelo mesmo endereco. Para o `http.get` use o IP publico (Radmin).
- **Cinza nao pode ser cor de recurso**, porque cinza e' o vazio da barra. O bloco de carvao
  ficava invisivel.
- **Serie perto do maximo com `fill` vira um retangulo solido.** Bonito e mudo.
- **Barra 3D em fileira tem angulo cego**: de perfil, as colunas se escondem umas atras das
  outras. Em circulo nao ha angulo ruim.
- **Lambert lava caixa alinhada aos eixos.** Mesma licao do `mesh.voxels`, aprendida de novo:
  cor por orientacao da face, nao por direcao de luz.
- **A barra de abas caia para os nomes curtos por UMA coluna.** Antes de encurtar nome, tire
  o espaco entre os botoes: cada um ja tem folga interna.

## Falta

**Onda 6 — fechamento.** Feito: capitulo [os/docs/09-reator.md](os/docs/09-reator.md),
`CLAUDE.md` com os fatos medidos do reator, e este plano. Falta o print do monitor de
verdade dentro do jogo, que so' voce consegue tirar.
