-- Cliente do relay: conecta por websocket a um servidor fora do jogo (relay/relay.js)
-- para que voce (ou uma IA) possa controlar este computador de qualquer lugar.
-- Roda como servico oculto. Protocolo documentado em /os/docs/protocolo-relay.md.
local log = mosaic.lib("log").open("relay")
local strutil = mosaic.lib("strutil")

local URL = settings.get("mosaic.relay.url")
local TOKEN = settings.get("mosaic.relay.token")
local FORWARD = settings.get("mosaic.relay.events") or {}
local MAX_MSG = 48 * 1024

if not URL or URL == "" then
    log:warn("sem mosaic.relay.url; servico encerrado")
    return
end
if not http then
    log:error("API http desativada no servidor")
    mosaic.notify("Relay: a API http esta desativada neste servidor", 8)
    return
end

local forward = {}
for _, name in ipairs(FORWARD) do forward[name] = true end

local ws                    -- handle aberto, ou nil
local backoff = 1
local reconnectTimer
local jobs = {}             -- procId -> { id = reqId, win = window, rows = n }
local status = { connected = false, since = os.clock(), sent = 0, received = 0, error = nil }

mosaic.relayStatus = function() return status end

-- ---------------------------------------------------------------- envio
local function send(tbl)
    if not ws then return false end
    local ok, body = pcall(textutils.serialiseJSON, tbl)
    if not ok then
        log:error("nao consegui serializar", body)
        return false
    end
    if #body > MAX_MSG then
        body = textutils.serialiseJSON({ id = tbl.id, ok = false, error = "resposta grande demais (" .. #body .. " bytes)" })
    end
    local sent = pcall(ws.send, body)
    if sent then status.sent = status.sent + 1 end
    return sent
end

local function reply(id, ok, value)
    if id == nil then return end
    if ok then send({ id = id, ok = true, result = value })
    else send({ id = id, ok = false, error = tostring(value) }) end
end

-- ---------------------------------------------------------------- handlers
-- Cada handler devolve (resultado) ou dispara erro; nil = resposta enviada depois (assincrona).
local handlers = {}

function handlers.ping() return { pong = true, uptime = os.clock() } end

function handlers.info()
    return {
        id = os.getComputerID(),
        label = os.getComputerLabel(),
        host = _HOST,
        os = mosaic.version.name .. " " .. mosaic.version.version,
        screen = { w = mosaic.wm.W, h = mosaic.wm.H },
        free = fs.getFreeSpace("/"),
        uptime = os.clock(),
        day = os.day(),
        time = os.time(),
        peripherals = mosaic.lib("hal").list(),
    }
end

-- Executa codigo Lua e devolve o que foi impresso + os valores retornados.
function handlers.exec(msg)
    local buffer = {}
    local env = setmetatable({}, { __index = _G })
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        buffer[#buffer + 1] = table.concat(parts, "\t")
    end
    env.write = function(s) buffer[#buffer + 1] = tostring(s) end
    env.printError = env.print
    local fn, err = load(msg.code or "", "=relay", "t", env)
    if not fn then error("erro de sintaxe: " .. tostring(err), 0) end
    local res = table.pack(pcall(fn))
    if not res[1] then error(tostring(res[2]), 0) end
    local values = {}
    for i = 2, res.n do
        local v = res[i]
        values[#values + 1] = type(v) == "table" and textutils.serialise(v) or tostring(v)
    end
    return { output = table.concat(buffer, "\n"), returns = values }
end

-- Roda um comando do shell numa janela invisivel e devolve o texto da tela.
function handlers.shell(msg)
    local cols = math.min(tonumber(msg.cols) or 51, 120)
    local rows = math.min(tonumber(msg.rows) or 19, 50)
    local win = window.create(mosaic.wm.canvas, 1, 1, cols, rows, false)
    local p = mosaic.proc.runCommand(msg.cmd or "", {
        hidden = true, term = win, title = "relay:" .. tostring(msg.cmd), holdOnError = false,
    })
    jobs[p.id] = { id = msg.id, win = win, rows = rows, deadline = os.clock() + (tonumber(msg.timeout) or 10) }
    -- resposta enviada quando o processo terminar (ou por timeout no loop principal)
    return nil, true
end

function handlers.screenshot()
    local shot = mosaic.screenshot()
    local lines = {}
    for y = 1, shot.h do
        lines[y] = { text = shot.lines[y][1], fg = shot.lines[y][2], bg = shot.lines[y][3] }
    end
    return { w = shot.w, h = shot.h, lines = lines }
end

function handlers.ps() return mosaic.list() end

function handlers.kill(msg)
    if not mosaic.kill(tonumber(msg.pid)) then error("processo nao encontrado", 0) end
    return true
end

function handlers.launch(msg)
    if not fs.exists(msg.path) then error("arquivo nao encontrado: " .. tostring(msg.path), 0) end
    return { pid = mosaic.launch(msg.path, table.unpack(msg.args or {})) }
end

function handlers.notify(msg)
    mosaic.notify(tostring(msg.text), tonumber(msg.secs))
    return true
end

-- Injeta um evento no computador (permite digitar/clicar remotamente).
function handlers.inject(msg)
    os.queueEvent(tostring(msg.name), table.unpack(msg.args or {}))
    return true
end

handlers["fs.read"] = function(msg)
    local h = fs.open(msg.path, "r")
    if not h then error("nao consegui abrir " .. tostring(msg.path), 0) end
    local data = h.readAll()
    h.close()
    if #data > MAX_MSG then error("arquivo grande demais (" .. strutil.bytes(#data) .. ")", 0) end
    return { path = msg.path, content = data, size = #data }
end

handlers["fs.write"] = function(msg)
    local dir = fs.getDir(msg.path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(msg.path, "w")
    if not h then error("nao consegui escrever em " .. tostring(msg.path), 0) end
    h.write(msg.content or "")
    h.close()
    return { path = msg.path, size = #(msg.content or "") }
end

handlers["fs.list"] = function(msg)
    local path = msg.path or "/"
    if not fs.isDir(path) then error("nao e uma pasta: " .. path, 0) end
    local out = {}
    for _, name in ipairs(fs.list(path)) do
        local p = fs.combine(path, name)
        out[#out + 1] = { name = name, path = "/" .. p, isDir = fs.isDir(p), size = fs.isDir(p) and 0 or fs.getSize(p) }
    end
    return { path = path, entries = out }
end

handlers["fs.delete"] = function(msg)
    if not fs.exists(msg.path) then error("nao existe: " .. tostring(msg.path), 0) end
    if fs.isReadOnly(msg.path) then error("somente leitura: " .. tostring(msg.path), 0) end
    fs.delete(msg.path)
    return true
end

handlers["fs.mkdir"] = function(msg) fs.makeDir(msg.path) return true end

function handlers.reboot() os.queueEvent("relay_reboot") return true end
function handlers.shutdown() os.queueEvent("relay_shutdown") return true end

-- ---------------------------------------------------------------- conexao
local function connect()
    log:info("conectando em", URL)
    local headers = { ["User-Agent"] = "MosaicOS/" .. mosaic.version.version }
    if TOKEN and TOKEN ~= "" then headers["Authorization"] = "Bearer " .. TOKEN end
    http.websocketAsync(URL, headers)
end

local function scheduleReconnect()
    reconnectTimer = os.startTimer(backoff)
    log:info("reconectando em", backoff .. "s")
    backoff = math.min(backoff * 2, 60)
end

local function onMessage(body)
    status.received = status.received + 1
    local ok, msg = pcall(textutils.unserialiseJSON, body)
    if not ok or type(msg) ~= "table" then
        log:warn("mensagem invalida")
        return
    end
    local handler = handlers[msg.type]
    if not handler then
        reply(msg.id, false, "comando desconhecido: " .. tostring(msg.type))
        return
    end
    local res = table.pack(pcall(handler, msg))
    if not res[1] then
        reply(msg.id, false, res[2])
    elseif res[3] == true then
        -- resposta assincrona (ex: shell); nada a fazer agora
    else
        reply(msg.id, true, res[2])
    end
end

local function finishJob(pid)
    local job = jobs[pid]
    if not job then return end
    jobs[pid] = nil
    local out = {}
    for y = 1, job.rows do
        local ok, text = pcall(job.win.getLine, y)
        out[y] = ok and (text:gsub("%s+$", "")) or ""
    end
    while #out > 0 and out[#out] == "" do table.remove(out) end
    reply(job.id, true, { output = table.concat(out, "\n") })
end

-- ---------------------------------------------------------------- loop
connect()
local sweep = os.startTimer(5)
mosaic.notify("Relay: conectando...")

while true do
    local ev = table.pack(os.pullEventRaw())
    local name = ev[1]

    if name == "websocket_success" and ev[2] == URL then
        ws = ev[3]
        backoff = 1
        status.connected = true
        status.since = os.clock()
        status.error = nil
        log:info("conectado")
        mosaic.notify("Relay conectado")
        send({
            type = "hello", id = os.getComputerID(), label = os.getComputerLabel(),
            os = mosaic.version.name .. " " .. mosaic.version.version, host = _HOST,
            screen = { w = mosaic.wm.W, h = mosaic.wm.H },
        })
        mosaic.emit("relay_state", true)

    elseif name == "websocket_failure" and ev[2] == URL then
        ws = nil
        status.connected = false
        status.error = tostring(ev[3])
        log:warn("falha:", ev[3])
        mosaic.emit("relay_state", false)
        scheduleReconnect()

    elseif name == "websocket_closed" and ev[2] == URL then
        ws = nil
        status.connected = false
        status.error = "conexao fechada"
        log:warn("fechado")
        mosaic.emit("relay_state", false)
        scheduleReconnect()

    elseif name == "websocket_message" and ev[2] == URL then
        onMessage(ev[3])

    elseif name == "timer" and ev[2] == reconnectTimer then
        connect()

    elseif name == "timer" and ev[2] == sweep then
        sweep = os.startTimer(5)
        for pid, job in pairs(jobs) do
            if os.clock() > job.deadline then
                if mosaic.kill(pid) then log:warn("job", pid, "expirou") end
                finishJob(pid)
            end
        end

    elseif name == "proc_exit" then
        finishJob(ev[2])

    elseif name == "relay_reboot" then
        os.reboot()

    elseif name == "relay_shutdown" then
        os.shutdown()

    elseif name == "terminate" then
        -- servico nao morre por Ctrl+T

    elseif forward[name] and ws then
        local args = {}
        for i = 2, ev.n do
            local v = ev[i]
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then args[#args + 1] = v
            elseif t == "table" then args[#args + 1] = v
            else args[#args + 1] = tostring(v) end
        end
        send({ type = "event", name = name, args = args, at = os.epoch("utc") })
    end
end
