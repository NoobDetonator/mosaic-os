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
    local e = hal.energy(hw.reactor) or {}
    if hw.energyDetector then
        local okR, rate = pcall(hw.energyDetector.getTransferRate)
        if okR then e.rate = rate end
        local okL, lim = pcall(hw.energyDetector.getTransferRateLimit)
        if okL then e.limit = lim end
    end
    if (e.capacity or 0) > 0 or e.rate then r.energy = e end

    -- Temperatura so existe via NBT do bloco.
    if hw.blockReader then
        local okB, data = pcall(hw.blockReader.getBlockData)
        if okB and type(data) == "table" then r.nbt = data end
    end
    return r
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
    return true
end

return powah
