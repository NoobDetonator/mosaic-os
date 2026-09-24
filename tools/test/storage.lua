-- Testes do gerenciamento de inventario. Somente perifericos em memoria: nenhum
-- item do mundo, computador conectado ou relay e' acessado por esta suite.
-- Uso no run.lua: dofile("/test/storage.lua")(check)

local unpack = table.unpack or unpack

local function copyItem(item)
    if not item then return nil end
    return {
        name = item.name, count = item.count, nbt = item.nbt,
        displayName = item.displayName or item.name, maxCount = item.maxCount or 64,
    }
end

local function fakeNetwork()
    local network = { nodes = {}, calls = {} }

    function network.add(name, kind, capacity, initial)
        local inv = { name = name, kind = kind, capacity = capacity, slots = {}, online = true }
        for slot, item in pairs(initial or {}) do inv.slots[slot] = copyItem(item) end

        inv.size = function()
            if not inv.online then error("Inventory unavailable", 2) end
            return inv.capacity
        end
        inv.list = function()
            if not inv.online then error("Inventory unavailable", 2) end
            local result = {}
            for slot, item in pairs(inv.slots) do result[slot] = copyItem(item) end
            return result
        end
        inv.getItemDetail = function(slot)
            if not inv.online then error("Inventory unavailable", 2) end
            return copyItem(inv.slots[slot])
        end

        local function sameItem(a, b)
            return a and b and a.name == b.name and a.nbt == b.nbt
        end

        inv.pushItems = function(toName, fromSlot, limit, toSlot)
            local dest = network.nodes[toName]
            network.calls[#network.calls + 1] = {
                from = name, to = toName, slot = fromSlot, limit = limit, toSlot = toSlot,
            }
            if not inv.online or not dest or not dest.online then
                error("Source or destination does not exist", 2)
            end
            local sourceItem = inv.slots[fromSlot]
            if not sourceItem then return 0 end
            local wanted = math.min(sourceItem.count, math.max(0, limit or sourceItem.count))
            local moved = 0

            local function put(slot)
                if moved >= wanted then return end
                local current = dest.slots[slot]
                if current and not sameItem(current, sourceItem) then return end
                local maxCount = (current and current.maxCount) or sourceItem.maxCount or 64
                local free = maxCount - (current and current.count or 0)
                local n = math.min(free, wanted - moved)
                if n <= 0 then return end
                if current then current.count = current.count + n
                else
                    dest.slots[slot] = copyItem(sourceItem)
                    dest.slots[slot].count = n
                end
                moved = moved + n
            end

            if toSlot then
                if toSlot >= 1 and toSlot <= dest.capacity then put(toSlot) end
            else
                -- Comportamento do Inventory do CC: primeiro empilhar, depois slots livres.
                for slot = 1, dest.capacity do
                    if dest.slots[slot] and sameItem(dest.slots[slot], sourceItem) then put(slot) end
                end
                for slot = 1, dest.capacity do
                    if not dest.slots[slot] then put(slot) end
                end
            end
            sourceItem.count = sourceItem.count - moved
            if sourceItem.count == 0 then inv.slots[fromSlot] = nil end
            return moved
        end
        inv.pullItems = function(fromName, fromSlot, limit, toSlot)
            local source = network.nodes[fromName]
            if not source then error("Source does not exist", 2) end
            return source.pushItems(name, fromSlot, limit, toSlot)
        end

        network.nodes[name] = inv
        return inv
    end

    local api = {}
    api.getNames = function()
        local names = {}
        for name, inv in pairs(network.nodes) do
            if inv.online then names[#names + 1] = name end
        end
        table.sort(names)
        return names
    end
    api.isPresent = function(name)
        return network.nodes[name] ~= nil and network.nodes[name].online
    end
    api.wrap = function(name)
        local inv = network.nodes[name]
        return inv and inv.online and inv or nil
    end
    api.getType = function(name)
        local inv = network.nodes[name]
        if not inv or not inv.online then return nil end
        return inv.kind, "inventory"
    end
    api.hasType = function(name, kind)
        local inv = network.nodes[name]
        return inv ~= nil and inv.online and (kind == inv.kind or kind == "inventory")
    end
    api.getName = function(obj)
        for name, inv in pairs(network.nodes) do if inv == obj then return name end end
    end
    api.getMethods = function(name)
        local inv = network.nodes[name]
        if not inv or not inv.online then return nil end
        return { "size", "list", "getItemDetail", "pushItems", "pullItems" }
    end
    api.find = function(kind, filter)
        local result = {}
        for _, name in ipairs(api.getNames()) do
            local inv = network.nodes[name]
            if (kind == "inventory" or kind == inv.kind)
                and (not filter or filter(name, inv)) then
                result[#result + 1] = inv
            end
        end
        return unpack(result)
    end
    api.call = function(name, method, ...)
        local inv = api.wrap(name)
        if not inv or not inv[method] then error("No such method", 2) end
        return inv[method](...)
    end
    network.api = api
    return network
end

local function count(inv, name, nbt)
    local total = 0
    for _, item in pairs(inv.slots) do
        if item.name == name and item.nbt == nbt then total = total + item.count end
    end
    return total
end

local function find(items, name, nbt)
    for _, item in ipairs(items or {}) do
        if item.name == name and item.nbt == nbt then return item end
    end
end

return function(check)
    local originalPeripheral = peripheral
    local net = fakeNetwork()
    peripheral = net.api
    local loaded, storage = pcall(dofile, "/os/lib/storage.lua")
    if not loaded then
        peripheral = originalPeripheral
        check(false, "storage: nao carregou a engine: " .. tostring(storage))
        return
    end

    local function scenario(name, fn)
        net = fakeNetwork()
        peripheral = net.api
        local ok, err = pcall(fn, net)
        check(ok, "storage: " .. name .. (ok and "" or " - " .. tostring(err)))
    end

    scenario("descoberta exclui maquinas e portas", function(n)
        n.add("minecraft:chest_0", "minecraft:chest", 9, {
            [1] = { name = "minecraft:iron_ingot", count = 12 },
        })
        n.add("minecraft:barrel_0", "minecraft:barrel", 9, {
            [1] = { name = "minecraft:iron_ingot", count = 4 },
        })
        n.add("mod:machine_0", "mod:machine", 9, {
            [1] = { name = "minecraft:iron_ingot", count = 64 },
        })
        n.add("minecraft:chest_input", "minecraft:chest", 9, {
            [1] = { name = "minecraft:gold_ingot", count = 9 },
        })
        n.add("minecraft:chest_output", "minecraft:chest", 9, {
            [1] = { name = "minecraft:dirt", count = 7 },
        })
        local cfg = { roles = {
            ["minecraft:chest_input"] = "input",
            ["minecraft:chest_output"] = "output",
        } }
        local snap = storage.scan(cfg)
        local iron = find(snap.items, "minecraft:iron_ingot")
        assert(iron and iron.count == 16, "baus de storage nao foram somados")
        assert(not find(snap.items, "minecraft:gold_ingot"), "input contado como storage")
        assert(not find(snap.items, "minecraft:dirt"), "output contado como storage")
        assert((snap.totalItems or 0) == 16, "maquina foi contada como storage")
    end)

    scenario("variantes NBT nao se misturam", function(n)
        n.add("minecraft:chest_0", "minecraft:chest", 9, {
            [1] = { name = "minecraft:enchanted_book", nbt = "hash-A", count = 1,
                displayName = "Livro A", maxCount = 1 },
            [2] = { name = "minecraft:enchanted_book", nbt = "hash-A", count = 1,
                displayName = "Livro A", maxCount = 1 },
            [3] = { name = "minecraft:enchanted_book", nbt = "hash-B", count = 1,
                displayName = "Livro B", maxCount = 1 },
        })
        n.add("minecraft:chest_output", "minecraft:chest", 9)
        local cfg = { roles = { ["minecraft:chest_output"] = "output" } }
        local snap = storage.scan(cfg)
        local a = find(snap.items, "minecraft:enchanted_book", "hash-A")
        local b = find(snap.items, "minecraft:enchanted_book", "hash-B")
        assert(a and b and a.key ~= b.key, "variantes combinadas no catalogo")
        assert(a.count == 2 and b.count == 1, "quantidade das variantes incorreta")
        local result = storage.withdraw(cfg, b.key, 1)
        assert(result.moved == 1, "retirada da variante B falhou")
        assert(count(n.nodes["minecraft:chest_0"], "minecraft:enchanted_book", "hash-A") == 2,
            "retirada da B alterou a variante A")
        assert(count(n.nodes["minecraft:chest_output"], "minecraft:enchanted_book", "hash-B") == 1,
            "variante errada chegou a saida")
    end)

    scenario("deposito ocupa stack existente antes de slot novo", function(n)
        local empty = n.add("minecraft:chest_1", "minecraft:chest", 2)
        local partial = n.add("minecraft:chest_2", "minecraft:chest", 2, {
            [1] = { name = "minecraft:iron_ingot", count = 60 },
        })
        local input = n.add("minecraft:chest_input", "minecraft:chest", 2, {
            [1] = { name = "minecraft:iron_ingot", count = 10 },
        })
        local cfg = { roles = { ["minecraft:chest_input"] = "input" } }
        local result = storage.deposit(cfg)
        assert(result.moved == 10, "deposito nao moveu os dez itens")
        assert(partial.slots[1] and partial.slots[1].count == 64,
            "stack existente nao foi preenchida primeiro")
        assert(count(empty, "minecraft:iron_ingot") + count(partial, "minecraft:iron_ingot") == 70,
            "saldo apos deposito incorreto")
        assert(count(input, "minecraft:iron_ingot") == 0, "itens ficaram na entrada")
    end)

    scenario("retirada parcial informa a quantidade real", function(n)
        local source = n.add("minecraft:chest_0", "minecraft:chest", 2, {
            [1] = { name = "minecraft:cobblestone", count = 20 },
        })
        local output = n.add("minecraft:chest_output", "minecraft:chest", 1, {
            [1] = { name = "minecraft:cobblestone", count = 62 },
        })
        local cfg = { roles = { ["minecraft:chest_output"] = "output" } }
        local key = assert(find(storage.scan(cfg).items, "minecraft:cobblestone")).key
        local result = storage.withdraw(cfg, key, 10)
        assert(result.requested == 10 and result.moved == 2,
            "resultado parcial incorreto: " .. tostring(result.moved))
        assert(count(source, "minecraft:cobblestone") == 18, "origem perdeu quantidade errada")
        assert(count(output, "minecraft:cobblestone") == 64, "saida excedeu sua capacidade")
    end)

    scenario("bau indisponivel nao perde itens", function(n)
        local source = n.add("minecraft:chest_0", "minecraft:chest", 2, {
            [1] = { name = "minecraft:diamond", count = 5 },
        })
        local output = n.add("minecraft:chest_output", "minecraft:chest", 2)
        local cfg = { roles = { ["minecraft:chest_output"] = "output" } }
        local key = assert(find(storage.scan(cfg).items, "minecraft:diamond")).key
        source.online = false
        local result = storage.withdraw(cfg, key, 3)
        assert(result and result.moved == 0, "ba'u offline informou transferencia")
        assert(count(source, "minecraft:diamond") == 5, "ba'u offline perdeu itens")
        assert(count(output, "minecraft:diamond") == 0, "item apareceu na saida")
    end)

    scenario("portas nunca viram armazenamento automatico", function(n)
        local input = n.add("minecraft:chest_input", "minecraft:chest", 2, {
            [1] = { name = "minecraft:gold_ingot", count = 3 },
        })
        local output = n.add("minecraft:chest_output", "minecraft:chest", 2, {
            [1] = { name = "minecraft:emerald", count = 2 },
        })
        local cfg = { roles = {
            ["minecraft:chest_input"] = "input",
            ["minecraft:chest_output"] = "output",
        } }
        local snap = storage.scan(cfg)
        assert(#snap.items == 0 and (snap.totalItems or 0) == 0,
            "porta apareceu como storage")
        local result = storage.deposit(cfg)
        assert(result.moved == 0 and #n.calls == 0, "deposito moveu entre portas")
        assert(count(input, "minecraft:gold_ingot") == 3, "entrada foi alterada")
        assert(count(output, "minecraft:emerald") == 2, "saida foi alterada")
    end)

    peripheral = originalPeripheral
end
