-- O scan do Geo Scanner virando cena 3D: uma veia por cor, e a turtle dentro dela.
--
--   local geo3d = mosaic.lib("geo3d")
--   local cena = geo3d.cena(grupos, { raio = 8, ligados = {...}, turtle = {x=,y=,z=} })
--   frame:draw(cena.objetos)
--
-- UM `mesh.voxels` POR TIPO, e nao um cubo por bloco. O `voxels` so' emite a face que da'
-- para fora, entao oito blocos de carvao grudados viram uma veia solida com as faces
-- internas descartadas - o desenho fica certo E barato. Com um cubo por bloco seriam 12
-- triangulos cada, sempre, e as faces internas apareceriam nas bordas.
--
-- As coordenadas do scan sao RELATIVAS ao scanner e vao de -raio a +raio. A grade do
-- `voxels` e' 1..N. A conversao mora num lugar so' (`indice`), porque errar isso desloca a
-- cena inteira em um bloco e ninguem percebe olhando.
local geo3d = {}

-- Cor por minerio, por palavra no nome. Dois motivos para ser tabela e nao sorteio: a mesma
-- veia tem de sair da mesma cor em toda varredura, e cor que lembra o minerio de verdade se
-- le' sem consultar legenda (ouro amarelo, redstone vermelho, lapis azul).
geo3d.CORES = {
    coal = colors.gray, iron = colors.lightGray, gold = colors.yellow,
    copper = colors.orange, diamond = colors.lightBlue, emerald = colors.lime,
    redstone = colors.red, lapis = colors.blue, quartz = colors.white,
    uranium = colors.green, osmium = colors.white, silver = colors.lightGray,
    lead = colors.purple, zinc = colors.cyan, tin = colors.cyan,
    nickel = colors.brown, fluorite = colors.magenta, aluminum = colors.lightGray,
    platinum = colors.cyan, iridium = colors.white, crystal = colors.pink,
    vinteum = colors.lightBlue, sulfur = colors.yellow, apatite = colors.cyan,
    niter = colors.white, cinnabar = colors.red, ruby = colors.red,
    sapphire = colors.blue, amber = colors.orange, salt = colors.white,
}

-- Cores para quem nao esta na tabela. Sai fora cinza e cinza claro: sao as do carvao e do
-- ferro, e repetir cor entre minerios diferentes e' o unico erro que a legenda nao conserta.
geo3d.RESERVA = {
    colors.magenta, colors.lime, colors.orange, colors.pink, colors.cyan,
    colors.purple, colors.yellow, colors.blue, colors.brown, colors.green,
}

function geo3d.corDe(nome, ordem)
    local corpo = tostring(nome):lower()
    for palavra, cor in pairs(geo3d.CORES) do
        if corpo:find(palavra, 1, true) then return cor end
    end
    -- `ordem` e' a posicao do grupo na lista: dois minerios desconhecidos na mesma varredura
    -- recebem cores diferentes, e a mesma varredura sempre da' o mesmo resultado.
    local i = ((tonumber(ordem) or 1) - 1) % #geo3d.RESERVA + 1
    return geo3d.RESERVA[i]
end

-- Coordenada do scan (-raio..+raio) para indice da grade (1..2*raio+1).
function geo3d.indice(v, raio) return math.floor(v) + raio + 1 end

-- Grade de ocupacao no formato que o `mesh.voxels` quer: layers[y][z][x].
--
-- `faixaY` corta na vertical. E' o filtro que mais rende: uma varredura de raio 8 tem 17
-- camadas, e olhar uma fatia de tres responde "o que tem na altura em que eu estou cavando"
-- sem o resto atrapalhar a vista.
function geo3d.grade(pontos, raio, faixaY)
    local n = raio * 2 + 1
    local layers, quantos = {}, 0
    for _, p in ipairs(pontos or {}) do
        local py = math.floor(p.y or 0)
        if not faixaY or (py >= faixaY[1] and py <= faixaY[2]) then
            local x = geo3d.indice(p.x or 0, raio)
            local y = geo3d.indice(py, raio)
            local z = geo3d.indice(p.z or 0, raio)
            if x >= 1 and x <= n and y >= 1 and y <= n and z >= 1 and z <= n then
                layers[y] = layers[y] or {}
                layers[y][z] = layers[y][z] or {}
                if not layers[y][z][x] then
                    layers[y][z][x] = true
                    quantos = quantos + 1
                end
            end
        end
    end
    return layers, n, quantos
end

-- ---------------------------------------------------------------- a cena

-- Monta os objetos para o `Frame:draw`.
--
-- opts.raio      raio da varredura (define o tamanho da grade)
-- opts.ligados   { [nome] = true } - quais tipos desenhar; nil = todos
-- opts.faixaY    { min, max } em coordenada de scan
-- opts.turtle    { x, y, z } em coordenada de scan, ou nil
-- opts.teto      maximo de blocos desenhados (protege o quadro)
function geo3d.cena(grupos, opts)
    opts = opts or {}
    local raio = opts.raio or 8
    local n = raio * 2 + 1
    local meio = n / 2
    local mesh = require("lib.mesh")
    local shade = require("lib.shade")
    local objetos, legenda, total = {}, {}, 0
    -- Teto MEDIDO, nao chutado. No servidor, 5204 triangulos custaram 247 ms por quadro num
    -- canvas de 160x108 pontos: ~21 mil triangulos/s. E' quarenta vezes mais lento que os
    -- 877 mil/s do bench no CraftOS-PC, que roda em PC e nao dentro do Minecraft.
    --
    -- 800 blocos dao ~5 mil triangulos, ~240 ms. E' o limite do que ainda se mexe; acima
    -- disso a janela engasga e a parede fica pior ainda. Quem quiser mais liga por filtro e
    -- assume o custo, mas o padrao nao pode ser inutilizavel.
    local teto = opts.teto or 800
    local cortou = false

    for ordem, g in ipairs(grupos or {}) do
        local mostrar = (opts.ligados == nil) or opts.ligados[g.nome]
        if mostrar and g.pontos and #g.pontos > 0 then
            local cor = geo3d.corDe(g.nome, ordem)
            local layers, tam, quantos = geo3d.grade(g.pontos, raio, opts.faixaY)
            if quantos > 0 then
                if total + quantos > teto then cortou = true else
                    total = total + quantos
                    -- Cor por ORIENTACAO da face, nunca por luz direcional: caixa alinhada
                    -- aos eixos tem seis normais, e luz joga metade delas no degrau escuro -
                    -- e' a mesma licao que deixou as barras 3D do reator quase todas cinzas.
                    local m = mesh.voxels(layers, tam, tam, tam, {
                        top = cor,
                        side = shade.darker[cor] or cor,
                        bottom = shade.darker[cor] or cor,
                        maxFaces = 6000,
                    })
                    objetos[#objetos + 1] = { model = m, x = -meio, y = -meio, z = -meio }
                end
                legenda[#legenda + 1] = { nome = g.nome, curto = g.curto, cor = cor,
                    n = quantos, ligado = mostrar }
            end
        elseif g.pontos and #g.pontos > 0 then
            legenda[#legenda + 1] = { nome = g.nome, curto = g.curto,
                cor = geo3d.corDe(g.nome, ordem), n = #g.pontos, ligado = false }
        end
    end

    -- A turtle por ultimo, e sempre visivel: ela e' a referencia de "onde eu estou nisso
    -- tudo", e some se for so' mais um bloco entre os minerios.
    if opts.turtle then
        local t = opts.turtle
        local x = geo3d.indice(t.x or 0, raio)
        local y = geo3d.indice(t.y or 0, raio)
        local z = geo3d.indice(t.z or 0, raio)
        if x >= 1 and x <= n and y >= 1 and y <= n and z >= 1 and z <= n then
            objetos[#objetos + 1] = {
                model = mesh.cube { top = colors.white, side = colors.lightGray,
                                    bottom = colors.gray },
                x = x - 1 - meio + 0.5, y = y - 1 - meio + 0.5, z = z - 1 - meio + 0.5,
                scale = 1.6,
            }
            legenda.turtle = true
        end
    end

    return { objetos = objetos, legenda = legenda, blocos = total, cortou = cortou,
             tamanho = n }
end

-- ---------------------------------------------------------------- self-check

function geo3d.demo()
    -- Cor pelo nome: a mesma veia sai da mesma cor sempre, e a cor lembra o minerio.
    assert(geo3d.corDe("minecraft:gold_ore") == colors.yellow, "ouro devia ser amarelo")
    assert(geo3d.corDe("minecraft:redstone_ore") == colors.red, "redstone devia ser vermelho")
    assert(geo3d.corDe("minecraft:lapis_ore") == colors.blue, "lapis devia ser azul")
    assert(geo3d.corDe("alltheores:ore_uranium") == colors.green, "uranio devia ser verde")
    assert(geo3d.corDe("MINECRAFT:COAL_ORE") == colors.gray, "a busca tem de ignorar caixa")

    -- Desconhecido cai na reserva, e dois desconhecidos na mesma lista nao repetem cor.
    local a = geo3d.corDe("mod:coisa_estranha", 1)
    local b = geo3d.corDe("mod:outra_coisa", 2)
    assert(a ~= b, "dois minerios desconhecidos nao podem sair da mesma cor")
    assert(a ~= colors.gray and a ~= colors.lightGray, "a reserva nao pode repetir carvao/ferro")
    assert(geo3d.corDe("mod:coisa_estranha", 1) == a, "a mesma entrada tem de dar a mesma cor")

    -- Indice: o centro do scan e' o meio da grade, e as pontas sao 1 e 2r+1.
    assert(geo3d.indice(0, 8) == 9, "o centro de um raio 8 e' o indice 9")
    assert(geo3d.indice(-8, 8) == 1, "a ponta negativa e' o indice 1")
    assert(geo3d.indice(8, 8) == 17, "a ponta positiva e' o indice 17")

    -- Grade: pontos viram ocupacao, e repetido nao conta duas vezes.
    local layers, n, q = geo3d.grade({
        { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 0, z = 0 },
    }, 8)
    assert(n == 17, "raio 8 da' grade de 17")
    assert(q == 2, "tres pontos com um repetido sao dois blocos, deu " .. q)
    assert(layers[9][9][9] == true and layers[9][9][10] == true, "os blocos nao entraram")

    -- Fora do raio nao entra: scan devolvendo lixo nao pode estourar a grade.
    local _, _, q2 = geo3d.grade({ { x = 99, y = 0, z = 0 }, { x = 0, y = 0, z = 0 } }, 8)
    assert(q2 == 1, "ponto fora do raio devia ser descartado")

    -- Faixa de altura: e' o filtro que responde "o que tem na altura em que estou cavando".
    local _, _, q3 = geo3d.grade({
        { x = 0, y = -5, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 5, z = 0 },
    }, 8, { -1, 1 })
    assert(q3 == 1, "so' o bloco dentro da faixa devia entrar, deu " .. q3)

    -- Cena: um grupo ligado desenha, um desligado so' entra na legenda.
    local grupos = {
        { nome = "minecraft:coal_ore", curto = "coal",
          pontos = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 } } },
        { nome = "minecraft:iron_ore", curto = "iron", pontos = { { x = 3, y = 0, z = 0 } } },
    }
    local cena = geo3d.cena(grupos, { raio = 8, ligados = { ["minecraft:coal_ore"] = true } })
    assert(#cena.objetos == 1, "so' o carvao devia virar objeto, deu " .. #cena.objetos)
    assert(#cena.legenda == 2, "a legenda mostra os dois, ligado ou nao")
    assert(cena.legenda[1].ligado == true and cena.legenda[2].ligado == false,
        "a legenda tem de dizer quem esta ligado")
    assert(cena.blocos == 2, "dois blocos de carvao desenhados")

    -- Nil e vazio nao explodem: varredura sem nada e' resposta valida.
    assert(#geo3d.cena(nil, {}).objetos == 0, "cena de nada devia sair vazia")
    assert(#geo3d.cena({}, {}).objetos == 0, "cena de lista vazia devia sair vazia")

    -- Teto: cena grande demais corta e AVISA, em vez de derrubar o quadro em silencio.
    local muitos = { pontos = {}, nome = "mod:pedra", curto = "pedra" }
    for i = 1, 50 do muitos.pontos[#muitos.pontos + 1] = { x = i % 17 - 8, y = 0, z = 0 } end
    local pequena = geo3d.cena({ muitos }, { raio = 8, teto = 5 })
    assert(pequena.cortou == true, "passar do teto tem de avisar")
    assert(#pequena.objetos == 0, "passou do teto: nao desenha")

    -- A turtle entra como objeto proprio, e fora do raio simplesmente nao aparece.
    local comT = geo3d.cena(grupos, { raio = 8, turtle = { x = 0, y = 0, z = 0 } })
    assert(#comT.objetos == 3, "dois minerios mais a turtle, deu " .. #comT.objetos)
    local semT = geo3d.cena(grupos, { raio = 8, turtle = { x = 99, y = 0, z = 0 } })
    assert(#semT.objetos == 2, "turtle fora do raio nao desenha")
    return true
end

return geo3d
