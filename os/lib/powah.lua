-- Adaptador do reator do Powah (Minecraft 1.16.5).
--
-- O que o reator publica para o CC depende da face encostada. Medido no servidor:
-- um `powah:reactor_part` expoe `inventory` + `fluid_storage` e NADA de energia --
-- getEnergy() nao existe ali. Entao energia, temperatura e FE/t vem de fora:
-- Block Reader (NBT do bloco), Energy Detector (linha de saida) ou uma celula Powah.
--
-- Por isso tudo aqui e opcional: read() devolve o que existe e nil no resto, e a
-- interface mostra so o que da para mostrar. Vai acendendo conforme o hardware aparece.

local hal = require("lib.hal")

local powah = {}

-- Identificacao por NOME DE ITEM, nao por indice de slot: o numero do slot muda
-- entre versoes do mod, o id do item nao.
powah.FUEL = "powah:uraninite"
powah.SOLID_COOLANT = "powah:dry_ice"

-- De quantos em quantos ciclos reler o NBT do bloco. Ele custa um tick e so
-- entrega `built`, que praticamente nunca muda.
powah.NBT_CADA = 10

-- Acha o reator: primeiro pelo tipo do Powah, senao qualquer periferico que se
-- comporte como reator (tem inventario E tanque).
function powah.findReactor()
    local p, name = peripheral.find("powah:reactor_part")
    if p then return p, name end
    for _, n in ipairs(peripheral.getNames()) do
        local w = peripheral.wrap(n)
        if w and w.list and w.tanks then return w, n end
    end
    return nil
end

-- Mapa do hardware presente. A interface usa isto para saber o que desenhar.
function powah.discover()
    local reactor, rname = powah.findReactor()
    return {
        reactor = reactor, reactorName = rname,
        blockReader = hal.find("blockReader"),
        energyDetector = hal.find("energyDetector"),
        chatBox = hal.find("chatBox"),
        monitor = hal.find("monitor"),
    }
end

-- Le uma leitura completa. Campos ausentes ficam nil de proposito: quem desenha
-- decide o que fazer com a falta, em vez de receber zero e mostrar grafico mentiroso.
function powah.read(hw)
    hw = hw or powah.discover()
    local r = { at = os.clock(), slots = {}, extras = {} }
    if not hw.reactor then r.error = "reator nao encontrado" return r end

    local ok, list = pcall(hw.reactor.list)
    if not ok then r.error = "reator nao respondeu: " .. tostring(list) return r end
    for slot, item in pairs(list or {}) do
        r.slots[slot] = item
        if item.name == powah.FUEL then
            r.fuel = { slot = slot, count = item.count }
        elseif item.name == powah.SOLID_COOLANT then
            r.coolant = { slot = slot, count = item.count }
        else
            r.extras[#r.extras + 1] = { slot = slot, name = item.name, count = item.count }
        end
    end
    r.fuel = r.fuel or { count = 0 }
    r.coolant = r.coolant or { count = 0 }

    local okT, tanks = pcall(hw.reactor.tanks)
    if okT and tanks and tanks[1] then
        -- tanks() do CC nao traz capacidade neste bloco; quem chama acompanha o
        -- maior valor ja visto para ter uma escala.
        r.tank = { name = tanks[1].name, amount = tanks[1].amount or 0 }
    end

    -- Energia: o buffer sai do proprio reator, mas SO quando ele vem pela rede com
    -- fio -- a face encostada direto no computador nao publica energy_storage.
    -- A vazao (FE/t) nao existe na API do Forge: so com Energy Detector na linha.
    --
    -- Cada chamada de periferico pela rede custa 1 tick (medido: 0.05 s cada).
    -- A capacidade nao muda, entao e lida uma vez so: um tick a menos por ciclo.
    local e = {}
    if hw.reactor.getEnergy then
        hw._cap = hw._cap or hw.reactor.getEnergyCapacity() or 0
        local stored = hw.reactor.getEnergy() or 0
        e.stored, e.capacity = stored, hw._cap
        e.percent = hw._cap > 0 and (stored / hw._cap * 100) or 0
    end
    if hw.energyDetector then
        local okR, rate = pcall(hw.energyDetector.getTransferRate)
        if okR then e.rate = rate end
        local okL, lim = pcall(hw.energyDetector.getTransferRateLimit)
        if okL then e.limit = lim end
    end
    if (e.capacity or 0) > 0 or e.rate then r.energy = e end

    -- Temperatura so existe no NBT, e so no NUCLEO do reator. Medido no servidor:
    -- uma PECA (powah:reactor_part) so carrega built/variant/redstone_mode/extractor
    -- e um core_pos apontando para o nucleo. Entao, se o leitor caiu numa peca, da
    -- para dizer exatamente para onde mover em vez de so ficar sem temperatura.
    -- getBlockData tambem custa 1 tick e so entrega `built`, que praticamente nunca
    -- muda: le a cada NBT_CADA ciclos em vez de a cada amostra.
    if hw.blockReader then
        hw._nbtN = (hw._nbtN or powah.NBT_CADA) + 1
        if hw._nbtN >= powah.NBT_CADA then
            hw._nbtN = 0
            local okB, data = pcall(hw.blockReader.getBlockData)
            hw._nbt = (okB and type(data) == "table") and data or false
            if hw.blockReader.getBlockName then
                local okN, nome = pcall(hw.blockReader.getBlockName)
                hw._blockName = okN and nome or nil
            end
        end
        local data = hw._nbt
        if data then
            r.nbt = data
            r.blockName = hw._blockName
            -- built = 0 significa multiblock desmontado: vale um alerta, ao contrario
            -- da temperatura, que so existe no nucleo e o nucleo e' inalcancavel.
            if data.built ~= nil then r.built = data.built == 1 end
            local c = data.core_pos
            if c and (c.X or c.x) then
                local cx, cy, cz = c.X or c.x, c.Y or c.y, c.Z or c.z
                -- Se o leitor ja esta no nucleo, core_pos aponta para ele mesmo.
                if cx ~= data.x or cy ~= data.y or cz ~= data.z then
                    r.coreHint = { x = cx, y = cy, z = cz }
                end
            end
        end
    end
    return r
end

-- Nome legivel dos itens que o reator come. Nao e' lista de permissao: item fora
-- daqui aparece pelo id mesmo. Serve so' para a tela nao dizer "minecraft:coal_block".
-- Curtos de proposito: a coluna de rotulo de uma barra tem 11 caracteres, e
-- "Bloco de carvao" saia como "Bloc...rvao", que nao diz nada. Dentro de um reator
-- nao ha carvao que nao seja em bloco, entao "Carvao" basta.
powah.NOMES = {
    ["powah:uraninite"] = "Uraninita",
    ["powah:dry_ice"] = "Gelo seco",
    ["minecraft:coal_block"] = "Carvao",
    ["minecraft:redstone_block"] = "Redstone",
    ["minecraft:blaze_rod"] = "Blaze",
    ["minecraft:ice"] = "Gelo",
    ["minecraft:packed_ice"] = "Gelo comp.",
    ["minecraft:blue_ice"] = "Gelo azul",
    ["minecraft:snow_block"] = "Neve",
}

-- Cor de cada item nas barras e nos graficos. A mesma cor em todo lugar: barra,
-- grafico e legenda. Item desconhecido cai no amarelo.
powah.CORES = {
    ["powah:uraninite"] = colors.lime,
    ["powah:dry_ice"] = colors.lightBlue,
    -- Marrom e nao cinza: cinza e' a cor do vazio da barra, e carvao cinza numa barra
    -- de fundo cinza fica invisivel. Visto no print antes de virar regra.
    ["minecraft:coal_block"] = colors.brown,
    ["minecraft:redstone_block"] = colors.red,
    ["minecraft:blaze_rod"] = colors.orange,
    ["minecraft:ice"] = colors.lightBlue,
    ["minecraft:packed_ice"] = colors.cyan,
    ["minecraft:blue_ice"] = colors.blue,
    ["minecraft:snow_block"] = colors.white,
}

function powah.corDe(id)
    return powah.CORES[id] or colors.yellow
end

function powah.nomeDe(id)
    return powah.NOMES[id] or (id:gsub("^.*:", ""):gsub("_", " "))
end

-- O que esta dentro do reator, por NOME DE ITEM. Um item pode ocupar mais de um slot,
-- entao a contagem soma e o slot guardado e' o primeiro (o destino de reposicao).
--
-- Por nome e nao por indice de slot: o Powah muda a ordem dos slots entre versoes, e
-- medido no servidor o slot 1 esta vazio enquanto o combustivel mora no 2. Codigo que
-- crava numero de slot quebra calado numa atualizacao do mod.
function powah.consumables(reading)
    local por, ordem = {}, {}
    for slot, item in pairs(reading and reading.slots or {}) do
        local e = por[item.name]
        if e then
            e.count = e.count + item.count
            if slot < e.slot then e.slot = slot end
        else
            e = { name = item.name, label = powah.nomeDe(item.name), count = item.count,
                  slot = slot, limit = 64, color = powah.corDe(item.name) }
            por[item.name] = e
            ordem[#ordem + 1] = e
        end
    end
    -- Ordem estavel: pelo slot. Sem isto as barras dancam de lugar entre quadros,
    -- porque `pairs` nao promete ordem nenhuma.
    table.sort(ordem, function(a, b) return a.slot < b.slot end)
    return ordem, por
end

-- Completa cada item do reator ate' o alvo, puxando do inventario `fromName`.
--
-- `alvos` e' opcional: { ["powah:uraninite"] = 64, ... }. Item sem alvo usa `padrao`.
-- So' repoe o que JA ESTA dentro: o reator e' que diz do que precisa, e assim nao ha
-- risco de empurrar item errado num slot que o aceite por acaso.
--
-- Devolve uma lista { { label, name, moved, para } } com o que entrou, para o registro
-- e o chat dizerem o que foi feito em vez de "reposto".
function powah.topUp(hw, fromName, reading, alvos, padrao)
    if not hw.reactor or not fromName then return {}, "sem reator ou sem origem" end
    local from = peripheral.wrap(fromName)
    if not from then return {}, "inventario '" .. fromName .. "' nao esta na rede" end
    local okL, disponivel = pcall(from.list)
    if not okL then return {}, "nao consegui ler " .. fromName end

    alvos = alvos or {}
    padrao = padrao or 64
    local feito = {}
    local _, por = powah.consumables(reading)
    for id, e in pairs(por) do
        local alvo = alvos[id] or padrao
        local falta = alvo - e.count
        if falta > 0 then
            local moveu = 0
            for fslot, item in pairs(disponivel or {}) do
                if item.name == id and moveu < falta then
                    local ok, n = pcall(hw.reactor.pullItems, fromName, fslot, falta - moveu, e.slot)
                    if ok and n then moveu = moveu + n end
                end
            end
            if moveu > 0 then
                feito[#feito + 1] = { name = id, label = e.label, moved = moveu, para = e.count + moveu }
            end
        end
    end
    table.sort(feito, function(a, b) return a.label < b.label end)
    return feito
end

-- Slot de combustivel: onde esta, ou o primeiro vazio, para poder reabastecer
-- um reator que ficou sem nada.
function powah.fuelSlot(hw, reading)
    if reading and reading.fuel and reading.fuel.slot then return reading.fuel.slot end
    if not hw.reactor then return nil end
    local list = hw.reactor.list() or {}
    for i = 1, (hw.reactor.size() or 0) do
        if not list[i] then return i end
    end
    return nil
end

-- Puxa combustivel de um inventario da rede com fio para dentro do reator.
-- Devolve quantos itens entraram (0 se nao tinha o que puxar).
function powah.feed(hw, fromName, slot, limit)
    if not hw.reactor or not fromName then return 0, "sem reator ou sem origem" end
    local from = peripheral.wrap(fromName)
    if not from then return 0, "inventario '" .. fromName .. "' nao esta na rede" end
    local moved = 0
    for fslot, item in pairs(from.list() or {}) do
        if item.name == powah.FUEL then
            local ok, n = pcall(hw.reactor.pullItems, fromName, fslot, limit, slot)
            if ok and n then moved = moved + n end
            if limit and moved >= limit then break end
        end
    end
    return moved
end

-- Parada de emergencia: tira o combustivel do reator. E a unica alavanca que
-- funciona sem hardware extra -- sem uraninita dentro, a reacao para.
function powah.pullFuel(hw, toName, reading)
    if not hw.reactor or not toName then return 0, "sem reator ou sem destino" end
    local slot = reading and reading.fuel and reading.fuel.slot
    if not slot then return 0, "nao ha combustivel para retirar" end
    local ok, n = pcall(hw.reactor.pushItems, toName, slot)
    if not ok then return 0, tostring(n) end
    return n or 0
end

-- Limita a saida de energia pelo Energy Detector. nil = sem detector.
function powah.setOutputLimit(hw, fePerTick)
    if not hw.energyDetector or not hw.energyDetector.setTransferRateLimit then return false end
    local ok = pcall(hw.energyDetector.setTransferRateLimit, math.floor(fePerTick))
    return ok
end

function powah.demo()
    -- Reator falso: so os metodos que o adaptador usa.
    local fake = {
        size = function() return 5 end,
        list = function()
            return {
                [2] = { name = "powah:uraninite", count = 16 },
                [3] = { name = "minecraft:coal_block", count = 15 },
                [5] = { name = "powah:dry_ice", count = 29 },
            }
        end,
        tanks = function() return { { name = "minecraft:water", amount = 1000 } } end,
    }
    local r = powah.read({ reactor = fake })
    assert(r.fuel.count == 16 and r.fuel.slot == 2, "combustivel nao foi achado pelo nome do item")
    assert(r.coolant.count == 29 and r.coolant.slot == 5, "refrigerante solido nao foi achado")
    assert(r.tank.amount == 1000, "tanque nao foi lido")
    assert(#r.extras == 1 and r.extras[1].name == "minecraft:coal_block", "extras errados: " .. #r.extras)
    assert(r.error == nil, "leitura boa nao devia ter erro")

    -- Reator vazio: contagem zero, sem estourar.
    local vazio = { size = function() return 5 end, list = function() return {} end,
                    tanks = function() return {} end }
    local r2 = powah.read({ reactor = vazio })
    assert(r2.fuel.count == 0 and r2.coolant.count == 0, "reator vazio devia dar zero")
    assert(r2.tank == nil, "sem tanque nao pode inventar tanque")

    -- Sem reator: erro explicito, nunca numero falso.
    local r3 = powah.read({})
    assert(r3.error, "sem reator tem de devolver erro")
    assert(r3.fuel == nil, "sem reator nao pode fingir combustivel")

    -- Reator que explode na chamada nao pode derrubar o app.
    local ruim = { list = function() error("desconectou") end }
    local r4 = powah.read({ reactor = ruim })
    assert(r4.error, "erro do periferico tinha de virar campo error")

    -- fuelSlot cai no primeiro vazio quando nao ha combustivel.
    assert(powah.fuelSlot({ reactor = vazio }, r2) == 1, "fuelSlot nao achou slot livre")
    assert(powah.fuelSlot({ reactor = fake }, r) == 2, "fuelSlot devia usar o slot do combustivel")

    -- Block Reader numa PECA do reator: o NBT util esta no nucleo, e core_pos diz onde.
    local naPeca = { getBlockData = function()
        return { x = 554, y = 96, z = -6497, core_pos = { X = 554, Y = 95, Z = -6496 } }
    end }
    local r5 = powah.read({ reactor = fake, blockReader = naPeca })
    assert(r5.coreHint, "nao apontou o nucleo a partir do core_pos")
    assert(r5.coreHint.x == 554 and r5.coreHint.y == 95 and r5.coreHint.z == -6496,
        "coordenada do nucleo errada")

    -- Ja no nucleo: core_pos aponta para o proprio bloco, nao pode pedir para mover.
    local noNucleo = { getBlockData = function()
        return { x = 554, y = 95, z = -6496, core_pos = { X = 554, Y = 95, Z = -6496 } }
    end }
    assert(powah.read({ reactor = fake, blockReader = noNucleo }).coreHint == nil,
        "leitor ja no nucleo nao devia pedir para mover")

    -- consumables: agrupa por NOME e devolve em ordem de slot, sempre igual.
    local itens, por = powah.consumables(r)
    assert(#itens == 3, "deviam ser tres itens distintos, deu " .. #itens)
    assert(itens[1].slot == 2 and itens[2].slot == 3 and itens[3].slot == 5,
        "a ordem tem de ser a dos slots, senao as barras dancam entre quadros")
    assert(por["powah:uraninite"].count == 16, "contagem por nome errada")
    assert(itens[1].label == "Uraninita", "nao traduziu o nome do item")
    assert(powah.nomeDe("mod:coisa_estranha") == "coisa estranha",
        "item desconhecido devia virar o id sem o mod, deu " .. powah.nomeDe("mod:coisa_estranha"))

    -- Dois slots com o mesmo item somam, e a reposicao vai para o PRIMEIRO deles.
    local dobrado = powah.read({ reactor = { size = function() return 5 end,
        list = function() return { [4] = { name = "powah:dry_ice", count = 10 },
                                   [2] = { name = "powah:dry_ice", count = 7 } } end,
        tanks = function() return {} end } })
    local doisItens, doisPor = powah.consumables(dobrado)
    assert(#doisItens == 1 and doisPor["powah:dry_ice"].count == 17,
        "o mesmo item em dois slots tinha de somar")
    assert(doisPor["powah:dry_ice"].slot == 2, "a reposicao tem de ir para o primeiro slot")

    -- topUp: completa ate' o alvo, so' do que ja esta dentro, e conta o que moveu.
    local movido = {}
    local bau = { list = function()
        return { [1] = { name = "powah:uraninite", count = 64 },
                 [2] = { name = "powah:dry_ice", count = 30 },
                 [3] = { name = "minecraft:diamond", count = 5 } }
    end }
    local comBau = { reactor = {
        size = function() return 5 end,
        list = fake.list, tanks = fake.tanks,
        pullItems = function(_, fslot, limite, destino)
            movido[#movido + 1] = { fslot = fslot, limite = limite, destino = destino }
            return limite
        end,
    } }
    -- peripheral.wrap do bau, so' para o teste
    local wrapAntigo = peripheral.wrap
    peripheral.wrap = function(n) if n == "bau" then return bau end return wrapAntigo(n) end
    local feito = powah.topUp(comBau, "bau", r, nil, 64)
    peripheral.wrap = wrapAntigo

    local porNome = {}
    for _, ff in ipairs(feito) do porNome[ff.name] = ff end
    assert(porNome["powah:uraninite"], "nao completou o combustivel")
    assert(porNome["powah:uraninite"].moved == 48, "16 + 48 = 64, deu " .. porNome["powah:uraninite"].moved)
    assert(porNome["powah:uraninite"].para == 64, "o total depois da reposicao esta errado")
    assert(porNome["powah:dry_ice"].moved == 35, "29 + 35 = 64, deu " .. porNome["powah:dry_ice"].moved)
    -- O carvao esta no reator e falta no bau: nao aparece no relatorio, porque nada
    -- foi movido. Item que nao existe na origem nao vira linha de "reposto".
    assert(not porNome["minecraft:coal_block"], "sem carvao no bau, nao ha o que repor")
    assert(not porNome["minecraft:diamond"], "nao pode empurrar item que o reator nao tem")
    for _, mv in ipairs(movido) do
        assert(mv.destino, "pullItems sem slot de destino cairia em qualquer lugar")
    end

    -- Alvo por item manda no padrao.
    local movido2 = {}
    comBau.reactor.pullItems = function(_, _, limite) movido2[#movido2 + 1] = limite return limite end
    peripheral.wrap = function(n) if n == "bau" then return bau end return wrapAntigo(n) end
    local feito2 = powah.topUp(comBau, "bau", r, { ["powah:uraninite"] = 20 }, 64)
    peripheral.wrap = wrapAntigo
    for _, ff in ipairs(feito2) do
        if ff.name == "powah:uraninite" then
            assert(ff.moved == 4, "com alvo 20 e 16 dentro, tinham de entrar 4, deu " .. ff.moved)
        end
    end

    -- Item ja no alvo nao move nada, e origem que nao existe nao derruba nada.
    local cheio = powah.read({ reactor = { size = function() return 1 end,
        list = function() return { [1] = { name = "powah:uraninite", count = 64 } } end,
        tanks = function() return {} end } })
    peripheral.wrap = function() return bau end
    assert(#powah.topUp(comBau, "bau", cheio, nil, 64) == 0, "item no alvo nao devia mover nada")
    peripheral.wrap = wrapAntigo
    local semBau, errBau = powah.topUp(comBau, "nao_existe", r)
    assert(#semBau == 0 and errBau, "origem inexistente tinha de devolver erro")

    -- Leitor que nao le nada (apontado para o ar) nao pode derrubar a leitura.
    local noAr = { getBlockData = function() return nil end }
    assert(powah.read({ reactor = fake, blockReader = noAr }).nbt == nil, "nbt inventado do nada")
    return true
end

return powah
