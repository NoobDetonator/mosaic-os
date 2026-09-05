-- O cluster: papel, grupo, batida de ponto e a tabela de nos.
--
-- Aqui mora so' a REGRA, sem rede e sem disco no caminho: quem manda mensagem e' o netd,
-- quem desenha e' o app. Assim a parte que decide quem esta no ar da' para testar sem
-- levantar dois computadores.
--
--   local cluster = mosaic.lib("cluster")
--   cluster.role()            -- "mestre" ou "no"
--   cluster.batida()          -- o que este computador tem a dizer sobre si
--   local t = cluster.tabela()
--   t:registra(7, batida, agora)
--
-- O DESENHO INTEIRO sai de um fato do CC: quando ninguem esta por perto, o pedaco de mundo
-- descarrega e o computador **nao pausa** — ele perde o estado de execucao e volta para o
-- shell vazio. Entao:
--
--   * o no EMPURRA, o mestre nao pergunta. No que renasce simplesmente volta a bater ponto,
--     e ninguem precisa perceber que ele sumiu;
--   * a tabela do mestre vai para DISCO, senao reiniciar o mestre apaga a frota inteira;
--   * nada que importa fica so' na memoria.
local cluster = {}

-- De quantos em quantos segundos o no bate ponto, e quantas batidas perdidas contam como
-- fora do ar. Tres e' de proposito: uma perdida e' rede, duas e' azar, tres e' ausencia.
cluster.INTERVALO = 5
cluster.FALTAS = 3

cluster.ARQUIVO = "/os/var/cluster/nos.json"

-- ---------------------------------------------------------------- este computador

function cluster.role()
    local r = settings.get("mosaic.cluster.role")
    return (r == "mestre") and "mestre" or "no"
end

function cluster.isMestre() return cluster.role() == "mestre" end

function cluster.group()
    local g = settings.get("mosaic.cluster.group")
    if g == nil or g == "" then return "sem grupo" end
    return g
end

-- O id do mestre, quando configurado. Sem ele a batida sai por transmissao e qualquer
-- mestre na rede recolhe: um no funciona sem configurar nada, e quem quiser cravar, crava.
function cluster.masterId()
    local m = tonumber(settings.get("mosaic.cluster.master"))
    return m
end

-- Tipo sai do ambiente, nao de configuracao: configurar isso seria uma chance a mais de
-- ficar errado, e a resposta esta na frente.
function cluster.tipo()
    if turtle then return "turtle" end
    if pocket then return "pocket" end
    return "computador"
end

-- Combustivel de turtle. `getFuelLevel` devolve a string "unlimited" quando o servidor
-- desligou o consumo — nao e' numero, e comparar isso com um limite derruba o servico.
function cluster.combustivel()
    if not turtle then return nil end
    local ok, v = pcall(turtle.getFuelLevel)
    if not ok then return nil end
    if v == "unlimited" then return -1 end        -- -1 quer dizer "sem limite"
    return tonumber(v)
end

-- O que este computador tem a dizer sobre si. E' o corpo da batida de ponto.
function cluster.batida()
    local netx = require("lib.netx")
    local hal = require("lib.hal")
    local b = {
        name = netx.name(),
        group = cluster.group(),
        kind = cluster.tipo(),
        version = mosaic.version and mosaic.version.version or "?",
        free = fs.getFreeSpace("/"),
        uptime = os.clock(),
    }
    local okP, lista = pcall(hal.list)
    if okP and type(lista) == "table" then
        local nomes = {}
        for _, p in ipairs(lista) do nomes[#nomes + 1] = p.type or p.name or "?" end
        table.sort(nomes)
        b.peripherals = nomes
    end
    if turtle then
        b.fuel = cluster.combustivel()
        local okS, s = pcall(turtle.getSelectedSlot)
        if okS then
            b.slot = s
            local okI, item = pcall(turtle.getItemDetail, s)
            if okI and item then b.holding = item.name end
        end
    end
    return b
end

-- ---------------------------------------------------------------- tabela de nos

local Tabela = {}
Tabela.__index = Tabela

function cluster.tabela(nos)
    return setmetatable({ nos = nos or {} }, Tabela)
end

-- Guarda a batida de um no. `agora` vem de fora (em milissegundos) para o self-check poder
-- adiantar o relogio sem esperar de verdade.
function Tabela:registra(id, batida, agora)
    id = tonumber(id)
    if not id then return nil end
    local n = self.nos[id] or { id = id, desde = agora }
    n.id = id
    n.visto = agora
    -- So' o que a gente sabe desenhar, e so' no tipo certo. A batida vem da rede: um campo
    -- com tipo inesperado (group virando tabela, por exemplo) derruba a ordenacao da lista e
    -- leva o painel junto. Campo ausente NAO apaga o que ja se sabia - excecao para o que a
    -- turtle largou da mao, que precisa poder virar "nada".
    local ESPERADO = {
        name = "string", group = "string", kind = "string", version = "string",
        free = "number", uptime = "number", fuel = "number", slot = "number",
        holding = "string", peripherals = "table",
    }
    for k, tipo in pairs(ESPERADO) do
        local v = (batida or {})[k]
        if type(v) == tipo then n[k] = v end
    end
    if type(batida) == "table" and batida.holding == nil then n.holding = nil end
    local novo = self.nos[id] == nil
    self.nos[id] = n
    return n, novo
end

function Tabela:esquece(id)
    id = tonumber(id)
    local tinha = self.nos[id] ~= nil
    self.nos[id] = nil
    return tinha
end

-- No ar = bateu ponto dentro das ultimas FALTAS batidas.
function Tabela:noAr(n, agora)
    return (agora - (n.visto or 0)) <= cluster.INTERVALO * cluster.FALTAS * 1000
end

-- A lista pronta para desenhar: agrupada por grupo, e dentro do grupo por id.
--
-- Ordenada porque a tela nao pode dancar: um `pairs` devolve ordem diferente a cada
-- chamada, e a linha que voce ia clicar troca de lugar debaixo do cursor.
function Tabela:lista(agora)
    local out = {}
    for _, n in pairs(self.nos) do
        n.online = self:noAr(n, agora)
        out[#out + 1] = n
    end
    table.sort(out, function(a, b)
        local ga, gb = a.group or "sem grupo", b.group or "sem grupo"
        if ga ~= gb then return ga < gb end
        return a.id < b.id
    end)
    return out
end

function Tabela:conta(agora)
    local total, noAr = 0, 0
    for _, n in pairs(self.nos) do
        total = total + 1
        if self:noAr(n, agora) then noAr = noAr + 1 end
    end
    return total, noAr
end

-- Disco. Reiniciar o mestre nao pode apagar a frota: sem isto, um mestre que caiu volta
-- sem saber que existe alguem, e so' descobre quando cada no bate ponto de novo — o que
-- pode demorar, porque no de chunk descarregado nao bate ponto nenhum.
function Tabela:salva(caminho)
    caminho = caminho or cluster.ARQUIVO
    local dir = fs.getDir(caminho)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(caminho, "w")
    if not h then return false end
    local lista = {}
    for _, n in pairs(self.nos) do lista[#lista + 1] = n end
    h.write(textutils.serialiseJSON({ nos = lista }))
    h.close()
    return true
end

function cluster.carrega(caminho)
    caminho = caminho or cluster.ARQUIVO
    local t = cluster.tabela()
    if not fs.exists(caminho) then return t end
    local h = fs.open(caminho, "r")
    if not h then return t end
    local corpo = h.readAll()
    h.close()
    local ok, dados = pcall(textutils.unserialiseJSON, corpo)
    if not ok or type(dados) ~= "table" or type(dados.nos) ~= "table" then return t end
    for _, n in ipairs(dados.nos) do
        if tonumber(n.id) then t.nos[tonumber(n.id)] = n end
    end
    return t
end

-- ---------------------------------------------------------------- self-check

function cluster.demo()
    local t = cluster.tabela()
    local t0 = 1000000

    -- Primeira batida entra como no novo.
    local n, novo = t:registra(7, { name = "sete", group = "mina", kind = "turtle", fuel = 500 }, t0)
    assert(novo == true and n.name == "sete", "primeira batida devia entrar como novo")
    local _, novo2 = t:registra(7, { name = "sete", fuel = 480 }, t0 + 5000)
    assert(novo2 == false, "segunda batida do mesmo no nao e' um no novo")
    assert(t.nos[7].fuel == 480, "a batida nova tinha de atualizar o combustivel")
    assert(t.nos[7].group == "mina", "campo que nao veio na batida nova nao pode sumir")
    assert(t.nos[7].desde == t0, "o 'desde' tem de ser o da primeira vez")

    -- Tres batidas perdidas = fora do ar. Duas ainda contam como no ar.
    local janela = cluster.INTERVALO * cluster.FALTAS * 1000
    assert(t:noAr(t.nos[7], t0 + 5000 + janela), "dentro da janela ainda esta no ar")
    assert(not t:noAr(t.nos[7], t0 + 5000 + janela + 1), "passou da janela: fora do ar")

    -- Ordem: por grupo, e por id dentro do grupo. Sem isso a lista danca na tela.
    t:registra(3, { name = "tres", group = "mina" }, t0)
    t:registra(9, { name = "nove", group = "fazenda" }, t0)
    t:registra(1, { name = "um", group = "fazenda" }, t0)
    local lista = t:lista(t0)
    local ordem = {}
    for _, x in ipairs(lista) do ordem[#ordem + 1] = x.group .. "/" .. x.id end
    assert(table.concat(ordem, " ") == "fazenda/1 fazenda/9 mina/3 mina/7",
        "ordem errada: " .. table.concat(ordem, " "))

    -- Contagem separa quem esta no ar de quem sumiu.
    local total, noAr = t:conta(t0 + janela + 1)
    assert(total == 4, "deviam ser quatro nos, deu " .. total)
    assert(noAr == 1, "so' o 7 bateu ponto depois; deviam sobrar 1 no ar, deu " .. noAr)

    assert(t:esquece(3) == true and t.nos[3] == nil, "esquecer nao tirou o no")
    assert(t:esquece(3) == false, "esquecer duas vezes nao pode dizer que tirou")

    -- Disco: salvar e carregar tem de devolver a mesma frota.
    local tmp = "/tmp_cluster_teste.json"
    assert(t:salva(tmp), "nao consegui salvar a tabela")
    local t2 = cluster.carrega(tmp)
    local a, b = t2:conta(t0)
    assert(a == 3, "carregou " .. a .. " nos, deviam ser 3")
    assert(t2.nos[7].name == "sete" and t2.nos[7].group == "mina", "os campos nao voltaram")
    assert(b >= 0, "conta nao pode explodir depois de carregar")
    fs.delete(tmp)

    -- Arquivo que nao existe devolve tabela vazia, e nao erro: mestre novo comeca do zero.
    assert(select(1, cluster.carrega("/nao/existe.json"):conta(t0)) == 0,
        "sem arquivo devia comecar com a frota vazia")

    -- Arquivo estragado tambem nao pode derrubar o servico.
    local h = fs.open(tmp, "w") h.write("{isto nao e json") h.close()
    assert(select(1, cluster.carrega(tmp):conta(t0)) == 0, "json estragado devia virar frota vazia")
    fs.delete(tmp)

    -- Papel e grupo saem das configuracoes, com padrao que nao surpreende.
    local rAntes, gAntes = settings.get("mosaic.cluster.role"), settings.get("mosaic.cluster.group")
    settings.unset("mosaic.cluster.role")
    assert(cluster.role() == "no", "sem configurar, o computador e' no e nao mestre")
    assert(not cluster.isMestre(), "sem configurar, ninguem e' mestre")
    settings.set("mosaic.cluster.role", "mestre")
    assert(cluster.isMestre(), "papel de mestre nao pegou")
    settings.set("mosaic.cluster.group", "")
    assert(cluster.group() == "sem grupo", "grupo vazio precisa de um nome, senao a lista fica sem cabecalho")
    settings.set("mosaic.cluster.group", "mina-norte")
    assert(cluster.group() == "mina-norte", "grupo nao foi lido")
    if rAntes then settings.set("mosaic.cluster.role", rAntes) else settings.unset("mosaic.cluster.role") end
    if gAntes then settings.set("mosaic.cluster.group", gAntes) else settings.unset("mosaic.cluster.group") end

    -- A batida diz o basico sobre este computador, sem precisar de rede.
    local b2 = cluster.batida()
    assert(b2.name and b2.name ~= "", "a batida precisa de nome")
    assert(b2.kind == "computador" or b2.kind == "turtle" or b2.kind == "pocket",
        "tipo estranho: " .. tostring(b2.kind))
    assert(type(b2.free) == "number", "a batida tem de dizer o espaco livre")

    return true
end

return cluster
