-- Conversa entre computadores Mosaic: o protocolo, o pedido/resposta e a varredura.
--
--   local netx = mosaic.lib("netx")
--   local info = netx.ask(7, { type = "ping" })          -- um computador
--   local todos = netx.askAll({ type = "ping" })         -- a rede inteira, num prazo so'
--
-- Isto existia copiado em tres lugares: `PROTOCOL = "mosaic"` no netd, no netcenter e no
-- remote, e a funcao `ask` duas vezes, com prazos diferentes (3 s num, 5 s no outro).
--
-- O que a documentacao do CC diz e vale repetir aqui, porque muda o desenho:
--
--   * `rednet.send` devolver `true` **nao garante que a mensagem chegou**, e nao ha ordem
--     garantida. Entao toda troca e' pedido/resposta com prazo, e nada depende de uma
--     mensagem unica chegar. Quem nao responde nao esta necessariamente morto.
--   * qualquer computador pode **fingir ser outro**. A correlacao confere o remetente junto
--     do numero do pedido, e comando que muda alguma coisa exige senha.
local netx = {}

netx.PROTOCOL = "mosaic"

-- Prazos padrao, num lugar so'. Cinco segundos para uma pergunta a um computador (que pode
-- estar executando algo), um e meio para varrer a rede (todo mundo responde de imediato).
netx.PRAZO = 5
netx.PRAZO_VARREDURA = 1.5

-- ---------------------------------------------------------------- identidade

-- Numero do pedido, unico.
--
-- Antes era `os.epoch("utc")` sozinho. Dois pedidos no mesmo milissegundo saem com o mesmo
-- numero, e ai a resposta de um casa com a espera do outro — raro, e por isso do tipo de bug
-- que aparece uma vez por semana e ninguem reproduz. O contador tira a duvida, e o id do
-- computador na frente evita que dois computadores gerem o mesmo numero.
local contador = 0
function netx.newId()
    contador = contador + 1
    return os.getComputerID() .. "-" .. os.epoch("utc") .. "-" .. contador
end

-- Nome e senha sao lidos AGORA, a cada chamada, e nao guardados numa variavel local no
-- comeco do programa. O netd lia a senha uma vez no boot: trocar a senha em Configuracoes
-- nao fazia efeito nenhum ate' reiniciar o computador, e nada na tela dizia isso.
function netx.name()
    return settings.get("mosaic.net.name") or os.getComputerLabel() or ("pc" .. os.getComputerID())
end

function netx.password()
    local s = settings.get("mosaic.net.password")
    if s == "" then return nil end
    return s
end

-- ---------------------------------------------------------------- modem

-- Todos os modems ligados, com o que cada um e'.
function netx.modems()
    local out = {}
    for _, s in ipairs(peripheral.getNames()) do
        if peripheral.getType(s) == "modem" then
            local m = peripheral.wrap(s)
            local semFio = false
            if m and m.isWireless then
                local ok, v = pcall(m.isWireless)
                semFio = ok and v or false
            end
            out[#out + 1] = { side = s, wireless = semFio }
        end
    end
    return out
end

-- Abre TODOS os modems, nao o primeiro que aparecer.
--
-- Medido no servidor: o computador do reator tem DOIS modems — um sem fio embaixo e um com
-- fio atras. Abrir "o primeiro" e' escolher no escuro, porque a ordem do `getNames` nao e'
-- promessa nenhuma: bastava a ordem mudar para o servico passar a ouvir a rede errada. Num
-- cluster com turtle sem fio no campo e computador de cabo na base, metade da frota ficaria
-- inalcancavel sem nenhum erro na tela.
--
-- O rednet aceita varios modems abertos ao mesmo tempo: a mensagem entra por qualquer um e
-- sai por todos.
function netx.open()
    local abertos = {}
    for _, m in ipairs(netx.modems()) do
        if not rednet.isOpen(m.side) then pcall(rednet.open, m.side) end
        if rednet.isOpen(m.side) then abertos[#abertos + 1] = m.side end
    end
    return abertos[1], abertos
end

-- O primeiro modem, para quem so' precisa saber se existe algum.
function netx.side()
    local m = netx.modems()[1]
    return m and m.side or nil
end

-- ---------------------------------------------------------------- perguntar

-- Junta a senha no pedido quando ha uma. Comando que muda algo precisa dela; consulta nao.
function netx.assina(msg)
    local s = netx.password()
    if s then msg.password = s end
    return msg
end

-- Pergunta a UM computador e espera a resposta dele.
--
-- Descarta o que nao for a resposta esperada em vez de desistir: numa rede com varios
-- computadores conversando, a primeira mensagem que chega quase nunca e' a sua.
function netx.ask(id, msg, prazo)
    if not netx.open() then return nil, "sem modem neste computador" end
    msg.id = msg.id or netx.newId()
    rednet.send(id, msg, netx.PROTOCOL)

    local fim = os.clock() + (prazo or netx.PRAZO)
    while true do
        local resto = fim - os.clock()
        if resto <= 0 then break end
        local from, reply = rednet.receive(netx.PROTOCOL, resto)
        if from == nil then break end
        -- Remetente E numero do pedido. So' o numero nao basta: outro computador pode
        -- responder no lugar, de propOsito ou por engano.
        if from == id and type(reply) == "table" and reply.id == msg.id then
            if reply.ok then return reply.result or true end
            return nil, reply.error or "erro sem descricao"
        end
    end
    return nil, "sem resposta do computador #" .. tostring(id)
end

-- Pergunta a REDE INTEIRA e colhe todas as respostas dentro de UM prazo.
--
-- Isto substitui o `rednet.lookup` seguido de uma pergunta por vizinho, que era como o app
-- Rede procurava: um segundo para cada um, em fila. Com dez computadores a tela ficava dez
-- segundos parada. Aqui sai uma transmissao so' e todo mundo responde ao mesmo tempo.
--
-- Devolve uma lista { { id, ok, result, error } } ordenada por id — ordenada porque a lista
-- da tela nao pode dancar de posicao a cada varredura.
function netx.askAll(msg, prazo)
    if not netx.open() then return {} end
    msg.id = netx.newId()
    rednet.broadcast(msg, netx.PROTOCOL)

    local fim = os.clock() + (prazo or netx.PRAZO_VARREDURA)
    local vistos, saida = {}, {}
    while true do
        local resto = fim - os.clock()
        if resto <= 0 then break end
        local from, reply = rednet.receive(netx.PROTOCOL, resto)
        if from == nil then break end
        if type(reply) == "table" and reply.id == msg.id and not vistos[from] then
            vistos[from] = true
            saida[#saida + 1] = { id = from, ok = reply.ok == true,
                                  result = reply.result, error = reply.error }
        end
    end
    table.sort(saida, function(a, b) return a.id < b.id end)
    return saida
end

-- Quem esta na rede, com o que o `ping` do netd devolve. Uma transmissao, um prazo.
function netx.peers(prazo)
    local out = {}
    for _, r in ipairs(netx.askAll({ type = "ping" }, prazo)) do
        if r.ok and type(r.result) == "table" then
            local p = r.result
            out[#out + 1] = { id = r.id, name = p.name, label = p.label, os = p.os,
                              uptime = p.uptime }
        else
            -- Respondeu alguma coisa mas nao um ping valido: ainda esta vivo, e some da
            -- lista se for descartado aqui.
            out[#out + 1] = { id = r.id }
        end
    end
    return out
end

-- ---------------------------------------------------------------- self-check

function netx.demo()
    -- Numero de pedido nao repete, nem em sequencia no mesmo milissegundo.
    local a, b = netx.newId(), netx.newId()
    assert(a ~= b, "dois pedidos seguidos sairam com o mesmo numero: " .. a)

    -- Nome cai no rotulo ou no id quando nao ha nada configurado.
    assert(netx.name() ~= nil and netx.name() ~= "", "nome nunca pode ser vazio")

    -- Senha vazia conta como sem senha: settings guarda "" quando o campo e' limpo, e
    -- comparar com "" em cada lugar que usa seria esquecido em um deles.
    local antes = settings.get("mosaic.net.password")
    settings.set("mosaic.net.password", "")
    assert(netx.password() == nil, "senha vazia tinha de contar como sem senha")
    settings.set("mosaic.net.password", "abc")
    assert(netx.password() == "abc", "senha nao foi lida na hora")
    -- E a leitura e' na hora mesmo: trocar aqui vale na chamada seguinte, sem reiniciar.
    settings.set("mosaic.net.password", "xyz")
    assert(netx.password() == "xyz", "a senha ficou presa no valor antigo")
    local assinado = netx.assina({ type = "exec" })
    assert(assinado.password == "xyz", "assina() nao pos a senha no pedido")
    if antes == nil then settings.unset("mosaic.net.password")
    else settings.set("mosaic.net.password", antes) end

    -- Rede de mentira: um barramento em memoria no lugar do rednet, para exercitar a
    -- correlacao sem precisar de modem. Guarda o de verdade e devolve no fim.
    local real = rednet
    local fila = {}
    local eu = os.getComputerID()
    local function entrega(from, msg) fila[#fila + 1] = { from, msg } end
    rednet = {
        isOpen = function() return true end,
        open = function() end,
        send = function(id, msg) entrega(id, msg) return true end,
        broadcast = function(msg) entrega(-1, msg) end,
        receive = function(_, _)
            local item = table.remove(fila, 1)
            if not item then return nil end
            return item[1], item[2]
        end,
    }
    -- O `open` percorre `netx.modems`, entao o modem tambem e' de mentira aqui.
    local modemsReal, sideReal = netx.modems, netx.side
    netx.modems = function() return { { side = "fake", wireless = true } } end
    netx.side = function() return "fake" end

    -- Resposta do computador certo, com o numero certo: chega.
    local pedido = { type = "ping" }
    fila = {}
    rednet.send = function(_, msg) fila[#fila + 1] = { 7, { id = msg.id, ok = true, result = { name = "sete" } } } end
    local r1 = netx.ask(7, pedido, 1)
    assert(r1 and r1.name == "sete", "a resposta boa nao passou")

    -- Resposta do computador ERRADO com o numero certo: ignorada. E' o caso do computador
    -- que finge ser outro, que a documentacao do CC avisa que e' possivel.
    fila = {}
    rednet.send = function(_, msg)
        fila[#fila + 1] = { 99, { id = msg.id, ok = true, result = { name = "impostor" } } }
    end
    local r2, e2 = netx.ask(7, { type = "ping" }, 0.2)
    assert(r2 == nil and e2, "resposta de outro computador nao podia ser aceita")

    -- Numero de pedido errado, remetente certo: tambem ignorado (resposta atrasada de uma
    -- pergunta anterior).
    fila = {}
    rednet.send = function(_, _)
        fila[#fila + 1] = { 7, { id = "velho", ok = true, result = { name = "atrasado" } } }
    end
    local r3 = netx.ask(7, { type = "ping" }, 0.2)
    assert(r3 == nil, "resposta atrasada de outro pedido nao podia ser aceita")

    -- Erro do outro lado vira segundo retorno, nao excecao.
    fila = {}
    rednet.send = function(_, msg) fila[#fila + 1] = { 7, { id = msg.id, ok = false, error = "sem senha" } } end
    local r4, e4 = netx.ask(7, { type = "exec" }, 1)
    assert(r4 == nil and e4 == "sem senha", "o erro do outro lado nao chegou: " .. tostring(e4))

    -- askAll: colhe todos, ignora o repetido, e devolve em ordem de id.
    fila = {}
    rednet.broadcast = function(msg)
        fila[#fila + 1] = { 12, { id = msg.id, ok = true, result = { name = "doze" } } }
        fila[#fila + 1] = { 3, { id = msg.id, ok = true, result = { name = "tres" } } }
        fila[#fila + 1] = { 12, { id = msg.id, ok = true, result = { name = "doze de novo" } } }
        fila[#fila + 1] = { 8, { id = "outro pedido", ok = true, result = {} } }
    end
    local todos = netx.askAll({ type = "ping" }, 1)
    assert(#todos == 2, "deviam ser dois computadores distintos, deu " .. #todos)
    assert(todos[1].id == 3 and todos[2].id == 12, "a lista tem de sair ordenada por id")
    assert(todos[1].result.name == "tres", "resposta trocada entre computadores")

    -- Ninguem responde: lista vazia, e sem travar.
    fila = {}
    rednet.broadcast = function() end
    assert(#netx.askAll({ type = "ping" }, 0.2) == 0, "sem resposta tinha de dar lista vazia")

    -- open() abre TODOS os modems, nao so' o primeiro. Dois modems num computador e' o
    -- caso real do servidor (sem fio embaixo, com fio atras), e abrir um so' deixaria
    -- metade da rede muda.
    local abertosFake = {}
    rednet.isOpen = function(s) return abertosFake[s] == true end
    rednet.open = function(s) abertosFake[s] = true end
    netx.modems = function()
        return { { side = "bottom", wireless = true }, { side = "back", wireless = false } }
    end
    local primeiro, todosModems = netx.open()
    assert(#todosModems == 2, "open() tinha de abrir os dois modems, abriu " .. #todosModems)
    assert(primeiro == "bottom", "o primeiro devolvido tem de ser o primeiro da lista")
    assert(abertosFake["back"] and abertosFake["bottom"], "faltou abrir um dos modems")

    rednet = real
    netx.modems, netx.side = modemsReal, sideReal
    assert(eu == os.getComputerID(), "o teste nao pode mexer na identidade do computador")
    return true
end

return netx
