-- Contas do mod Create.
--
-- Aqui so' entra o que e' verdade por construcao: razao de engrenagem, propagacao de
-- velocidade, e stress = valor base vezes RPM. Os valores base de cada bloco NAO sao verdade
-- por construcao — mudam de versao para versao do mod — entao eles vivem numa tabela que voce
-- corrige dentro do jogo, e todo numero que veio de mim nasce marcado com `check = true`.
--
-- Onde conferir no jogo: os Oculos de Engenheiro (Engineer's Goggles) mostram o impacto de
-- cada maquina e a capacidade de cada gerador na propria tela.
local fsx = require("lib.fsx")

local create = {}

create.FILE = "/os/var/create.json"

-- Teto de rotacao do mod. Tambem marcado para conferir: e' configuravel no pacote.
create.RPM_MAX = 256

-- Semente. Cada item: name, kind ("gerador" ou "maquina"), base (SU por RPM), qty.
-- `check = true` quer dizer "esse numero veio da IA e ninguem conferiu ainda".
create.defaults = {
    rpm = 32,
    chain = "",
    items = {
        { name = "Roda d'agua",     kind = "gerador", base = 16,  qty = 1, check = true },
        { name = "Moinho de vento", kind = "gerador", base = 512, qty = 0, check = true },
        { name = "Manivela",        kind = "gerador", base = 8,   qty = 0, check = true },
        { name = "Prensa",          kind = "maquina", base = 8,   qty = 1, check = true },
        { name = "Misturador",      kind = "maquina", base = 8,   qty = 0, check = true },
        { name = "Moedor",          kind = "maquina", base = 4,   qty = 0, check = true },
        { name = "Serra",           kind = "maquina", base = 4,   qty = 0, check = true },
        { name = "Ventilador",      kind = "maquina", base = 4,   qty = 0, check = true },
        { name = "Broca",           kind = "maquina", base = 4,   qty = 0, check = true },
        { name = "Implantador",     kind = "maquina", base = 4,   qty = 0, check = true },
    },
}

local function copyDefaults()
    local out = { rpm = create.defaults.rpm, chain = create.defaults.chain, items = {} }
    for i, it in ipairs(create.defaults.items) do
        out.items[i] = { name = it.name, kind = it.kind, base = it.base, qty = it.qty, check = it.check }
    end
    return out
end

function create.load()
    local t = fsx.readJSON(create.FILE, nil)
    if type(t) ~= "table" or type(t.items) ~= "table" or #t.items == 0 then return copyDefaults() end
    t.rpm = tonumber(t.rpm) or create.defaults.rpm
    t.chain = tostring(t.chain or "")
    for _, it in ipairs(t.items) do
        it.base = tonumber(it.base) or 0
        it.qty = math.max(0, math.floor(tonumber(it.qty) or 0))
        it.kind = (it.kind == "gerador") and "gerador" or "maquina"
        it.name = tostring(it.name or "?")
    end
    return t
end

function create.save(t)
    return fsx.writeJSON(create.FILE, t)
end

-- ---------------------------------------------------------------- engrenagens

-- "8:24, 24:8" -> { {8,24}, {24,8} }. Devolve nil, motivo quando nao da para ler.
function create.parseChain(texto)
    local pares = {}
    texto = tostring(texto or "")
    if texto:match("^%s*$") then return pares end
    for pedaco in texto:gmatch("[^,;]+") do
        local a, b = pedaco:match("^%s*(%d+)%s*[:/]%s*(%d+)%s*$")
        if not a then return nil, "nao entendi '" .. pedaco:gsub("^%s+", "") .. "' (use 8:24)" end
        a, b = tonumber(a), tonumber(b)
        if a < 1 or b < 1 then return nil, "engrenagem sem dente nao existe" end
        pares[#pares + 1] = { a, b }
    end
    return pares
end

-- Multiplicador da corrente. Engrenagem de entrada com mais dentes acelera a saida.
function create.ratio(pares)
    local r = 1
    for _, p in ipairs(pares or {}) do r = r * (p[1] / p[2]) end
    return r
end

-- RPM depois da corrente. Devolve tambem se estourou o teto.
function create.speed(rpm, pares)
    local v = (tonumber(rpm) or 0) * create.ratio(pares)
    return v, math.abs(v) > create.RPM_MAX
end

-- ---------------------------------------------------------------- stress

-- Tanto o impacto de uma maquina quanto a capacidade de um gerador sao o valor base
-- multiplicado pela rotacao.
function create.su(base, rpm)
    return (tonumber(base) or 0) * math.abs(tonumber(rpm) or 0)
end

-- Soma o que a rede gasta contra o que ela aguenta.
function create.budget(items, rpm)
    local impacto, capacidade, aConferir = 0, 0, 0
    for _, it in ipairs(items or {}) do
        local qty = math.max(0, math.floor(tonumber(it.qty) or 0))
        if qty > 0 then
            local su = create.su(it.base, rpm) * qty
            if it.kind == "gerador" then capacidade = capacidade + su else impacto = impacto + su end
            if it.check then aConferir = aConferir + 1 end
        end
    end
    return { impacto = impacto, capacidade = capacidade, saldo = capacidade - impacto,
        ok = impacto <= capacidade, aConferir = aConferir }
end

function create.demo()
    -- razao de engrenagem
    local pares = assert(create.parseChain("8:24"))
    assert(#pares == 1 and pares[1][1] == 8 and pares[1][2] == 24, "leitura de 8:24 errada")
    assert(math.abs(create.ratio(pares) - 1 / 3) < 1e-9, "8:24 deveria dividir por tres")
    local ida = assert(create.parseChain("8:24, 24:8"))
    assert(math.abs(create.ratio(ida) - 1) < 1e-9, "reduzir e voltar tem de dar 1")
    assert(math.abs(create.ratio(assert(create.parseChain(""))) - 1) < 1e-9,
        "corrente vazia nao muda a velocidade")
    assert(create.parseChain("8:24, banana") == nil, "texto invalido deveria ser recusado")
    assert(create.parseChain("0:24") == nil, "engrenagem sem dente deveria ser recusada")
    assert(create.parseChain("8/24") ~= nil, "a barra tambem deveria valer como separador")

    -- velocidade e o teto
    local v, estourou = create.speed(64, assert(create.parseChain("8:24")))
    assert(math.abs(v - 64 / 3) < 1e-9, "64 RPM reduzido por tres deu " .. v)
    assert(not estourou, "21 RPM nao estoura o teto")
    local v2, estourou2 = create.speed(64, assert(create.parseChain("24:8")))
    assert(math.abs(v2 - 192) < 1e-9, "64 RPM acelerado por tres deveria dar 192")
    assert(not estourou2, "192 ainda cabe no teto de 256")
    local _, estourou3 = create.speed(128, assert(create.parseChain("24:8")))
    assert(estourou3, "384 RPM tem de acusar o teto")

    -- stress
    assert(create.su(8, 32) == 256, "base 8 a 32 RPM sao 256 SU")
    assert(create.su(8, -32) == 256, "girar ao contrario gasta o mesmo")
    local b = create.budget({
        { kind = "gerador", base = 16, qty = 2 },
        { kind = "maquina", base = 8, qty = 1 },
    }, 32)
    assert(b.capacidade == 1024, "dois geradores de base 16 a 32 RPM dao 1024, deu " .. b.capacidade)
    assert(b.impacto == 256, "uma maquina de base 8 a 32 RPM gasta 256, deu " .. b.impacto)
    assert(b.saldo == 768 and b.ok, "sobra e situacao erradas")
    local ruim = create.budget({ { kind = "maquina", base = 8, qty = 10 } }, 32)
    assert(not ruim.ok and ruim.saldo < 0, "rede sem gerador tem de acusar falta")
    assert(create.budget({}, 32).ok, "rede vazia nao esta sobrecarregada")

    -- quantidade zero nao entra na conta
    local zero = create.budget({ { kind = "maquina", base = 8, qty = 0 } }, 32)
    assert(zero.impacto == 0, "peca com quantidade zero nao deveria pesar")

    -- a semente marca tudo que veio de mim
    local t = create.load()
    assert(type(t.items) == "table" and #t.items > 0, "a tabela padrao deveria vir preenchida")
    for _, it in ipairs(create.defaults.items) do
        assert(it.check, "todo valor da semente tem de nascer marcado para conferir: " .. it.name)
    end

    return true
end

return create
