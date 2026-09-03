-- Iluminacao por face: Lambert simples, com o resultado caindo num degrau de uma rampa de cor.
--
--   local shade = mosaic.lib("shade")
--   shade.normals(m)                          -- uma vez, depois de montar a malha
--   shade.apply(m, 0.4, 1, -0.3, shade.ramps.cinza)
--
-- Por que por face e nao por vertice: com 16 cores nao existe degrade. Interpolar tom entre
-- vertices so' aumentaria o numero de celulas com tres cores, e a celula de sub-pixel aceita
-- duas — o resultado seria pior, nao melhor.
local shade = {}

-- Luminancia aproximada de cada cor com a paleta do Mosaic aplicada. Serve para conferir que
-- uma rampa esta em ordem do escuro para o claro; e' o que o self-check usa.
shade.lum = {
    [colors.black] = 0, [colors.gray] = 128, [colors.lightGray] = 192, [colors.white] = 255,
    [colors.blue] = 15, [colors.cyan] = 92, [colors.lightBlue] = 111,
    [colors.brown] = 105, [colors.red] = 112, [colors.orange] = 172, [colors.yellow] = 207,
    [colors.purple] = 124, [colors.magenta] = 163, [colors.pink] = 194,
    [colors.green] = 140, [colors.lime] = 168,
}

-- ATENCAO ao primeiro degrau. A rampa de cinza comeca no PRETO, e o fundo do canvas 3D
-- costuma ser preto: face que cair nesse degrau some no fundo e o modelo perde as faces de
-- costas. Foi assim que o cubo do demo virou um losango achatado — so' o topo sobrava.
-- Use `ambiente` alto o bastante para o primeiro degrau nunca ser alcancado (0,3 ja resolve
-- numa rampa de quatro), ou um fundo que nao seja preto.
--
-- Rampas, do escuro para o claro.
--
-- A de cinza e' a unica com quatro degraus de verdade. Vale saber que a paleta do Win95
-- PIOROU ela para sombreamento: os degraus sao 128, 64 e 63, enquanto o CC de fabrica da
-- 59, 77 e 87. O salto preto -> cinza e' o dobro dos outros, entao a sombra fecha em faixa.
shade.ramps = {
    cinza   = { colors.black, colors.gray, colors.lightGray, colors.white },
    quente  = { colors.brown, colors.red, colors.orange, colors.yellow },
    lavanda = { colors.purple, colors.magenta, colors.pink },
    frio    = { colors.blue, colors.cyan, colors.lightBlue, colors.white },
    terra   = { colors.green, colors.lime, colors.lightGray, colors.white },

    -- Oito degraus, e SO' faz sentido com o mapa `render3d` do kernel/palette aplicado: sem
    -- ele, marrom, roxo, magenta e rosa sao cores de verdade e a rampa vira arco-iris.
    cinza8  = { colors.black, colors.brown, colors.purple, colors.gray,
                colors.magenta, colors.lightGray, colors.pink, colors.white },
}

-- Normal de uma face, apontando para FORA.
--
-- A ordem dos cantos usada por todos os geradores deixa o produto vetorial de mao direita
-- apontando para DENTRO (conferido face a face no cubo e no voxel), entao o sinal e' trocado.
function shade.faceNormal(x1, y1, z1, x2, y2, z2, x3, y3, z3)
    local ux, uy, uz = x2 - x1, y2 - y1, z2 - z1
    local vx, vy, vz = x3 - x1, y3 - y1, z3 - z1
    local nx = -(uy * vz - uz * vy)
    local ny = -(uz * vx - ux * vz)
    local nz = -(ux * vy - uy * vx)
    local m = math.sqrt(nx * nx + ny * ny + nz * nz)
    if m == 0 then return 0, 1, 0 end
    return nx / m, ny / m, nz / m
end

-- Guarda a normal de cada triangulo em tri[11..13]. Uma vez por malha, nao por quadro:
-- recalcular o produto vetorial de 3.768 triangulos a cada quadro custaria mais que o desenho.
function shade.normals(model)
    for _, t in ipairs(model.tris) do
        t[11], t[12], t[13] = shade.faceNormal(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9])
    end
    model.temNormais = true
    return model
end

-- Pinta a malha pela luz. (dx, dy, dz) e' a direcao DE ONDE a luz vem.
-- `ambiente` (0 a 1) e' o quanto a face totalmente na sombra ainda recebe; sem ele, metade do
-- modelo vira uma silhueta preta e some do fundo.
function shade.apply(model, dx, dy, dz, ramp, ambiente)
    ramp = ramp or shade.ramps.cinza
    ambiente = ambiente or 0.25
    if not model.temNormais then shade.normals(model) end

    local m = math.sqrt(dx * dx + dy * dy + dz * dz)
    if m == 0 then dx, dy, dz, m = 0, 1, 0, 1 end
    dx, dy, dz = dx / m, dy / m, dz / m

    local n = #ramp
    for _, t in ipairs(model.tris) do
        local d = t[11] * dx + t[12] * dy + t[13] * dz
        if d < 0 then d = 0 end
        local f = ambiente + (1 - ambiente) * d
        local i = math.floor(f * n) + 1
        if i < 1 then i = 1 elseif i > n then i = n end
        t.c = ramp[i]
    end
    return model
end

-- Mesma ideia, mas guardando a cor base de cada triangulo e escurecendo a partir dela.
-- Serve para malha que ja tem cor propria (terreno colorido por altura, modelo importado).
--
-- Os tres niveis sao medidos DEPOIS de tirar o ambiente, entao a face mais escura possivel cai
-- no cinza e nunca no preto: sobre fundo preto ela sumiria.
function shade.applyTinted(model, dx, dy, dz, ambiente)
    ambiente = ambiente or 0.35
    if not model.temNormais then shade.normals(model) end
    if not model.corBase then
        local base = {}
        for i, t in ipairs(model.tris) do base[i] = t.c end
        model.corBase = base
    end

    local m = math.sqrt(dx * dx + dy * dy + dz * dz)
    if m == 0 then dx, dy, dz, m = 0, 1, 0, 1 end
    dx, dy, dz = dx / m, dy / m, dz / m

    for i, t in ipairs(model.tris) do
        local d = t[11] * dx + t[12] * dy + t[13] * dz
        if d < 0 then d = 0 end
        local f = ambiente + (1 - ambiente) * d
        local base = model.corBase[i]
        -- Nao da' para escurecer uma cor arbitraria com 16 tons fixos, entao a queda vai para
        -- o cinza. `g` e' a luz ja sem o ambiente, de 0 a 1, para o corte nao depender dele.
        local g = (f - ambiente) / (1 - ambiente)
        if g > 0.55 then t.c = base
        elseif g > 0.25 then t.c = colors.lightGray
        else t.c = colors.gray end
    end
    return model
end

function shade.demo()
    local mesh = require("lib.mesh")

    -- A rampa de oito degraus so' esta em ordem com a paleta render3d aplicada, entao ela
    -- e' conferida contra as luminancias DAQUELE mapa, e nao contra as de fabrica.
    local lum8 = { [colors.black] = 0, [colors.brown] = 48, [colors.purple] = 90,
        [colors.gray] = 128, [colors.magenta] = 160, [colors.lightGray] = 192,
        [colors.pink] = 224, [colors.white] = 255 }
    assert(#shade.ramps.cinza8 == 8, "a rampa de oito precisa de oito degraus")
    for i = 2, 8 do
        assert(lum8[shade.ramps.cinza8[i]] > lum8[shade.ramps.cinza8[i - 1]],
            "a rampa de oito esta fora de ordem no degrau " .. i)
    end

    -- As demais rampas estao em ordem do escuro para o claro, pela paleta normal.
    for nome, ramp in pairs(shade.ramps) do
        if nome ~= "cinza8" then
        assert(#ramp >= 3, "rampa " .. nome .. " precisa de ao menos tres degraus")
        for i = 2, #ramp do
            local a, b = shade.lum[ramp[i - 1]], shade.lum[ramp[i]]
            assert(a and b, "rampa " .. nome .. " tem cor sem luminancia na tabela")
            assert(b > a, "rampa " .. nome .. " fora de ordem no degrau " .. i)
        end
        end
    end

    -- Normal do topo do cubo aponta para cima, a da base para baixo.
    local c = mesh.cube()
    shade.normals(c)
    local achouTopo, achouBase = false, false
    for _, t in ipairs(c.tris) do
        assert(t[11] and t[12] and t[13], "faltou normal num triangulo")
        local n = math.sqrt(t[11] ^ 2 + t[12] ^ 2 + t[13] ^ 2)
        assert(math.abs(n - 1) < 1e-9, "normal nao esta normalizada: " .. n)
        if t[12] > 0.99 then achouTopo = true end
        if t[12] < -0.99 then achouBase = true end
    end
    assert(achouTopo, "nenhuma face do cubo aponta para cima")
    assert(achouBase, "nenhuma face do cubo aponta para baixo")

    -- As seis faces cobrem as seis direcoes, cada uma com duas dos doze triangulos.
    local dirs = {}
    for _, t in ipairs(c.tris) do
        local k = string.format("%.0f,%.0f,%.0f", t[11], t[12], t[13])
        dirs[k] = (dirs[k] or 0) + 1
    end
    local quantas = 0
    for _, n in pairs(dirs) do
        assert(n == 2, "cada face devia dar dois triangulos com a mesma normal, deu " .. n)
        quantas = quantas + 1
    end
    assert(quantas == 6, "o cubo devia ter seis normais diferentes, teve " .. quantas)

    -- Luz vindo de cima: o topo pega o degrau mais claro, a base o mais escuro.
    shade.apply(c, 0, 1, 0, shade.ramps.cinza, 0)
    local topo, base
    for _, t in ipairs(c.tris) do
        if t[12] > 0.99 then topo = t.c end
        if t[12] < -0.99 then base = t.c end
    end
    assert(topo == colors.white, "o topo iluminado de cima devia ficar branco")
    assert(base == colors.black, "a base devia ficar no degrau mais escuro")

    -- Com ambiente, nada fica no degrau totalmente escuro.
    shade.apply(c, 0, 1, 0, shade.ramps.cinza, 0.5)
    for _, t in ipairs(c.tris) do
        assert(t.c ~= colors.black, "com ambiente 0,5 nenhuma face devia zerar")
    end

    -- Virar a luz vira o resultado.
    shade.apply(c, 0, -1, 0, shade.ramps.cinza, 0)
    for _, t in ipairs(c.tris) do
        if t[12] < -0.99 then assert(t.c == colors.white, "com a luz de baixo, a base clareia") end
    end

    -- Com ambiente suficiente, nada cai no primeiro degrau. E' o que impede a face de sumir
    -- num fundo preto, e foi um bug de verdade antes de virar teste.
    shade.apply(c, 0, 1, 0, shade.ramps.cinza, 0.3)
    for _, t in ipairs(c.tris) do
        assert(t.c ~= shade.ramps.cinza[1],
            "com ambiente 0,3 nenhuma face devia cair no degrau mais escuro")
    end

    -- E o applyTinted nunca usa preto, por construcao.
    local escuro = mesh.cube():mapColor(colors.lime)
    shade.applyTinted(escuro, 0, 1, 0, 0)
    for _, t in ipairs(escuro.tris) do
        assert(t.c ~= colors.black, "applyTinted nao pode devolver preto")
    end

    -- applyTinted preserva a cor propria na luz.
    local v = mesh.cube():mapColor(colors.lime)
    shade.applyTinted(v, 0, 1, 0, 0)
    local viuLime = false
    for _, t in ipairs(v.tris) do if t.c == colors.lime then viuLime = true end end
    assert(viuLime, "a face na luz devia manter a cor propria")
    -- E a cor base fica guardada, entao reaplicar nao acumula.
    shade.applyTinted(v, 0, 1, 0, 0)
    local viuLime2 = false
    for _, t in ipairs(v.tris) do if t.c == colors.lime then viuLime2 = true end end
    assert(viuLime2, "reaplicar a luz nao pode perder a cor base")

    return true
end

return shade
