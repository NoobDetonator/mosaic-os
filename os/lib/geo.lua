-- Geo Scanner do Advanced Peripherals: o que ha no chunk, e onde estao as veias por perto.
--
--   local geo = mosaic.lib("geo")
--   local lista = geo.analise()          -- o chunk inteiro, por tipo de bloco
--   local achados = geo.varre(8)         -- blocos num raio, agrupados e com posicao
--
-- Medido no servidor (AP 0.7 / MC 1.16.5): `scan(4)` devolveu 261 blocos em 32 ms, e
-- `chunkAnalyze()` 46 tipos de bloco.
--
-- ENERGIA: ha um raio de graca e, depois dele, custo que cresce rapido. Medido:
-- raio 1 a 8 custa 0; raio 9 custa 330; 12 custa 1821; 16 custa 5274. E o scanner de la' tem
-- capacidade ZERO, ou seja, tudo acima de 8 e' impossivel enquanto ele nao for ligado na
-- energia. Eu quase concluí que o consumo estava desligado porque `cost(8)` deu 0 - era so'
-- o raio estar dentro da faixa gratuita.
--
-- Por isso `limiteGratis()` existe: o app pergunta ao scanner ate' onde da' para ir sem
-- energia, em vez de oferecer um raio que vai falhar.
--
-- O scanner mede em volta de SI MESMO, nao de quem pergunta. Ligado por cabo, ele e' uma
-- estacao parada: as coordenadas saem relativas ao bloco dele. Para uma turtle que anda,
-- seria preciso o scanner como upgrade dela.
local geo = {}

function geo.find()
    local hal = require("lib.hal")
    return hal.find("geoScanner")
end

function geo.temScanner() return geo.find() ~= nil end

-- ---------------------------------------------------------------- nomes
--
-- Classificar minerio pelo nome e' chute; pela TAG e' certeza. O `scan` devolve as tags de
-- cada bloco, entao ali da' para acertar. O `chunkAnalyze` so' devolve nome e contagem, e ai
-- so' resta o padrao do nome - por isso os dois caminhos existem.
local NAO_MINERIO = { core = true, score = true, shore = true, encore = true, hardcore = true }

function geo.ehMinerio(nome, tags)
    if type(tags) == "table" then
        for _, t in ipairs(tags) do
            if type(t) == "string" and t:sub(1, 10) == "forge:ores" then return true end
        end
    end
    local corpo = tostring(nome):match("[^:]+$") or tostring(nome)
    if corpo:find("^ore_") or corpo:find("_ore$") or corpo:find("_ore_") or corpo:find("_ores$") then
        return true
    end
    -- "crystalore" e "quartzore" existem; "core" e "score" nao sao minerio.
    local fim = corpo:match("(%a+)$")
    if fim and #fim > 3 and fim:sub(-3) == "ore" and not NAO_MINERIO[fim] then return true end
    return false
end

-- Nome curto para caber na tela. Tira o mod da frente e o "ore" que so' repete a coluna.
function geo.nomeCurto(nome)
    local corpo = tostring(nome):match("[^:]+$") or tostring(nome)
    if geo.ehMinerio(nome) then
        corpo = corpo:gsub("^ore_", ""):gsub("_ores?$", "")
    end
    return (corpo:gsub("_", " "))
end

-- ---------------------------------------------------------------- o chunk

-- Ordena por quantidade, e minerio antes de pedra: a lista existe para responder "vale a
-- pena cavar aqui?", e cascalho no topo nao responde isso.
local function ordena(lista)
    table.sort(lista, function(a, b)
        if a.minerio ~= b.minerio then return a.minerio end
        if a.n ~= b.n then return a.n > b.n end
        return a.nome < b.nome
    end)
    return lista
end

function geo.organiza(contagem)
    local lista = {}
    for nome, n in pairs(contagem or {}) do
        if type(n) == "number" then
            lista[#lista + 1] = { nome = nome, curto = geo.nomeCurto(nome),
                n = n, minerio = geo.ehMinerio(nome) }
        end
    end
    return ordena(lista)
end

function geo.analise()
    local g = geo.find()
    if not g then return nil, "nenhum Geo Scanner na rede" end
    local ok, dados = pcall(g.chunkAnalyze)
    if not ok then return nil, tostring(dados) end
    if type(dados) ~= "table" then return nil, "o scanner nao respondeu a analise" end
    return geo.organiza(dados)
end

-- ---------------------------------------------------------------- energia

function geo.custo(raio)
    local g = geo.find()
    if not g or not g.cost then return nil end
    local ok, c = pcall(g.cost, raio)
    return ok and tonumber(c) or nil
end

-- O maior raio que ainda sai de graca. `custoFn` existe para o self-check exercitar a busca
-- sem hardware nenhum.
--
-- Anda de baixo para cima e PARA no primeiro que custa: o custo cresce com o raio, entao o
-- primeiro pago marca o fim da faixa gratuita.
function geo.limiteGratis(custoFn, maximo)
    custoFn = custoFn or geo.custo
    local limite = 0
    for r = 1, maximo or 16 do
        local c = custoFn(r)
        if c == nil then return limite > 0 and limite or nil end
        if c > 0 then return limite end
        limite = r
    end
    return limite
end

-- ---------------------------------------------------------------- o raio

-- Agrupa o `scan` por tipo, guardando as posicoes. E' o formato que o desenho precisa: uma
-- cor por minerio, e os pontos daquela cor.
function geo.agrupa(blocos)
    local por, ordem = {}, {}
    for _, b in ipairs(blocos or {}) do
        if type(b) == "table" and type(b.name) == "string" then
            local g = por[b.name]
            if not g then
                g = { nome = b.name, curto = geo.nomeCurto(b.name),
                      minerio = geo.ehMinerio(b.name, b.tags), n = 0, pontos = {} }
                por[b.name] = g
                ordem[#ordem + 1] = g
            end
            g.n = g.n + 1
            g.pontos[#g.pontos + 1] = { x = b.x, y = b.y, z = b.z }
        end
    end
    return ordena(ordem)
end

function geo.varre(raio)
    local g = geo.find()
    if not g then return nil, "nenhum Geo Scanner na rede" end
    local okC, custo = pcall(g.cost, raio)
    if okC and type(custo) == "number" and custo > 0 then
        local okF, tem = pcall(g.getFuelLevel)
        if okF and type(tem) == "number" and tem < custo then
            return nil, string.format("falta energia: precisa de %d e tem %d", custo, tem)
        end
    end
    local ok, blocos = pcall(g.scan, raio)
    if not ok then return nil, tostring(blocos) end
    if type(blocos) ~= "table" then return nil, "o scanner recusou o scan (raio grande demais?)" end
    return geo.agrupa(blocos), #blocos
end

-- ---------------------------------------------------------------- self-check

function geo.demo()
    -- Classificacao por TAG ganha do nome, sempre: e' a unica que nao e' chute.
    assert(geo.ehMinerio("qualquer:coisa", { "forge:ores/iron" }), "tag forge:ores devia bastar")
    assert(geo.ehMinerio("mod:pedra_comum", { "forge:ores" }), "tag sozinha tambem vale")

    -- Nomes reais, colhidos do servidor com chunkAnalyze.
    assert(geo.ehMinerio("minecraft:coal_ore"), "coal_ore e' minerio")
    assert(geo.ehMinerio("mekanism:fluorite_ore"), "fluorite_ore e' minerio")
    assert(geo.ehMinerio("alltheores:ore_uranium"), "ore_uranium e' minerio")
    assert(geo.ehMinerio("elementalcraft:crystalore"), "crystalore e' minerio")
    assert(not geo.ehMinerio("forbidden_arcanus:runestone"), "runestone NAO e' minerio")
    assert(not geo.ehMinerio("minecraft:stone"), "pedra nao e' minerio")
    -- Falsos amigos: tudo que termina em "ore" sem ser minerio.
    assert(not geo.ehMinerio("botania:mana_core"), "core nao e' minerio")
    assert(not geo.ehMinerio("mod:score"), "score nao e' minerio")

    -- Nome curto: cabe na tela e nao repete "ore" em toda linha.
    assert(geo.nomeCurto("minecraft:coal_ore") == "coal", "coal_ore devia virar 'coal'")
    assert(geo.nomeCurto("alltheores:ore_uranium") == "uranium", "ore_uranium devia virar 'uranium'")
    assert(geo.nomeCurto("minecraft:oak_slab") == "oak slab", "nao-minerio so' perde o mod")

    -- Ordem: minerio primeiro, depois por quantidade. E' o que responde "vale cavar aqui?".
    local lista = geo.organiza({
        ["minecraft:stone"] = 5000,
        ["minecraft:coal_ore"] = 200,
        ["alltheores:ore_uranium"] = 14,
        ["minecraft:dirt"] = 900,
    })
    assert(lista[1].nome == "minecraft:coal_ore", "carvao devia vir na frente da pedra")
    assert(lista[2].nome == "alltheores:ore_uranium", "urânio e' o segundo minerio")
    assert(lista[3].nome == "minecraft:stone", "pedra so' depois dos minerios, e pela contagem")
    assert(lista[4].nome == "minecraft:dirt", "terra por ultimo")

    -- Agrupar o scan: um grupo por tipo, com as posicoes juntas.
    local g = geo.agrupa({
        { name = "minecraft:coal_ore", x = 1, y = 2, z = 3, tags = { "forge:ores/coal" } },
        { name = "minecraft:coal_ore", x = 1, y = 3, z = 3, tags = { "forge:ores/coal" } },
        { name = "minecraft:stone", x = 0, y = 0, z = 0, tags = {} },
    })
    assert(#g == 2, "deviam sair dois grupos, saiu " .. #g)
    assert(g[1].nome == "minecraft:coal_ore" and g[1].n == 2, "o carvao devia agrupar dois")
    assert(#g[1].pontos == 2 and g[1].pontos[2].y == 3, "as posicoes nao foram guardadas")
    assert(g[1].minerio == true and g[2].minerio == false, "classificacao errada no grupo")

    -- Lista vazia nao pode explodir: chunk sem nada e' resposta valida.
    assert(#geo.organiza({}) == 0, "contagem vazia devia dar lista vazia")
    assert(#geo.agrupa({}) == 0, "scan vazio devia dar lista vazia")
    assert(#geo.agrupa(nil) == 0, "scan nil devia dar lista vazia")

    -- O limite gratuito: a busca para no primeiro raio que custa. Com a curva medida no
    -- servidor (gratis ate' 8, 330 no 9), o limite tem de ser 8.
    local medido = { [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0, [7]=0, [8]=0,
                     [9]=330, [10]=739, [11]=1200, [12]=1821, [13]=2500, [14]=3300,
                     [15]=4200, [16]=5274 }
    assert(geo.limiteGratis(function(r) return medido[r] end) == 8,
        "com a curva do servidor o limite gratuito e' 8")
    -- Tudo pago: nao ha raio de graca, e isso e' zero e nao erro.
    assert(geo.limiteGratis(function() return 100 end) == 0, "tudo pago devia dar 0")
    -- Tudo de graca: o limite e' o teto da busca.
    assert(geo.limiteGratis(function() return 0 end, 16) == 16, "tudo gratis devia dar o teto")
    -- Sem scanner o custo e' nil, e ai nao da' para afirmar limite nenhum.
    assert(geo.limiteGratis(function() return nil end) == nil, "sem custo nao ha limite conhecido")

    -- Sem scanner, as duas portas dizem o motivo em vez de levantar erro.
    if not geo.temScanner() then
        assert(select(2, geo.analise()):find("Geo Scanner"), "sem scanner, analise devia explicar")
        assert(select(2, geo.varre(4)):find("Geo Scanner"), "sem scanner, varre devia explicar")
    end
    return true
end

return geo
