-- Armazenamento em rede: indice de inventarios e transferencias seguras.
--
-- Cada bau precisa de modem com fio na mesma rede do computador e das portas.
-- A biblioteca nao guarda saldo: cada operacao consulta os inventarios de novo.
-- Assim, itens retirados por jogadores ou outros computadores nao viram estoque fantasma.
local storage = {}
local unpack = table.unpack or unpack

local SIDES = { top = true, bottom = true, left = true, right = true,
                front = true, back = true }
local ROLES = { storage = true, input = true, output = true, ignore = true }
local STORAGE_TYPES = { "chest", "barrel", "drawer", "crate", "shulker", "armoire" }
local displayCache, cacheSize = {}, 0

-- Chave sem ambiguidade para variantes com NBT (encantamento, dano, conteudo etc.).
-- O hash NBT nao e' legivel, mas identifica pilhas equivalentes no CC:T.
function storage.key(name, nbt)
    local variant = nbt or ""
    return tostring(#name) .. ":" .. name .. tostring(#variant) .. ":" .. variant
end

local function stackKey(item)
    return storage.key(item.name, item.nbt)
end

local function typesOf(name)
    local result = { pcall(peripheral.getType, name) }
    local types = {}
    if result[1] then
        for i = 2, #result do
            if type(result[i]) == "string" then types[#types + 1] = result[i] end
        end
    end
    return types
end

local function typeName(types)
    for _, name in ipairs(types) do
        if name ~= "inventory" then return name end
    end
    return types[1] or "inventory"
end

local function isStorageType(types, peripheralName)
    local candidates = { peripheralName }
    for _, kind in ipairs(types) do candidates[#candidates + 1] = kind end
    for _, name in ipairs(candidates) do
        local lower = name:lower()
        if lower ~= "inventory" and not lower:find("minecart", 1, true) then
            for _, needle in ipairs(STORAGE_TYPES) do
                if lower:find(needle, 1, true) then return true end
            end
        end
    end
    return false
end

local function roleFor(config, name, types)
    local chosen = type(config.roles) == "table" and config.roles[name] or nil
    if ROLES[chosen] then return chosen end
    -- Um bau ao lado pode ser o MESMO bau que aparece pelo modem com nome de rede.
    -- Nao incluir lados automaticamente evita contar seus itens duas vezes; tambem evita
    -- prometer transferencias lado <-> rede que o CC:T nao consegue fazer.
    if not SIDES[name] and isStorageType(types, name) then return "storage" end
    return "ignore"
end

local function readList(device)
    if not device or not device.p or not device.p.list then return nil, "inventario ausente" end
    local ok, items = pcall(device.p.list)
    if not ok then return nil, tostring(items) end
    if type(items) ~= "table" then return nil, "list() nao devolveu tabela" end
    return items
end

local function readSize(device)
    if not device or not device.p or not device.p.size then return nil, "inventario ausente" end
    local ok, size = pcall(device.p.size)
    if not ok then return nil, tostring(size) end
    if type(size) ~= "number" or size < 0 then return nil, "size() invalido" end
    return math.floor(size)
end

local function detail(device, slot)
    if not device.p.getItemDetail then return nil end
    local ok, item = pcall(device.p.getItemDetail, slot)
    return ok and type(item) == "table" and item or nil
end

local function addPort(snapshot, role, name)
    local field = role == "input" and "input" or "output"
    local plural = role == "input" and "inputs" or "outputs"
    snapshot[plural][#snapshot[plural] + 1] = name
    if not snapshot[field] then snapshot[field] = name end
end

local function build(config)
    config = type(config) == "table" and config or {}
    local snapshot = {
        inventories = {}, items = {}, totalItems = 0, usedSlots = 0, totalSlots = 0,
        inputItems = 0, outputItems = 0, inputs = {}, outputs = {},
        storageCount = 0, error = nil,
    }
    local devices, byItem, seen, errors = {}, {}, {}, {}
    if not peripheral or not peripheral.getNames then
        snapshot.error = "API de perifericos indisponivel"
        return snapshot, devices
    end
    local okNames, names = pcall(peripheral.getNames)
    if not okNames or type(names) ~= "table" then
        snapshot.error = "Nao consegui listar os perifericos"
        return snapshot, devices
    end
    table.sort(names)

    for _, name in ipairs(names) do
        seen[name] = true
        local okWrap, p = pcall(peripheral.wrap, name)
        if okWrap and p and type(p.list) == "function" and type(p.size) == "function" then
            local types = typesOf(name)
            local role = roleFor(config, name, types)
            local info = { name = name, type = typeName(types), role = role,
                slots = 0, used = 0, items = 0, online = true }
            local device = { name = name, p = p, role = role, info = info }
            devices[name] = device
            snapshot.inventories[#snapshot.inventories + 1] = info
            if role ~= "ignore" then
                local size, sizeErr = readSize(device)
                local list, listErr = readList(device)
                if not size or not list then
                    info.error = "Nao consegui ler: " .. tostring(sizeErr or listErr)
                    errors[#errors + 1] = name .. ": " .. info.error
                else
                    device.size, device.list = size, list
                    if role == "input" or role == "output" then addPort(snapshot, role, name) end
                    info.slots = size
                    for slot, item in pairs(list) do
                        if type(slot) == "number" and type(item) == "table"
                            and type(item.name) == "string" and type(item.count) == "number"
                            and item.count > 0 then
                            info.used = info.used + 1
                            info.items = info.items + item.count
                            if role == "storage" then
                                local key = stackKey(item)
                                local entry = byItem[key]
                                if not entry then
                                    local cached = displayCache[key]
                                    if not cached then
                                        local d = detail(device, slot)
                                        cached = {
                                            display = d and d.displayName or item.name,
                                            maxCount = d and tonumber(d.maxCount) or 64,
                                        }
                                        if cacheSize >= 512 then displayCache, cacheSize = {}, 0 end
                                        displayCache[key] = cached
                                        cacheSize = cacheSize + 1
                                    end
                                    entry = { key = key, name = item.name, nbt = item.nbt,
                                        display = cached.display, maxCount = cached.maxCount,
                                        count = 0, locations = {} }
                                    byItem[key] = entry
                                    snapshot.items[#snapshot.items + 1] = entry
                                end
                                entry.count = entry.count + item.count
                                entry.locations[#entry.locations + 1] = {
                                    inventory = name, slot = slot, count = item.count,
                                }
                            end
                        end
                    end
                    if role == "storage" then
                        snapshot.storageCount = snapshot.storageCount + 1
                        snapshot.totalItems = snapshot.totalItems + info.items
                        snapshot.usedSlots = snapshot.usedSlots + info.used
                        snapshot.totalSlots = snapshot.totalSlots + info.slots
                    elseif role == "input" then
                        snapshot.inputItems = snapshot.inputItems + info.items
                    elseif role == "output" then
                        snapshot.outputItems = snapshot.outputItems + info.items
                    end
                end
            end
        end
    end

    -- Papéis escolhidos continuam visiveis quando o cabo, o modem ou o bau some.
    for name, role in pairs(type(config.roles) == "table" and config.roles or {}) do
        if ROLES[role] and role ~= "ignore" and not seen[name] then
            snapshot.inventories[#snapshot.inventories + 1] = {
                name = name, type = "?", role = role, slots = 0, used = 0,
                items = 0, online = false, error = "Desconectado",
            }
            errors[#errors + 1] = name .. ": desconectado"
        end
    end

    for _, entry in ipairs(snapshot.items) do
        table.sort(entry.locations, function(a, b)
            if a.inventory ~= b.inventory then return a.inventory < b.inventory end
            return a.slot < b.slot
        end)
    end
    table.sort(snapshot.items, function(a, b)
        local al, bl = a.display:lower(), b.display:lower()
        if al ~= bl then return al < bl end
        return a.key < b.key
    end)
    table.sort(snapshot.inventories, function(a, b) return a.name < b.name end)
    if snapshot.storageCount == 0 then
        snapshot.error = "Nenhum bau de armazenamento na rede com fio"
    elseif #errors > 0 then
        snapshot.error = table.concat(errors, "; ")
    end
    return snapshot, devices
end

function storage.scan(config)
    local snapshot = build(config)
    return snapshot
end

local function matchingSlots(device, key)
    local list, err = readList(device)
    if not list then return nil, err end
    local size, sizeErr = readSize(device)
    if not size then return nil, sizeErr end
    local same, empty = {}, {}
    for slot = 1, size do
        local item = list[slot]
        if not item then
            empty[#empty + 1] = slot
        elseif type(item.name) == "string" and stackKey(item) == key then
            -- Uma pilha pode estar cheia. pushItems devolve 0 e tenta o proximo slot.
            same[#same + 1] = slot
        end
    end
    for _, slot in ipairs(empty) do same[#same + 1] = slot end
    return same
end

local function freshStack(device, slot, key)
    local list, err = readList(device)
    if not list then return nil, err end
    local item = list[slot]
    if not item or type(item.name) ~= "string" or stackKey(item) ~= key then
        return nil, "O item mudou de lugar"
    end
    return item
end

local function push(source, target, fromSlot, amount, toSlot)
    local fn, args
    if source.p.pushItems then
        fn = source.p.pushItems
        args = { target.name, fromSlot, amount, toSlot }
    elseif target.p.pullItems then
        fn = target.p.pullItems
        args = { source.name, fromSlot, amount, toSlot }
    else
        return 0, "Inventarios nao permitem mover itens"
    end
    local ok, moved = pcall(fn, unpack(args))
    if not ok then return 0, tostring(moved) end
    if type(moved) ~= "number" or moved < 0 then return 0, "Transferencia sem quantidade valida" end
    return moved
end

-- Preenche primeiro pilhas da MESMA variante, depois usa slots vazios. Cada tentativa
-- confere o slot de origem novamente; outro jogador pode mexer nos baus entre leituras.
local function moveSlot(source, fromSlot, target, key, limit)
    local slots, err = matchingSlots(target, key)
    if not slots then return 0, err end
    local moved, lastError = 0, nil
    for _, toSlot in ipairs(slots) do
        if moved >= limit then break end
        local current, currentErr = freshStack(source, fromSlot, key)
        if not current then lastError = currentErr break end
        local amount = math.min(limit - moved, current.count)
        if amount <= 0 then break end
        local n, transferErr = push(source, target, fromSlot, amount, toSlot)
        if transferErr then
            lastError = transferErr
            break
        end
        moved = moved + n
    end
    return moved, lastError
end

local function liveDevices(devices, role)
    local out = {}
    for _, device in pairs(devices) do
        if device.role == role and device.list and device.size then out[#out + 1] = device end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Prefere baus que ja guardam a mesma variante. Entre os demais, distribui nos que
-- tem mais slots livres. A ordem por nome desempata e torna o resultado previsivel.
local function rankStores(stores, key)
    local ranks = {}
    for _, device in ipairs(stores) do
        local same, used = 0, 0
        for _, item in pairs(device.list) do
            used = used + 1
            if type(item.name) == "string" and stackKey(item) == key then same = same + 1 end
        end
        ranks[device] = { same = same > 0 and 1 or 0, free = device.size - used }
    end
    table.sort(stores, function(a, b)
        local ar, br = ranks[a], ranks[b]
        if ar.same ~= br.same then return ar.same > br.same end
        if ar.free ~= br.free then return ar.free > br.free end
        return a.name < b.name
    end)
end

-- Retira uma variante para o bau de saida. Quantidade pedida e movida sao separadas:
-- saida cheia, item retirado por outro jogador, ou estoque curto geram resultado parcial.
function storage.withdraw(config, key, count)
    local requested = tonumber(count)
    if type(key) ~= "string" or not requested or requested < 1 or requested % 1 ~= 0 then
        return { moved = 0, requested = count, error = "Escolha um item e uma quantidade positiva" }
    end
    local snapshot, devices = build(config)
    local outputs = liveDevices(devices, "output")
    if #outputs == 0 then
        return { moved = 0, requested = requested, error = "Configure um bau de saida conectado" }
    end
    local entry
    for _, item in ipairs(snapshot.items) do if item.key == key then entry = item break end end
    if not entry then
        return { moved = 0, requested = requested, error = "Item nao encontrado no armazenamento" }
    end
    local locations = {}
    for _, loc in ipairs(entry.locations) do locations[#locations + 1] = loc end
    table.sort(locations, function(a, b)
        if a.count ~= b.count then return a.count < b.count end
        if a.inventory ~= b.inventory then return a.inventory < b.inventory end
        return a.slot < b.slot
    end)
    local moved, lastError = 0, nil
    for _, loc in ipairs(locations) do
        if moved >= requested then break end
        local source = devices[loc.inventory]
        if source then
            for _, output in ipairs(outputs) do
                if moved >= requested then break end
                local n, err = moveSlot(source, loc.slot, output, key, requested - moved)
                moved = moved + n
                if err then lastError = err end
                if n == 0 and err then break end
            end
        end
    end
    local result = { moved = moved, requested = requested }
    if moved < requested then
        result.error = lastError or (moved >= entry.count and "Estoque insuficiente"
            or "Bau de saida cheio ou inacessivel")
    end
    return result
end

-- Recolhe os itens de todos os baus de entrada para o armazenamento. `limit` permite
-- ao daemon fazer lotes pequenos sem prender a interface do computador por muito tempo.
function storage.deposit(config, limit)
    local cap = limit == nil and math.huge or tonumber(limit)
    if not cap or cap < 0 then return { moved = 0, error = "Limite invalido" } end
    cap = math.floor(cap)
    local _, devices = build(config)
    local inputs = liveDevices(devices, "input")
    if #inputs == 0 then return { moved = 0, error = "Configure um bau de entrada conectado" } end
    local stores = liveDevices(devices, "storage")
    if #stores == 0 then return { moved = 0, error = "Nenhum bau de armazenamento disponivel" } end
    local moved, lastError, pending = 0, nil, 0
    for _, input in ipairs(inputs) do
        local slots = {}
        for slot, item in pairs(input.list) do
            if type(slot) == "number" and type(item) == "table"
                and type(item.name) == "string" and type(item.count) == "number" and item.count > 0 then
                slots[#slots + 1] = slot
                pending = pending + item.count
            end
        end
        table.sort(slots)
        for _, slot in ipairs(slots) do
            if moved >= cap then break end
            local current, currentErr = readList(input)
            current = current and current[slot]
            if current and type(current.name) == "string" then
                local key = stackKey(current)
                rankStores(stores, key)
                for _, store in ipairs(stores) do
                    if moved >= cap then break end
                    local n, err = moveSlot(input, slot, store, key, cap - moved)
                    moved = moved + n
                    if err then lastError = err end
                    -- Ordem e ocupacao podem ter mudado; nunca confiar no indice anterior.
                    local refreshed = readList(store)
                    if refreshed then store.list = refreshed end
                    local remaining = readList(input)
                    local stack = remaining and remaining[slot]
                    if not stack or stackKey(stack) ~= key then break end
                end
            elseif currentErr then
                lastError = currentErr
            end
        end
        if moved >= cap then break end
    end
    local result = { moved = moved }
    if moved < math.min(cap, pending) then
        result.error = lastError or "Armazenamento cheio ou inacessivel"
    end
    return result
end

return storage
