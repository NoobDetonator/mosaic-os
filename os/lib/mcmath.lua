-- Contas de Minecraft: formas em blocos, e a conversao para stack e recipiente.
--
--   local mc = mosaic.lib("mcmath")
--   local r = mc.build("circulo", { w = 15 })
--   r.total            -- quantos blocos
--   r.layers[1][z][x]  -- true onde tem bloco
--
-- O criterio do circulo e' o classico de construtor: o centro do bloco contra o raio,
-- `((x + 0.5) - r)^2 + ((z + 0.5) - r)^2 <= r^2`. E' o que acerta diametro par e impar e da'
-- o desenho que todo mundo reconhece (diametro 7 = 37 blocos).
local mcmath = {}

-- Teto de tamanho. Uma esfera 64x64x64 ja e' um quarto de milhao de celulas; acima disso a
-- geracao passaria dos 7 segundos que o CC aguenta sem yield.
mcmath.MAX_DIM = 64

mcmath.shapes = {
    { id = "retangulo", name = "Retangulo", dims = { "w", "d" } },
    { id = "caixa",     name = "Caixa",     dims = { "w", "h", "d" } },
    { id = "circulo",   name = "Circulo",   dims = { "w" } },
    { id = "elipse",    name = "Elipse",    dims = { "w", "d" } },
    { id = "cilindro",  name = "Cilindro",  dims = { "w", "h", "d" } },
    { id = "esfera",    name = "Esfera",    dims = { "w" } },
    { id = "elipsoide", name = "Elipsoide", dims = { "w", "h", "d" } },
    { id = "cupula",    name = "Cupula",    dims = { "w", "h" } },
    { id = "cone",      name = "Cone",      dims = { "w", "h" } },
    { id = "losango",   name = "Losango",   dims = { "w", "d" } },
    { id = "triangulo", name = "Triangulo", dims = { "w", "d" } },
}

function mcmath.shapeById(id)
    for _, s in ipairs(mcmath.shapes) do if s.id == id then return s end end
    return nil
end

local function clampDim(v, padrao)
    v = tonumber(v) or padrao
    v = math.floor(v)
    if v < 1 then v = 1 end
    if v > mcmath.MAX_DIM then v = mcmath.MAX_DIM end
    return v
end

-- ---------------------------------------------------------------- formas
-- Cada uma devolve uma funcao inside(x, y, z) com indices comecando em zero.

local function insideFor(kind, w, h, d)
    local rx, ry, rz = w / 2, h / 2, d / 2

    if kind == "retangulo" or kind == "caixa" then
        return function() return true end

    elseif kind == "circulo" or kind == "elipse" or kind == "cilindro" then
        -- Sem termo em y: a mesma secao repetida em todas as camadas.
        return function(x, _, z)
            local dx, dz = (x + 0.5 - rx) / rx, (z + 0.5 - rz) / rz
            return dx * dx + dz * dz <= 1
        end

    elseif kind == "esfera" or kind == "elipsoide" then
        return function(x, y, z)
            local dx = (x + 0.5 - rx) / rx
            local dy = (y + 0.5 - ry) / ry
            local dz = (z + 0.5 - rz) / rz
            return dx * dx + dy * dy + dz * dz <= 1
        end

    elseif kind == "cupula" then
        -- Meia esfera: o centro em y fica na base, entao a camada 0 e' a mais larga.
        return function(x, y, z)
            local dx = (x + 0.5 - rx) / rx
            local dy = (y + 0.5) / h
            local dz = (z + 0.5 - rz) / rz
            return dx * dx + dy * dy + dz * dz <= 1
        end

    elseif kind == "cone" then
        return function(x, y, z)
            local escala = 1 - (y + 0.5) / h      -- raio encolhe subindo
            if escala <= 0 then return false end
            local dx = (x + 0.5 - rx) / (rx * escala)
            local dz = (z + 0.5 - rz) / (rz * escala)
            return dx * dx + dz * dz <= 1
        end

    elseif kind == "losango" then
        return function(x, _, z)
            local dx, dz = math.abs(x + 0.5 - rx) / rx, math.abs(z + 0.5 - rz) / rz
            return dx + dz <= 1
        end

    elseif kind == "triangulo" then
        -- Isoceles visto de cima: uma ponta na frente, a base atras.
        return function(x, _, z)
            local frac = (z + 0.5) / d
            local meia = frac * rx
            return math.abs(x + 0.5 - rx) <= meia
        end
    end
    return nil
end

-- ---------------------------------------------------------------- casca

-- Tira o miolo, deixando `espessura` camadas de parede. Eixo de tamanho 1 nao conta como
-- vizinho: numa forma de uma camada so', o "de cima" e o "de baixo" seriam sempre vazios e a
-- forma inteira viraria casca.
local function hollowOut(grid, w, h, d, espessura)
    local atual = grid
    local casca = {}
    for y = 1, h do
        casca[y] = {}
        for z = 1, d do casca[y][z] = {} end
    end

    for _ = 1, espessura do
        local borda = {}
        for y = 1, h do
            for z = 1, d do
                for x = 1, w do
                    if atual[y][z][x] then
                        local fora = false
                        if w > 1 and (x == 1 or x == w or not atual[y][z][x - 1] or not atual[y][z][x + 1]) then fora = true end
                        if not fora and d > 1 and (z == 1 or z == d or not atual[y][z - 1][x] or not atual[y][z + 1][x]) then fora = true end
                        if not fora and h > 1 and (y == 1 or y == h or not atual[y - 1][z][x] or not atual[y + 1][z][x]) then fora = true end
                        if fora then
                            borda[#borda + 1] = { y, z, x }
                            casca[y][z][x] = true
                        end
                    end
                end
            end
        end
        if #borda == 0 then break end
        for _, c in ipairs(borda) do atual[c[1]][c[2]][c[3]] = false end
    end
    return casca
end

-- ---------------------------------------------------------------- geracao

-- params: { w, h, d, hollow, thickness }
-- Devolve { kind, w, h, d, layers, total, perLayer } ou nil, motivo.
function mcmath.build(kind, params)
    params = params or {}
    local shape = mcmath.shapeById(kind)
    if not shape then return nil, "nao conheco a forma '" .. tostring(kind) .. "'" end

    local w = clampDim(params.w, 7)
    local d = clampDim(params.d, w)
    local h = clampDim(params.h, 1)
    -- Formas de secao unica so' tem uma camada; as redondas em 3D usam o proprio diametro.
    if kind == "circulo" or kind == "elipse" or kind == "retangulo"
        or kind == "losango" or kind == "triangulo" then h = 1 end
    if kind == "circulo" or kind == "esfera" then d = w end
    if kind == "esfera" then h = w end

    local inside = insideFor(kind, w, h, d)
    if not inside then return nil, "forma sem regra: " .. kind end

    local grid = {}
    for y = 1, h do
        local layer = {}
        for z = 1, d do
            local row = {}
            for x = 1, w do row[x] = inside(x - 1, y - 1, z - 1) end
            layer[z] = row
        end
        grid[y] = layer
    end

    if params.hollow then
        local esp = math.max(1, math.floor(tonumber(params.thickness) or 1))
        grid = hollowOut(grid, w, h, d, esp)
    end

    local total, perLayer = 0, {}
    for y = 1, h do
        local n = 0
        for z = 1, d do
            for x = 1, w do if grid[y][z][x] then n = n + 1 end end
        end
        perLayer[y] = n
        total = total + n
    end

    return { kind = kind, w = w, h = h, d = d, layers = grid, total = total, perLayer = perLayer,
        hollow = params.hollow and true or false }
end

-- ---------------------------------------------------------------- stacks e recipientes

mcmath.STACK = 64

-- O plural vem escrito: "Bau duplo" + "s" daria "Bau duplos", e "Barril" + "s", "Barrils".
mcmath.containers = {
    { id = "chest",   name = "Bau",       plural = "baus",        slots = 27 },
    { id = "double",  name = "Bau duplo", plural = "baus duplos", slots = 54 },
    { id = "barrel",  name = "Barril",    plural = "barris",      slots = 27 },
    { id = "shulker", name = "Shulker",   plural = "shulkers",    slots = 27 },
    { id = "hopper",  name = "Funil",     plural = "funis",       slots = 5 },
}

function mcmath.containerById(id)
    for _, c in ipairs(mcmath.containers) do if c.id == id then return c end end
    return nil
end

-- Devolve stacks inteiros e o resto solto.
function mcmath.stacks(n, tamanho)
    tamanho = math.max(1, math.floor(tonumber(tamanho) or mcmath.STACK))
    n = math.max(0, math.floor(tonumber(n) or 0))
    return math.floor(n / tamanho), n % tamanho
end

-- Quantos recipientes cheios, mais o que sobra em stacks e itens soltos.
function mcmath.containersFor(n, tamanho, slots)
    tamanho = math.max(1, math.floor(tonumber(tamanho) or mcmath.STACK))
    slots = math.max(1, math.floor(tonumber(slots) or 27))
    n = math.max(0, math.floor(tonumber(n) or 0))
    local porRecipiente = tamanho * slots
    local cheios = math.floor(n / porRecipiente)
    local resto = n % porRecipiente
    local st, itens = mcmath.stacks(resto, tamanho)
    return { containers = cheios, stacks = st, items = itens, perContainer = porRecipiente }
end

-- Quantos itens cabem em `n` recipientes.
function mcmath.capacity(n, tamanho, slots)
    tamanho = math.max(1, math.floor(tonumber(tamanho) or mcmath.STACK))
    slots = math.max(1, math.floor(tonumber(slots) or 27))
    return math.max(0, math.floor(tonumber(n) or 0)) * tamanho * slots
end

-- Texto curto: "2 baus + 3 stacks + 12".
function mcmath.describe(n, tamanho, slots, nome, plural)
    local r = mcmath.containersFor(n, tamanho, slots)
    local partes = {}
    if r.containers > 0 then
        partes[#partes + 1] = r.containers .. " " ..
            (r.containers > 1 and (plural or ((nome or "bau") .. "s")) or (nome or "bau"))
    end
    if r.stacks > 0 then partes[#partes + 1] = r.stacks .. " stack" .. (r.stacks > 1 and "s" or "") end
    if r.items > 0 or #partes == 0 then partes[#partes + 1] = tostring(r.items) end
    return table.concat(partes, " + ")
end

-- ---------------------------------------------------------------- self-check

function mcmath.demo()
    local function conta(kind, p)
        local r = assert(mcmath.build(kind, p))
        return r
    end

    -- retangulo: a conta que da para fazer de cabeca
    local ret = conta("retangulo", { w = 5, d = 5 })
    assert(ret.total == 25, "retangulo 5x5 cheio deveria dar 25, deu " .. ret.total)
    local oco = conta("retangulo", { w = 5, d = 5, hollow = true })
    assert(oco.total == 16, "moldura 5x5 deveria dar 16, deu " .. oco.total)
    local oco2 = conta("retangulo", { w = 7, d = 7, hollow = true, thickness = 2 })
    assert(oco2.total == 49 - 9, "parede de 2 num 7x7 deveria deixar 40, deu " .. oco2.total)

    -- circulo: 37 para diametro 7 e' o numero conhecido do criterio classico
    assert(conta("circulo", { w = 1 }).total == 1, "circulo de 1 deveria ser 1 bloco")
    assert(conta("circulo", { w = 2 }).total == 4, "circulo de 2 deveria ser 4 blocos")
    local c7 = conta("circulo", { w = 7 })
    assert(c7.total == 37, "circulo de diametro 7 deveria dar 37, deu " .. c7.total)
    assert(c7.w == 7 and c7.d == 7 and c7.h == 1, "circulo saiu com dimensao errada")

    -- simetria nos quatro sentidos
    for z = 1, 7 do
        for x = 1, 7 do
            local v = c7.layers[1][z][x]
            assert(v == c7.layers[1][z][8 - x], "circulo assimetrico no eixo x")
            assert(v == c7.layers[1][8 - z][x], "circulo assimetrico no eixo z")
            assert(v == c7.layers[1][x][z], "circulo deveria ser igual espelhado na diagonal")
        end
    end

    -- casca sempre cabe dentro da forma cheia, e e' menor
    local c15 = conta("circulo", { w = 15 })
    local c15o = conta("circulo", { w = 15, hollow = true })
    assert(c15o.total < c15.total, "circulo oco deveria ter menos blocos que o cheio")
    assert(c15o.total > 0, "circulo oco nao pode ficar vazio")
    for z = 1, 15 do
        for x = 1, 15 do
            if c15o.layers[1][z][x] then
                assert(c15.layers[1][z][x], "a casca saiu fora da forma cheia")
            end
        end
    end

    -- esfera e cupula
    assert(conta("esfera", { w = 1 }).total == 1, "esfera de 1 deveria ser 1 bloco")
    local esf = conta("esfera", { w = 9 })
    assert(esf.w == 9 and esf.h == 9 and esf.d == 9, "esfera deveria ser cubica na caixa")
    assert(esf.perLayer[5] > esf.perLayer[1], "a camada do meio da esfera tem de ser a maior")
    local cup = conta("cupula", { w = 11, h = 6 })
    assert(cup.perLayer[1] > cup.perLayer[6], "a cupula tem de afinar para cima")
    local cone = conta("cone", { w = 11, h = 6 })
    assert(cone.perLayer[1] > cone.perLayer[6], "o cone tem de afinar para cima")

    -- o total bate com a soma das camadas
    local soma = 0
    for _, n in ipairs(esf.perLayer) do soma = soma + n end
    assert(soma == esf.total, "o total nao bate com a soma das camadas")

    -- teto de tamanho e forma desconhecida
    local grande = conta("retangulo", { w = 999, d = 1 })
    assert(grande.w == mcmath.MAX_DIM, "a dimensao deveria ter sido limitada")
    local nada, motivo = mcmath.build("piramide_invertida", {})
    assert(nada == nil and motivo, "forma desconhecida deveria ser recusada")

    -- stacks e recipientes
    local st, resto = mcmath.stacks(100, 64)
    assert(st == 1 and resto == 36, "100 itens dariam 1 stack e 36, deu " .. st .. " e " .. resto)
    assert(select(1, mcmath.stacks(64, 64)) == 1, "64 itens sao exatamente 1 stack")
    local r = mcmath.containersFor(1728, 64, 27)
    assert(r.containers == 1 and r.stacks == 0 and r.items == 0, "1728 itens sao 1 bau cheio")
    local r2 = mcmath.containersFor(1729, 64, 27)
    assert(r2.containers == 1 and r2.stacks == 0 and r2.items == 1, "1729 e 1 bau e 1 item")
    assert(mcmath.capacity(2, 64, 27) == 3456, "dois baus levam 3456 itens")
    assert(mcmath.capacity(1, 16, 27) == 432, "bau de item que empilha 16")
    assert(mcmath.describe(0, 64, 27, "bau") == "0", "zero deveria aparecer como 0")
    assert(mcmath.describe(1729, 64, 27, "bau", "baus"):find("1 bau"), "descricao errada: " ..
        mcmath.describe(1729, 64, 27, "bau", "baus"))
    assert(mcmath.describe(3458, 64, 27, "bau", "baus"):find("2 baus"), "plural errado")
    assert(mcmath.describe(6913, 64, 54, "bau duplo", "baus duplos"):find("2 baus duplos"),
        "o plural escrito e que vale, nao um s no fim")
    for _, c in ipairs(mcmath.containers) do
        assert(c.plural and c.slots > 0, "recipiente sem plural ou sem slots: " .. c.id)
    end

    return true
end

return mcmath
