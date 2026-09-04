-- Perifericos falsos para o emulador: alto-falante e monitor.
--
-- O emulador nao tem periferico nenhum (o `peripheral` do bios.lua e' um toco que devolve
-- nil para tudo), e o CraftOS-PC headless recusa monitor com "Monitors are not available in
-- this mode". Sem isto, som e multi-tela nao teriam teste nenhum fora do jogo.
--
-- Instala por cima das funcoes globais de peripheral, como o fake-reactor.lua faz, entao
-- vale para o processo todo.
--
-- Diferenca importante para o fake-reactor: aqui o `find` devolve VARIOS resultados, porque
-- e' exatamente isso que multi-monitor precisa e o find do CC devolve varargs.

-- O emulador roda em fengari (5.3) e o CC em 5.1: cobre os dois.
local unpack = table.unpack or unpack

local M = {}
M.itens = {}          -- ordem de insercao: { { name =, tipos =, obj = }, ... }

function M.add(name, tipos, obj)
    M.itens[#M.itens + 1] = { name = name, tipos = tipos, obj = obj }
    return obj
end

-- Alto-falante que anota o que tocou, em vez de fazer barulho.
--   spk.notas    lista de { instrumento, volume, tom }
--   spk.amostras total de amostras aceitas por playAudio
--   spk.cheio    quando true, playAudio recusa (simula a fila cheia do jogo)
function M.speaker(name)
    local s = { notas = {}, sons = {}, amostras = 0, cheio = false, parou = 0 }
    s.playNote = function(instrumento, volume, tom)
        s.notas[#s.notas + 1] = { instrumento, volume, tom }
        return true
    end
    s.playSound = function(nome, volume, tom)
        s.sons[#s.sons + 1] = { nome, volume, tom }
        return true
    end
    s.playAudio = function(buffer)
        if s.cheio then return false end
        s.amostras = s.amostras + #buffer
        return true
    end
    s.stop = function() s.parou = s.parou + 1 end
    M.add(name, { "speaker" }, s)
    return s
end

-- Monitor falso: um terminal de verdade por dentro (window sobre um buffer proprio), para
-- o compositor ter onde escrever e o teste ter o que ler.
--
-- `escala` muda o tamanho como no jogo: quanto maior a escala, menos caracteres cabem.
function M.monitor(name, cols, rows)
    local m = { toques = 0, escala = 1 }
    -- Pai e' o terminal nativo, nao o atual: um monitor falso costuma ser maior que a janela
    -- de quem o cria, e a janela nunca aparece na tela (nasce invisivel) - so' serve de
    -- buffer para o teste ler com getLine.
    local pai = (term.native and term.native()) or term.current()
    local base = window.create(pai, 1, 1, cols, rows, false)
    for k, v in pairs(base) do m[k] = v end

    m.getSize = function() return cols, rows end
    m.setTextScale = function(e)
        if type(e) ~= "number" or e < 0.5 or e > 5 or (e * 2) % 1 ~= 0 then
            error("Expected number between 0.5 and 5", 2)
        end
        -- O jogo recalcula o tamanho a partir da escala. Aqui o tamanho de escala 1 e' o
        -- pedido, e as outras escalas saem proporcionais - o suficiente para o codigo que
        -- procura a escala que cabe ter algo para escolher.
        m.escala = e
        cols = math.max(1, math.floor(m.baseCols / e))
        rows = math.max(1, math.floor(m.baseRows / e))
        base.reposition(1, 1, cols, rows)
        os.queueEvent("monitor_resize", name)
    end
    m.getTextScale = function() return m.escala end
    -- Para o teste ler o que foi desenhado.
    m.getLine = function(y) return base.getLine(y) end
    m.baseCols, m.baseRows = cols, rows
    m.linha = function(y)
        local ok, texto = pcall(base.getLine, y)
        return ok and texto or ""
    end
    m.tela = function()
        local t = {}
        for y = 1, rows do t[#t + 1] = m.linha(y) end
        return table.concat(t, "\n")
    end
    -- Um toque de jogador (clique direito no monitor).
    m.tocar = function(x, y)
        m.toques = m.toques + 1
        os.queueEvent("monitor_touch", name, x, y)
    end

    M.add(name, { "monitor" }, m)
    return m
end

-- HTTP falso, por evento. O emulador nao tem rede (o `http` do bios.lua sempre falha) e o
-- CraftOS tem rede DE VERDADE - nenhum dos dois serve para testar o servico de musica, que
-- precisa de respostas conhecidas e sem internet.
--
-- Substitui o `http` global, entao vale para o processo todo, como o resto deste arquivo.
--
--   local h = fake.http()
--   h.responde("/api/musica", '{"id":"abc",...}')      -- casa por pedaco da URL
--   h.responde("/api/audio/", function(url) return ... end)
function M.http()
    local h = { pedidos = {}, respostas = {} }

    function h.responde(padrao, corpo)
        h.respostas[#h.respostas + 1] = { padrao = padrao, corpo = corpo }
    end

    local function acha(url)
        -- De tras para frente: uma resposta nova ganha da antiga para o mesmo padrao, que e'
        -- como o teste troca o que o relay "responde" no meio do caminho.
        for i = #h.respostas, 1, -1 do
            local r = h.respostas[i]
            if url:find(r.padrao, 1, true) then
                local c = r.corpo
                if type(c) == "function" then c = c(url) end
                return c
            end
        end
    end

    local function handle(corpo)
        return {
            readAll = function() return corpo end,
            readLine = function() return (corpo:gmatch("[^\n]*")()) end,
            read = function(n) return corpo:sub(1, n or 1) end,
            close = function() end,
            getResponseCode = function() return 200 end,
            getResponseHeaders = function() return {} end,
        }
    end

    http = {
        checkURL = function() return true end,
        checkURLAsync = function() return true end,
        get = function(url)
            h.pedidos[#h.pedidos + 1] = url
            local c = acha(url)
            if c then return handle(c) end
            return nil, "sem resposta falsa para " .. url
        end,
        post = function(url) return nil, "post nao previsto no teste: " .. url end,
        request = function(url)
            h.pedidos[#h.pedidos + 1] = url
            local c = acha(url)
            if c then
                os.queueEvent("http_success", url, handle(c))
            else
                os.queueEvent("http_failure", url, "sem resposta falsa")
            end
        end,
        websocket = function() return false, "sem websocket no teste" end,
        websocketAsync = function(url) os.queueEvent("websocket_failure", url, "sem websocket no teste") end,
    }
    return h
end

function M.instalar()
    local function achar(name)
        for _, it in ipairs(M.itens) do if it.name == name then return it end end
    end

    peripheral.getNames = function()
        local n = {}
        for _, it in ipairs(M.itens) do n[#n + 1] = it.name end
        return n
    end
    peripheral.isPresent = function(name) return achar(name) ~= nil end
    peripheral.wrap = function(name)
        local it = achar(name)
        return it and it.obj or nil
    end
    peripheral.getType = function(name)
        local it = achar(name)
        if not it then return nil end
        return unpack(it.tipos)
    end
    peripheral.hasType = function(name, tipo)
        local it = achar(name)
        if not it then return nil end
        for _, t in ipairs(it.tipos) do if t == tipo then return true end end
        return false
    end
    peripheral.getMethods = function(name)
        local it = achar(name)
        if not it then return nil end
        local m = {}
        for k, v in pairs(it.obj) do if type(v) == "function" then m[#m + 1] = k end end
        return m
    end
    peripheral.getName = function(obj)
        for _, it in ipairs(M.itens) do if it.obj == obj then return it.name end end
    end
    -- Varargs, como o CC: `{ peripheral.find("monitor") }` tem que dar todos.
    peripheral.find = function(tipo, filtro)
        local out = {}
        for _, it in ipairs(M.itens) do
            for _, t in ipairs(it.tipos) do
                if t == tipo then
                    if not filtro or filtro(it.name, it.obj) then out[#out + 1] = it.obj end
                    break
                end
            end
        end
        return unpack(out)
    end
    peripheral.call = function(name, metodo, ...)
        local it = achar(name)
        if not it or not it.obj[metodo] then error("No such method " .. tostring(metodo), 2) end
        return it.obj[metodo](...)
    end
end

return M
