-- Rede local entre computadores Mosaic (rednet, via modem com fio ou sem fio).
-- Roda como servico oculto. Responde a pedidos de outros computadores e permite
-- descobrir quem esta na rede. Comandos que mudam algo exigem a senha
-- (mosaic.net.password); sem senha configurada, so respondemos consultas.
local log = mosaic.lib("log").open("netd")
local netx = mosaic.lib("netx")
local cluster = mosaic.lib("cluster")

local PROTOCOL = netx.PROTOCOL
local nome = netx.name()

local side = netx.open()
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
    return { side = side, name = nome, protected = netx.password() ~= nil, peers = peers }
end

-- Procura outros computadores Mosaic: UMA transmissao e um prazo so' para todo mundo
-- responder, em vez de um `lookup` seguido de uma pergunta por vizinho.
mosaic.netScan = function(prazo)
    if not side then return {} end
    peers = netx.peers(prazo)
    return peers
end

-- ---------------------------------------------------------------- cluster
--
-- UM daemon, nao dois. O `rednet_message` chega por difusao para todos os processos, entao
-- um segundo servico ouvindo o mesmo protocolo responderia o mesmo pedido duas vezes.
--
-- O no EMPURRA e o mestre nao pergunta. E' consequencia direta do chunk descarregado: no
-- que sai do ar nao avisa e nao pausa, ele simplesmente para; quando volta, volta batendo
-- ponto sozinho, e ninguem precisa ter percebido a ausencia.
local tabela = cluster.isMestre() and cluster.carrega() or cluster.tabela()
local mudouTabela = false

-- A frota, para o app do cluster desenhar. Calculada na hora, nunca guardada: "quem esta no
-- ar" depende do relogio, e um valor guardado envelhece calado.
mosaic.clusterNodes = function()
    local agora = os.epoch("utc")
    return tabela:lista(agora), cluster.role()
end

local function anota(id, batida)
    local agora = os.epoch("utc")
    local antes = tabela.nos[id]
    local eraNoAr = antes and tabela:noAr(antes, agora) or false
    local _, novo = tabela:registra(id, batida, agora)
    -- Grava em disco so' quando a FROTA muda, nao a cada batida: combustivel e tempo de
    -- atividade mudam toda vez, e escrever no disco a cada cinco segundos por no seria
    -- desgaste sem serventia. O que precisa sobreviver a um reinicio e' quem existe.
    if novo or not eraNoAr then mudouTabela = true end
end

-- A batida NAO pede senha quando o mestre nao tem uma: assim um no novo aparece na lista
-- sem configurar nada. Se o mestre tiver senha, a batida passa a exigi-la como qualquer
-- outro pedido — e ai ninguem enche a lista de no inventado.
local function recebeBatida(msg, from)
    if netx.password() and msg.password ~= netx.password() then
        return nil, "senha incorreta"
    end
    anota(from, msg.node or {})
    return { ok = true }
end

-- A senha e' lida AGORA, a cada pedido, e nao guardada numa variavel no comeco do servico.
-- Antes ela vinha de um `settings.get` no topo do arquivo: trocar a senha em Configuracoes
-- nao valia nada ate' reiniciar o computador, e nenhuma tela dizia isso.
local function autorizado(msg)
    local senha = netx.password()
    if not senha then
        return false, "este computador nao aceita comandos remotos (sem senha configurada)"
    end
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

function handlers.beat(msg, from)
    if not cluster.isMestre() then return nil, "este computador nao e' o mestre" end
    return recebeBatida(msg, from)
end

-- Quem sou eu no cluster. Serve para o app perguntar a um no sem depender do mestre.
function handlers.whoami()
    return { role = cluster.role(), group = cluster.group(), node = cluster.batida() }
end

function handlers.shutdown(msg)
    local ok, err = autorizado(msg)
    if not ok then return nil, err end
    os.queueEvent("netd_shutdown")
    return { ok = true }
end

-- ---------------------------------------------------------------- loop

-- A batida sai por transmissao quando nao ha mestre configurado, e direto quando ha. Assim
-- um no funciona sem configurar nada, e quem quiser cravar o mestre, crava.
local function bate()
    if not side then return end
    local corpo = netx.assina({ type = "beat", node = cluster.batida() })
    corpo.id = netx.newId()
    if cluster.isMestre() then
        -- O mestre tambem entra na propria lista: sem isso ele nao aparece no painel dele
        -- mesmo, e quem olha a tela fica sem saber onde esta.
        anota(os.getComputerID(), corpo.node)
    end
    local alvo = cluster.masterId()
    if alvo then rednet.send(alvo, corpo, PROTOCOL)
    elseif not cluster.isMestre() then rednet.broadcast(corpo, PROTOCOL) end
end

local batidaTimer = os.startTimer(cluster.INTERVALO)
bate()

while true do
    local ev = table.pack(os.pullEventRaw())
    local name = ev[1]

    -- Nome trocado em Configuracoes vale sem reiniciar: reanuncia com o nome novo.
    -- `settings.get` e' consulta a uma tabela, entao conferir a cada evento nao custa nada.
    if side then
        local atual = netx.name()
        if atual ~= nome then
            pcall(rednet.unhost, PROTOCOL)
            nome = atual
            rednet.host(PROTOCOL, nome)
            log:info("renomeado para", nome)
        end
    end

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
            side = netx.open()
            if side then
                rednet.host(PROTOCOL, nome)
                log:info("modem reconectado em", side)
            end
        end

    elseif name == "timer" and ev[2] == batidaTimer then
        batidaTimer = os.startTimer(cluster.INTERVALO)
        pcall(bate)
        if mudouTabela and cluster.isMestre() then
            mudouTabela = false
            pcall(function() tabela:salva() end)
        end

    elseif name == "netd_shutdown" then
        os.shutdown()

    elseif name == "terminate" then
        -- servico nao morre por Ctrl+T
    end
end
