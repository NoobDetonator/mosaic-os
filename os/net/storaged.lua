-- Servico de armazenamento em rede. A janela so envia comandos; este processo
-- serializa todas as transferencias e mantem o catalogo vivo com a janela fechada.
local storage = mosaic.lib("storage")
local fsx = mosaic.lib("fsx")

local CONFIG_PATH = "/os/var/storage.json"
local SCAN_INTERVAL = 5
local AUTO_BATCH = 256
local VALID_ROLE = { input = true, output = true, storage = true, ignore = true }

local function loadConfig()
    local saved = fsx.readJSON(CONFIG_PATH, {})
    if type(saved) ~= "table" then saved = {} end
    local config = { roles = {}, autoDeposit = saved.autoDeposit ~= false }
    if type(saved.roles) == "table" then
        for name, role in pairs(saved.roles) do
            if type(name) == "string" and VALID_ROLE[role] then config.roles[name] = role end
        end
    end
    return config
end

local config = loadConfig()
local state = {
    ready = false, state = "setup", inventories = {}, items = {},
    totalItems = 0, usedSlots = 0, totalSlots = 0,
    busy = false, error = nil, activity = nil, lastScan = nil,
    config = config,
}

mosaic.storageStatus = function() return state end

local function publish()
    os.queueEvent("mosaic:storage_state")
end

local function scan(keepError)
    local ok, result = pcall(storage.scan, config)
    if not ok then
        state.error = "Falha ao ler os baus: " .. tostring(result)
        state.state = "error"
        state.ready = false
        publish()
        return false
    end
    if type(result) ~= "table" then
        state.error = "O catalogo retornou um estado invalido"
        state.state = "error"
        state.ready = false
        publish()
        return false
    end
    local priorError = keepError and state.error or nil
    state.input, state.output = nil, nil
    for k, v in pairs(result) do state[k] = v end
    state.error = result.error or priorError
    state.config = config
    state.lastScan = os.clock()
    state.ready = state.input ~= nil and state.output ~= nil and
        ((state.totalSlots or 0) > 0)
    state.state = result.error and "error" or (state.ready and "ready" or "setup")
    publish()
    return true
end

local function saveConfig()
    local ok, err = fsx.writeJSON(CONFIG_PATH, config)
    if not ok then state.error = "Nao consegui salvar a configuracao: " .. tostring(err) end
    return ok
end

local function operation(action, key, count, automatic)
    state.busy = true
    state.error = nil
    publish()
    local ok, result
    if action == "withdraw" then
        ok, result = pcall(storage.withdraw, config, key, count)
    else
        ok, result = pcall(storage.deposit, config, count)
    end
    state.busy = false
    if not ok then
        state.error = "Transferencia falhou: " .. tostring(result)
        state.activity = "Operacao interrompida"
    elseif type(result) ~= "table" then
        state.error = "Resposta invalida da transferencia"
    else
        local moved = tonumber(result.moved) or 0
        state.error = result.error
        if moved > 0 or not automatic then
            state.activity = action == "withdraw"
                and (moved .. " itens enviados para a saida")
                or (moved .. " itens guardados")
        end
    end
    scan(true)
    publish()
end

local function command(c)
    if type(c) ~= "table" then return end
    if c.action == "rescan" then
        state.error = nil
        scan()
    elseif c.action == "set_role" then
        if type(c.name) ~= "string" or c.name == "" then return end
        if c.role ~= "auto" and not VALID_ROLE[c.role] then return end
        if c.role == "input" or c.role == "output" then
            for name, role in pairs(config.roles) do
                if name ~= c.name and role == c.role then config.roles[name] = "ignore" end
            end
        end
        config.roles[c.name] = c.role == "auto" and nil or c.role
        state.error = nil
        saveConfig()
        scan(true)
    elseif c.action == "set_auto" then
        config.autoDeposit = c.enabled == true
        state.error = nil
        saveConfig()
        scan(true)
    elseif c.action == "withdraw" then
        operation("withdraw", c.key, c.count)
    elseif c.action == "deposit" then
        operation("deposit", nil, c.count)
    end
end

scan()
local timer = os.startTimer(SCAN_INTERVAL)
while true do
    local ev, arg = os.pullEvent()
    if ev == "mosaic:storage_cmd" then
        command(arg)
    elseif ev == "peripheral" or ev == "peripheral_detach" then
        scan()
    elseif ev == "timer" and arg == timer then
        timer = os.startTimer(SCAN_INTERVAL)
        scan()
        if config.autoDeposit and state.input and (state.inputItems or 0) > 0
            and (state.totalSlots or 0) > 0 then
            operation("deposit", nil, AUTO_BATCH, true)
        end
    end
end
