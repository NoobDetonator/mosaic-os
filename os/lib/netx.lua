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

-- ---------------------------------------------------------------- assinatura
--
-- A senha NAO viaja. Antes ela ia dentro da mensagem, em texto claro, e a batida de ponto
-- do cluster era por TRANSMISSAO quando nao havia mestre configurado - ou seja, a senha do
-- computador saia difundida para a rede inteira, de cinco em cinco segundos. Qualquer
-- computador com um modem aberto a recolhia e virava dono da frota.
--
-- Agora vai uma ASSINATURA: HMAC-SHA1 do conteudo, com a senha como chave. Quem nao tem a
-- senha nao consegue produzir a assinatura, e quem escuta a rede nao aprende a senha.
--
-- Contra repeticao, duas travas, porque so' assinar nao basta: uma mensagem assinada
-- capturada hoje continuaria valida amanha.
--   * `t` - o relogio. Todo computador do mesmo servidor le' o mesmo os.epoch("utc"), entao
--     a janela pode ser curta sem risco de desencontro.
--   * `id` - o numero do pedido, guardado ate' sair da janela. Repetiu, recusa.
--
-- E a assinatura cobre `de`, conferido contra o remetente que o rednet informa: sem isso
-- daria para pegar a mensagem de outro computador e reenviar como se fosse sua.
--
-- O sha1 mora no lib/update porque o instalador roda ANTES do sistema existir e precisa ser
-- autossuficiente - ele nao pode dar require em nada. Melhor importar de la' do que ter uma
-- segunda copia de 40 linhas de SHA-1 no repositorio.
netx.JANELA = 60          -- segundos de tolerancia entre o relogio de quem manda e de quem le

local BLOCO = 64          -- tamanho de bloco do SHA-1, para o HMAC

local function bin(hex)
    return (hex:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

local function almofada(chave, valor)
    local out = {}
    for i = 1, BLOCO do out[i] = string.char(bit32.bxor(chave:byte(i) or 0, valor)) end
    return table.concat(out)
end

function netx.hmac(segredo, texto)
    local sha1 = require("lib.update").sha1
    local k = segredo
    if #k > BLOCO then k = bin(sha1(k)) end
    return sha1(almofada(k, 0x5c) .. bin(sha1(almofada(k, 0x36) .. texto)))
end

-- Texto deterministico da mensagem. `pairs` devolve ordem diferente a cada chamada, entao
-- assinar o resultado de um serializador qualquer daria assinaturas diferentes para a MESMA
-- mensagem. As chaves vao ordenadas, e o tipo entra junto do valor para que o numero 1 e a
-- string "1" nao produzam o mesmo texto.
local function canon(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local ks = {}
    for k in pairs(v) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(ks) do
        if k ~= "mac" then out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Pedidos ja aceitos, para recusar repeticao. Some sozinho ao sair da janela: guardar para
-- sempre seria vazamento de memoria num servico que nao reinicia.
local vistos = {}
local function repetido(id, agora)
    for k, t in pairs(vistos) do
        if agora - t > netx.JANELA * 1000 then vistos[k] = nil end
    end
    if vistos[id] then return true end
    vistos[id] = agora
    return false
end

-- Assina o pedido. Sem senha configurada nao assina - e do outro lado o `confere` recusa,
-- que e' o mesmo comportamento de antes: sem senha, o computador so' responde consulta.
-- `segredo` opcional: o terminal remoto e o Centro de Rede pedem a senha DO OUTRO
-- computador a quem esta usando, e e' com ela que o pedido tem de ser assinado - nao com a
-- senha deste computador aqui, que o outro lado nem conhece.
function netx.assina(msg, segredo)
    msg.password = nil        -- nunca mais; se algo ainda puser, some aqui
    msg.id = msg.id or netx.newId()
    segredo = segredo or netx.password()
    if not segredo then return msg end
    msg.de = os.getComputerID()
    msg.t = os.epoch("utc")
    msg.mac = netx.hmac(segredo, canon(msg))
    return msg
end

-- Confere a assinatura. Devolve false e o motivo, para a mensagem chegar a quem pediu.
function netx.confere(msg, from)
    local segredo = netx.password()
    if not segredo then
        return false, "este computador nao aceita comandos remotos (sem senha configurada)"
    end
    if type(msg) ~= "table" or type(msg.mac) ~= "string" then
        return false, "pedido sem assinatura (o outro computador esta com Mosaic antigo?)"
    end
    if msg.de ~= from then return false, "remetente nao confere" end
    local t = tonumber(msg.t)
    local agora = os.epoch("utc")
    if not t or math.abs(agora - t) > netx.JANELA * 1000 then
        return false, "pedido fora da janela de tempo"
    end
    -- Conferir a assinatura ANTES de anotar o id: senao qualquer um enche a lista de
    -- repetidos com pedidos inventados e derruba os de verdade.
    if netx.hmac(segredo, canon(msg)) ~= msg.mac then return false, "assinatura invalida" end
    if repetido(msg.id, agora) then return false, "pedido repetido" end
    return true
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
    -- VALOR CONHECIDO, e nao so' coerencia interna. Uma implementacao errada de sha1 assina
    -- e confere com ela mesma sem reclamar de nada - foi exatamente o que aconteceu no
    -- emulador, cujo bit32.bxor aceitava dois argumentos e ignorava o resto calado. Estes
    -- numeros vem do FIPS 180-1 e do RFC 2202; se um dia baterem diferente, o hash quebrou.
    local sha1 = require("lib.update").sha1
    assert(sha1("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d", "sha1('abc') errado")
    assert(sha1("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709", "sha1('') errado")
    assert(netx.hmac("Jefe", "what do ya want for nothing?")
        == "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", "HMAC do RFC 2202 caso 2 errado")
    assert(netx.hmac(string.rep(string.char(0x0b), 20), "Hi There")
        == "b617318655057264e28bc0b6fb378c8ef146be00", "HMAC do RFC 2202 caso 1 errado")
    -- Chave maior que o bloco de 64 tem de passar por sha1 antes; e' o ramo que costuma
    -- ficar sem teste, e uma senha longa cai justamente nele.
    assert(netx.hmac(string.rep("k", 80), "teste")
        == "c2864c16a0b76b76004c55a4d5b84e01a8ce1d79", "HMAC com chave longa errado")

    -- A SENHA NAO PODE SAIR NA MENSAGEM. Este era o buraco: ela ia em texto claro, e a
    -- batida do cluster saia por transmissao para a rede inteira levando ela junto.
    local eu0 = os.getComputerID()
    local assinado = netx.assina({ type = "exec" })
    assert(assinado.password == nil, "a senha vazou dentro do pedido")
    assert(type(assinado.mac) == "string" and #assinado.mac == 40, "faltou a assinatura")
    assert(netx.confere(assinado, eu0) == true, "a propria assinatura nao foi aceita")

    -- Mexeu no conteudo, a assinatura cai.
    local mexido = {}
    for k, v in pairs(assinado) do mexido[k] = v end
    mexido.type = "shutdown"
    mexido.id = netx.newId()
    assert(netx.confere(mexido, eu0) == false, "aceitou pedido adulterado")

    -- Repetir o MESMO pedido nao vale duas vezes: sem isto, gravar uma mensagem da rede e
    -- reenviar depois seria suficiente para mandar no computador dos outros.
    assert(netx.confere(assinado, eu0) == false, "aceitou o mesmo pedido duas vezes")

    -- Fingir ser outro remetente nao cola: o `de` entra na assinatura.
    local outro = netx.assina({ type = "exec" })
    assert(netx.confere(outro, eu0 + 1) == false, "aceitou pedido de remetente trocado")

    -- Pedido velho nao vale: assinatura capturada hoje nao serve amanha.
    local velhoPedido = netx.assina({ type = "exec" })
    velhoPedido.t = velhoPedido.t - (netx.JANELA + 5) * 1000
    assert(netx.confere(velhoPedido, eu0) == false, "aceitou pedido fora da janela de tempo")

    -- Segredo diferente, assinatura diferente: e' o caso do terminal remoto, que assina com
    -- a senha do computador de destino.
    local comOutroSegredo = netx.assina({ type = "exec" }, "senha-do-outro")
    assert(netx.confere(comOutroSegredo, eu0) == false, "assinatura com outra senha foi aceita")
    assert(netx.hmac("chave", "abc") ~= netx.hmac("chave2", "abc"), "hmac ignorou a chave")
    assert(#netx.hmac("chave", "abc") == 40, "hmac devia sair em 40 hex")
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
