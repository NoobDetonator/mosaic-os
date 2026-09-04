-- HAL: acesso pratico a perifericos, com nomes do Advanced Peripherals 0.7 (Minecraft 1.16.5).
-- `local hal = mosaic.lib("hal")`
local hal = {}

-- Nomes de tipo por categoria. A primeira que existir e usada.
hal.types = {
    chatBox = { "chatBox" },
    playerDetector = { "playerDetector" },
    environmentDetector = { "environmentDetector" },
    energyDetector = { "energyDetector" },
    blockReader = { "blockReader" },
    geoScanner = { "geoScanner" },
    inventoryManager = { "inventoryManager" },
    redstoneIntegrator = { "redstoneIntegrator" },
    meBridge = { "meBridge" },
    rsBridge = { "rsBridge" },
    colonyIntegrator = { "colonyIntegrator" },
    nbtStorage = { "NBTStorage", "nbtStorage" },
    arController = { "arController" },
    monitor = { "monitor" },
    modem = { "modem" },
    speaker = { "speaker" },
    drive = { "drive" },
    printer = { "printer" },
}

-- Procura um periferico por apelido (ver hal.types) ou pelo tipo cru.
function hal.find(kind)
    local names = hal.types[kind] or { kind }
    for _, t in ipairs(names) do
        local p = peripheral.find(t)
        if p then return p, t end
    end
    return nil
end

function hal.findAll(kind)
    local names = hal.types[kind] or { kind }
    local out = {}
    for _, t in ipairs(names) do
        for _, p in ipairs({ peripheral.find(t) }) do out[#out + 1] = p end
    end
    return out
end

function hal.has(kind) return hal.find(kind) ~= nil end

-- Lista tudo que esta conectado: { {name=, type=, methods=n}, ... }
function hal.list()
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name)
        out[#out + 1] = {
            name = name,
            type = peripheral.getType(name) or "?",
            methods = methods and #methods or 0,
            side = not name:find("_") and name or nil,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ---------------------------------------------------------------- energia
-- Funciona com energyDetector (AP), celulas Powah/Mekanism e qualquer bloco
-- com a interface generica energy_storage do CC:T.
function hal.energy(target)
    local p = target
    if type(p) == "string" then p = peripheral.wrap(p) end
    if not p then p = peripheral.find("energy_storage") or hal.find("energyDetector") end
    if not p then return nil end
    local info = { stored = 0, capacity = 0, rate = nil }
    if p.getEnergy then info.stored = p.getEnergy() or 0 end
    if p.getEnergyCapacity then info.capacity = p.getEnergyCapacity() or 0 end
    if p.getEnergyStored then info.stored = p.getEnergyStored() or info.stored end
    if p.getEnergyMaxStored then info.capacity = p.getEnergyMaxStored() or info.capacity end
    if p.getTransferRate then info.rate = p.getTransferRate() end
    if p.getTransferRateLimit then info.limit = p.getTransferRateLimit() end
    info.percent = info.capacity > 0 and (info.stored / info.capacity * 100) or 0
    return info
end

-- ---------------------------------------------------------------- inventarios
-- Soma os itens de todos os inventarios conectados (ou de um especifico).
-- Devolve { ["minecraft:iron_ingot"] = { count = 12, name = ..., display = ... }, ... }
function hal.items(source)
    local invs = {}
    if source then
        local p = type(source) == "string" and peripheral.wrap(source) or source
        if p then invs[1] = p end
    else
        invs = { peripheral.find("inventory") }
    end
    local totals = {}
    for _, inv in ipairs(invs) do
        if inv.list then
            for slot, item in pairs(inv.list()) do
                local entry = totals[item.name]
                if not entry then
                    entry = { name = item.name, count = 0, slots = {} }
                    totals[item.name] = entry
                end
                entry.count = entry.count + item.count
                entry.slots[#entry.slots + 1] = slot
            end
        end
    end
    return totals
end

-- Total de um item em todos os inventarios.
function hal.countItem(name)
    local t = hal.items()
    return t[name] and t[name].count or 0
end

-- ---------------------------------------------------------------- ME / RS bridge
-- Interface unica para Applied Energistics (meBridge) e Refined Storage (rsBridge).
function hal.storage()
    local bridge, kind = hal.find("meBridge")
    if bridge then kind = "me" else bridge, kind = hal.find("rsBridge"), "rs" end
    if not bridge then return nil end
    local s = { raw = bridge, kind = kind }
    function s.items() return bridge.listItems and bridge.listItems() or {} end
    function s.item(filter) return bridge.getItem and bridge.getItem(filter) or nil end
    function s.count(name)
        local it = s.item({ name = name })
        return it and it.amount or 0
    end
    function s.craft(filter) return bridge.craftItem and bridge.craftItem(filter) or nil end
    function s.isCrafting(filter) return bridge.isItemCrafting and bridge.isItemCrafting(filter) or false end
    function s.energy()
        if bridge.getEnergyStorage then
            return { stored = bridge.getEnergyStorage() or 0, capacity = bridge.getMaxEnergyStorage and bridge.getMaxEnergyStorage() or 0 }
        end
        return nil
    end
    function s.exportTo(filter, direction) return bridge.exportItem and bridge.exportItem(filter, direction) or nil end
    function s.importFrom(filter, direction) return bridge.importItem and bridge.importItem(filter, direction) or nil end
    return s
end

-- ---------------------------------------------------------------- chat / jogadores
function hal.chat(message, prefix)
    local box = hal.find("chatBox")
    if not box then return false, "sem chatBox conectado" end
    return box.sendMessage(message, prefix or "Mosaic")
end

function hal.chatTo(player, message, prefix)
    local box = hal.find("chatBox")
    if not box then return false, "sem chatBox conectado" end
    if box.sendMessageToPlayer then return box.sendMessageToPlayer(message, player, prefix or "Mosaic") end
    return false, "chatBox sem sendMessageToPlayer"
end

function hal.players()
    local d = hal.find("playerDetector")
    if not d then return {} end
    return d.getOnlinePlayers and d.getOnlinePlayers() or {}
end

function hal.playersNear(range)
    local d = hal.find("playerDetector")
    if not d or not d.getPlayersInRange then return {} end
    return d.getPlayersInRange(range or 16)
end

-- ---------------------------------------------------------------- redstone
-- Aceita lados do computador ("top") ou um redstoneIntegrator conectado.
function hal.setRedstone(side, on, integrator)
    if integrator then
        local p = type(integrator) == "string" and peripheral.wrap(integrator) or integrator
        if p and p.setOutput then p.setOutput(side, on) return true end
        return false
    end
    redstone.setOutput(side, on and true or false)
    return true
end

function hal.getRedstone(side, integrator)
    if integrator then
        local p = type(integrator) == "string" and peripheral.wrap(integrator) or integrator
        if p and p.getInput then return p.getInput(side) end
        return false
    end
    return redstone.getInput(side)
end

function hal.pulse(side, secs)
    hal.setRedstone(side, true)
    sleep(secs or 0.2)
    hal.setRedstone(side, false)
end

-- ---------------------------------------------------------------- monitores

-- Todos os monitores, COM o nome e o tamanho atual.
--
-- O nome e' obrigatorio para multi-tela: e' ele que vem no `monitor_touch` e no
-- `peripheral_detach`, e e' por ele que se sabe qual app esta em qual parede. Por isso nao
-- da para usar `hal.findAll`: ele devolve os objetos e perde o nome.
function hal.monitors()
    local out = {}
    if not peripheral then return out end
    local ok, names = pcall(peripheral.getNames)
    if not ok or not names then return out end
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "monitor" then
            local m = peripheral.wrap(name)
            -- Monitor quebrado no jogo entre o getNames e o wrap: some da lista, nao estoura.
            local okSize, w, h = pcall(function() return m.getSize() end)
            if m and okSize then
                out[#out + 1] = { name = name, p = m, w = w, h = h }
            end
        end
    end
    return out
end

-- Maior escala de texto que ainda deixa o conteudo caber: texto grande se le de longe, mas
-- nao pode espremer o que esta escrito.
--
-- Veio do apps/reactor.lua, onde a politica foi decidida medindo no servidor: um monitor
-- 2x2 so' serve a 0,5 (36x10); um maior aguenta 1 e fica bem mais legivel de longe.
function hal.fitMonitor(m, minW, minH, wideW)
    minW, minH = minW or 26, minH or 8
    -- Se a escala menor render uma tela larga, ela vence: e' a unica que abre layout de duas
    -- colunas. Texto menor, mas muito mais informacao na parede.
    if wideW then
        local ok = pcall(m.setTextScale, 0.5)
        if ok and select(1, m.getSize()) >= wideW then return 0.5 end
    end
    -- Senao, a MAIOR escala que ainda deixa caber: num monitor pequeno vale mais ler de
    -- longe do que espremer.
    for _, s in ipairs({ 5, 4, 3, 2, 1.5, 1, 0.5 }) do
        if pcall(m.setTextScale, s) then
            local mw, mh = m.getSize()
            if mw >= minW and mh >= minH then return s end
        end
    end
    pcall(m.setTextScale, 0.5)
    return 0.5
end

-- Prepara um monitor: escala, limpa e devolve o objeto.
function hal.monitor(scale, name)
    local mon = name and peripheral.wrap(name) or peripheral.find("monitor")
    if not mon then return nil end
    if scale then mon.setTextScale(scale) end
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
    return mon
end

-- ---------------------------------------------------------------- ambiente
function hal.environment()
    local d = hal.find("environmentDetector")
    if not d then return nil end
    local env = {}
    local function try(key, fn) if fn then local ok, v = pcall(fn) if ok then env[key] = v end end end
    try("time", d.getTime)
    try("biome", d.getBiome)
    try("raining", d.isRaining)
    try("thunder", d.isThunder)
    try("sunny", d.isSunny)
    try("moon", d.getMoonName)
    try("dimension", d.getDimension)
    try("light", d.getDayLightLevel)
    try("radiation", d.getRadiationRaw)
    return env
end

-- ---------------------------------------------------------------- drives (disquete)
-- Devolve um item por drive de disquete, esteja ele vazio ou nao. `mount` e' onde o CC
-- montou o disquete (/disk, /disk2, ...), que e' o que a barra lateral do Arquivos abre.
--
-- A API `disk` nao existe no emulador em JS a nao ser como esboco: teste disquete no
-- CraftOS-PC ou no jogo, nunca no `tools/test.js`.
function hal.drives()
    local out = {}
    if not disk then return out end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "drive" then
            local ok, present = pcall(disk.isPresent, name)
            present = ok and present or false
            local d = { side = name, present = present }
            if present then
                local function try(fn) local o, v = pcall(fn, name) return o and v or nil end
                d.mount = try(disk.getMountPath)
                d.id = try(disk.getID)
                d.hasData = try(disk.hasData) or false
                d.hasAudio = try(disk.hasAudio) or false
                d.label = try(disk.getLabel)
                if not d.label or d.label == "" then
                    d.label = d.hasAudio and "Disco de musica" or ("Disquete " .. tostring(d.id or "?"))
                end
            end
            out[#out + 1] = d
        end
    end
    return out
end

return hal
