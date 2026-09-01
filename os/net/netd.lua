-- Rede local entre computadores Mosaic (rednet, via modem com fio ou sem fio).
-- Roda como servico oculto. Responde a pedidos de outros computadores e permite
-- descobrir quem esta na rede. Comandos que mudam algo exigem a senha
-- (mosaic.net.password); sem senha configurada, so respondemos consultas.
local log = mosaic.lib("log").open("netd")

local PROTOCOL = "mosaic"
local nome = settings.get("mosaic.net.name") or os.getComputerLabel() or ("pc" .. os.getComputerID())
local senha = settings.get("mosaic.net.password")

local function openModem()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then rednet.open(side) end
            return side
        end
    end
    return nil
end

local side = openModem()
if not side then
    log:warn("nenhum modem conectado; servico em espera")
end
if side then
    rednet.host(PROTOCOL, nome)
    log:info("rede aberta em", side, "como", nome)
end

-- Estado exposto para o app Rede.
local peers = {}
mosaic.netStatus = function()
    return { side = side, name = nome, protected = senha ~= nil and senha ~= "", peers = peers }
end

-- Procura outros computadores Mosaic. Bloqueia por ate 1s.
mosaic.netScan = function()
    if not side then return {} end
    local found = { rednet.lookup(PROTOCOL) }
    peers = {}
    for _, id in ipairs(found) do
        if type(id) == "number" and id ~= os.getComputerID() then peers[#peers + 1] = { id = id } end
    end
    return peers
end

local function autorizado(msg)
    if not senha or senha == "" then return false, "este computador nao aceita comandos remotos (sem senha configurada)" end
    if msg.password ~= senha then return false, "senha incorreta" end
    return true
end

local handlers = {}

function handlers.ping()
    return { name = nome, id = os.getComputerID(), label = os.getComputerLabel(),
        os = mosaic.version.name .. " " .. mosaic.version.version, uptime = os.clock() }
end

function handlers.info()
    local hal = mosaic.lib("hal")
    return { name = nome, id = os.getComputerID(), free = fs.getFreeSpace("/"),
        peripherals = hal.list(), procs = #mosaic.list(), day = os.day(), time = os.time() }
end

function handlers.chat(msg, from)
    mosaic.notify("[" .. tostring(msg.from or from) .. "] " .. tostring(msg.text), 8)
    return { received = true }
end

function handlers.exec(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    local env = setmetatable({}, { __index = _G })
    local buffer = {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        buffer[#buffer + 1] = table.concat(parts, "\t")
    end
    local fn, lerr = load(msg.code or "", "=rednet", "t", env)
    if not fn then return nil, "erro de sintaxe: " .. tostring(lerr) end
    local res = table.pack(pcall(fn))
    if not res[1] then return nil, tostring(res[2]) end
    local values = {}
    for i = 2, res.n do values[#values + 1] = tostring(res[i]) end
    return { output = table.concat(buffer, "\n"), returns = values }
end

function handlers.launch(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    if not fs.exists(msg.path) then return nil, "arquivo nao encontrado" end
    return { pid = mosaic.launch(msg.path) }
end

function handlers.notify(msg)
    mosaic.notify(tostring(msg.text), tonumber(msg.secs))
    return { shown = true }
end

function handlers.sendFile(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    local path = msg.path or ("/home/recebido_" .. os.epoch("utc") .. ".txt")
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w")
    if not h then return nil, "nao consegui escrever" end
    h.write(msg.content or "")
    h.close()
    mosaic.notify("Arquivo recebido: " .. path, 6)
    return { path = path, size = #(msg.content or "") }
end

function handlers.getFile(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    local h = fs.open(msg.path, "r")
    if not h then return nil, "nao consegui ler " .. tostring(msg.path) end
    local content = h.readAll()
    h.close()
    return { path = msg.path, content = content }
end

function handlers.shutdown(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    os.queueEvent("netd_shutdown")
    return { ok = true }
end

-- ---------------------------------------------------------------- loop
while true do
    local ev = table.pack(os.pullEventRaw())
    local name = ev[1]

    if name == "rednet_message" then
        local from, msg, protocol = ev[2], ev[3], ev[4]
        if protocol == PROTOCOL and type(msg) == "table" and msg.type then
            local handler = handlers[msg.type]
            if handler then
                local ok, result, err = pcall(handler, msg, from)
                if not ok then
                    rednet.send(from, { id = msg.id, ok = false, error = tostring(result) }, PROTOCOL)
                elseif result == nil then
                    rednet.send(from, { id = msg.id, ok = false, error = tostring(err) }, PROTOCOL)
                else
                    rednet.send(from, { id = msg.id, ok = true, result = result }, PROTOCOL)
                end
            end
        end

    elseif name == "peripheral" or name == "peripheral_detach" then
        if not side or not rednet.isOpen(side) then
            side = openModem()
            if side then
                rednet.host(PROTOCOL, nome)
                log:info("modem reconectado em", side)
            end
        end

    elseif name == "netd_shutdown" then
        os.shutdown()

    elseif name == "terminate" then
        -- servico nao morre por Ctrl+T
    end
end
