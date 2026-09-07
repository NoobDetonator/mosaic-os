-- Geo Scanner de mentira, para conferir o painel de prospeccao sem o jogo.
--
-- No molde do fake-reactor: monta um periferico falso pelo fake-periph e devolve dados com a
-- MESMA forma que o de verdade devolveu no servidor - `chunkAnalyze` dando nome -> contagem,
-- e `scan` dando uma lista de { name, tags, x, y, z } relativos ao scanner.
--
-- Os nomes sao os que sairam do servidor, inclusive os que quebram classificacao ingenua
-- (`alltheores:ore_uranium` com o prefixo, `elementalcraft:crystalore` colado). E a curva de
-- custo tambem e' a medida la': gratis ate' 8, e cara depois.
local fake = dofile("/test/fake-periph.lua")
local M = {}

local CHUNK = {
    ["minecraft:stone"] = 12480, ["minecraft:dirt"] = 640, ["minecraft:gravel"] = 310,
    ["minecraft:coal_ore"] = 200, ["minecraft:iron_ore"] = 86,
    ["ars_nouveau:vinteum_ore"] = 83, ["mekanism:fluorite_ore"] = 47,
    ["elementalcraft:crystalore"] = 40, ["alltheores:ore_copper"] = 34,
    ["alltheores:ore_lead"] = 31, ["alltheores:ore_zinc"] = 30,
    ["alltheores:ore_osmium"] = 27, ["alltheores:ore_silver"] = 25,
    ["alltheores:ore_uranium"] = 14, ["minecraft:diamond_ore"] = 6,
    ["forbidden_arcanus:runestone"] = 1,
}

-- Veias com forma, e nao pontos soltos: e' o que exercita a juncao de faces do `mesh.voxels`
-- (blocos vizinhos do mesmo tipo viram uma casca so'). Ponto solto nao provaria nada disso.
local VEIAS = {
    { nome = "minecraft:coal_ore", tag = "forge:ores/coal",
      base = { -5, -2, 3 }, forma = { {0,0,0},{1,0,0},{2,0,0},{1,1,0},{1,0,1},{2,0,1} } },
    { nome = "minecraft:iron_ore", tag = "forge:ores/iron",
      base = { 2, 1, -4 }, forma = { {0,0,0},{0,1,0},{0,0,1},{1,0,1} } },
    { nome = "minecraft:diamond_ore", tag = "forge:ores/diamond",
      base = { 0, -6, 0 }, forma = { {0,0,0},{1,0,0} } },
    { nome = "alltheores:ore_uranium", tag = "forge:ores/uranium",
      base = { -3, 4, -3 }, forma = { {0,0,0},{0,0,1},{0,1,1} } },
    { nome = "elementalcraft:crystalore", tag = "forge:ores/crystal",
      base = { 5, 2, 5 }, forma = { {0,0,0} } },
}

function M.instalar()
    local scanner = {}

    function scanner.chunkAnalyze()
        local copia = {}
        for k, v in pairs(CHUNK) do copia[k] = v end
        return copia
    end

    -- A curva medida no servidor: gratis ate' 8, e depois cara. E' o que faz o app achar o
    -- limite gratuito sozinho em vez de oferecer um raio que falharia.
    function scanner.cost(raio)
        if (raio or 0) <= 8 then return 0 end
        return math.floor(((raio - 8) ^ 2.4) * 330)
    end

    function scanner.getFuelLevel() return 0 end
    function scanner.getMaxFuelLevel() return 0 end
    function scanner.getName() return "geoScanner_0" end

    function scanner.scan(raio)
        if scanner.cost(raio) > 0 then return nil, "Not enough energy" end
        local out = {}
        -- Pedra em volta, com buracos: o painel tem de aguentar milhares de blocos e ainda
        -- deixar o filtro contar so' o que interessa.
        for x = -raio, raio do
            for y = -raio, raio do
                for z = -raio, raio do
                    if (x + y + z) % 3 ~= 0 then
                        out[#out + 1] = { name = "minecraft:stone", tags = {}, x = x, y = y, z = z }
                    end
                end
            end
        end
        for _, v in ipairs(VEIAS) do
            for _, d in ipairs(v.forma) do
                local x, y, z = v.base[1] + d[1], v.base[2] + d[2], v.base[3] + d[3]
                if math.abs(x) <= raio and math.abs(y) <= raio and math.abs(z) <= raio then
                    out[#out + 1] = { name = v.nome, tags = { v.tag }, x = x, y = y, z = z }
                end
            end
        end
        return out
    end

    fake.add("geoScanner_0", { "geoScanner" }, scanner)
    fake.instalar()
    return scanner
end

-- Uma turtle de mentira na frota, para o 3D ter onde poe-la. Precisa da ancora, senao o app
-- (com razao) recusa situar a turtle.
function M.comTurtle(api)
    settings.set("mosaic.geo.anchor", "100 64 -50")
    api.clusterNodes = function()
        return { { id = 7, name = "mineradora", kind = "turtle", group = "mina",
                   version = "0.2.0", online = true, visto = os.epoch("utc"),
                   desde = os.epoch("utc"), fuel = 18450,
                   pos = { x = 103, y = 62, z = -52, olhando = "leste", certa = true } } }, "mestre"
    end
end

return M
