-- Servico de musica: segura a fila e toca. O app `music` e' so' a cara disto.
--
-- Por que servico e nao app: musica que para quando voce fecha a janela nao e' um tocador,
-- e' um script. Aqui a fila sobrevive a janela, como o relay sobrevive ao app de rede.
--
-- Fala com o relay, que baixa do YouTube e converte para DFPWM. O computador do jogo nao
-- baixa video: ele pede pedacos de 16 KiB ja convertidos e empurra para o alto-falante.
--
-- Comandos chegam por evento:  os.queueEvent("mosaic:music_cmd", cmd, arg)
-- O estado sai por            mosaic.musicStatus()  e o evento  mosaic:music_state
local audio = mosaic.lib("audio")
local httpx = mosaic.lib("httpx")
local log = mosaic.lib("log").open("musica")

-- Dois pedacos a frente. Cada pedaco e' ~2,7 s de som, entao isto da ~5 s de folga para o
-- pedido HTTP ir e voltar - o suficiente numa rede caseira, sem gastar memoria a toa.
local PREFETCH = 2
local BATIDA = 1

local fila = {}                 -- { { id, titulo, autor, duracao, blocos } }
local atual = 0                 -- indice na fila, 0 = nada
local tocando = false
local st                        -- audio.stream da faixa atual
local proximoBloco = 1
local buffer = {}               -- pedacos crus ja baixados, esperando o alto-falante
local pedindoAudio              -- url do pedaco em voo
local pedindoMeta               -- url da resolucao em voo
local termoPendente             -- o que o usuario pediu e ainda esta sendo preparado
local preparando                -- texto do estado ("buscando", "convertendo"...)
local tentativas = 0
local ultimoErro
local esperandoSom              -- fila pronta, faltando so' o alto-falante aparecer

local estado = {}
local function publica()
    estado.tocando = tocando
    estado.atual = atual
    estado.faixa = fila[atual]
    estado.fila = fila
    estado.preparando = preparando
    estado.termo = termoPendente
    estado.erro = ultimoErro
    os.queueEvent("mosaic:music_state")
end

-- Alto-falante, relay e tempo tocado sao perguntas sobre o MUNDO, nao sobre o servico, e por
-- isso sao respondidas na hora em vez de ficarem guardadas no publica().
--
-- Guardadas, davam resposta velha: no boot ainda nao ha alto-falante (o periferico aparece
-- depois), o publica() so' roda em evento, e o app dizia "nenhum alto-falante" para sempre.
-- No jogo e' pior: as pessoas grudam periferico com o computador ligado.
mosaic.musicStatus = function()
    estado.temSom = audio.has()
    estado.relay = httpx.gateway() ~= nil
    estado.segundos = st and st:seconds() or 0
    return estado
end

-- ---------------------------------------------------------------- reproducao

local function paraFluxo()
    if st then st:stop() end
    st = nil
    buffer = {}
    pedindoAudio = nil
    proximoBloco = 1
    tentativas = 0
end

local function comecaFaixa(i)
    paraFluxo()
    atual = i or 0
    local f = fila[atual]
    if not f then tocando = false publica() return end
    -- Um fluxo novo por faixa: o decodificador guarda estado do fluxo, e reaproveitar entre
    -- musicas sai com o som errado (a documentacao do cc.audio.dfpwm avisa isso em caixa).
    st = audio.stream()
    if not st:ok() then
        -- Falta de alto-falante NAO e' erro: e' hardware que ainda nao esta la'. Nao vai para
        -- `ultimoErro` porque o app tem uma frase melhor para isso ("Nenhum alto-falante ao
        -- lado do computador"), e um erro guardado taparia essa frase.
        --
        -- Fica marcado para a batida tentar de novo: no jogo se gruda alto-falante com o
        -- computador ligado, e a musica tem que comecar sozinha quando ele aparecer.
        if not audio.has() then
            esperandoSom = true
            -- Limpa o erro anterior: a situacao mudou, e um erro velho na tela e' pior que
            -- nenhum - a pessoa conserta a coisa errada.
            ultimoErro = nil
        else
            -- Aqui e' erro de verdade: tem alto-falante e mesmo assim nao deu. Na pratica so'
            -- acontece em servidor com CC:T anterior a 1.100, que nao tem cc.audio.dfpwm.
            ultimoErro = st.err
        end
        tocando = false
        publica()
        return
    end
    esperandoSom = false
    tocando = true
    ultimoErro = nil
    publica()
end

local function pedeBloco()
    if not tocando or pedindoAudio or not st then return end
    local f = fila[atual]
    if not f then return end
    if #buffer >= PREFETCH then return end
    if proximoBloco > (f.blocos or 0) then return end
    local url, headers = httpx.gatewayUrl("/api/audio/" .. f.id .. "/" .. proximoBloco)
    if not url then ultimoErro = "relay nao configurado" tocando = false publica() return end
    pedindoAudio = url
    httpx.requestAsync(url, nil, headers, true)
end

local function alimenta()
    if not st or not tocando then return end
    if st.pending then st:retry() return end
    local pedaco = table.remove(buffer, 1)
    if pedaco then st:offer(pedaco) end
end

-- A faixa acabou quando nao ha mais o que pedir, nem o que empurrar, nem nada preso.
local function acabou()
    local f = fila[atual]
    if not f then return false end
    return proximoBloco > (f.blocos or 0) and #buffer == 0 and st and not st.pending
end

local function proxima()
    if atual < #fila then comecaFaixa(atual + 1) else paraFluxo() tocando = false atual = 0 publica() end
end

-- ---------------------------------------------------------------- fila

local function pedeMeta(termo)
    local url, headers = httpx.gatewayUrl("/api/musica", { q = termo })
    if not url then ultimoErro = "relay nao configurado" publica() return end
    termoPendente = termo
    preparando = "pedindo"
    pedindoMeta = url
    httpx.requestAsync(url, nil, headers)
    publica()
end

local function trataMeta(corpo)
    local ok, doc = pcall(textutils.unserialiseJSON, corpo)
    if not ok or type(doc) ~= "table" then
        ultimoErro = "resposta do relay nao e JSON"
        termoPendente, preparando = nil, nil
        publica()
        return
    end
    if doc.erro then
        ultimoErro = doc.erro
        termoPendente, preparando = nil, nil
        publica()
        return
    end
    -- Ainda preparando: o relay avisa e a gente pergunta de novo daqui a pouco. Converter
    -- leva de 20 a 60 s, e uma requisicao do CC morre em 30 - por isso o relay nao espera.
    if doc.espere then
        preparando = doc.estado or "preparando"
        if doc.titulo and doc.titulo ~= "" then termoPendente = doc.titulo end
        publica()
        return
    end
    fila[#fila + 1] = {
        id = doc.id, titulo = doc.titulo or "sem titulo", autor = doc.autor or "",
        duracao = tonumber(doc.duracao) or 0, blocos = tonumber(doc.blocos) or 0,
    }
    log:info("na fila: " .. tostring(doc.titulo))
    termoPendente, preparando, ultimoErro = nil, nil, nil
    if not tocando then comecaFaixa(#fila) else publica() end
end

local function comando(cmd, arg)
    if cmd == "add" and arg and arg ~= "" then
        if pedindoMeta or termoPendente then
            ultimoErro = "espere a musica anterior ficar pronta"
            publica()
        else
            pedeMeta(arg)
        end
    elseif cmd == "play" then
        if #fila == 0 then return end
        if atual == 0 then comecaFaixa(1)
        elseif not tocando then tocando = true publica() alimenta() pedeBloco() end
    elseif cmd == "pause" then
        tocando = false
        if st then st:stop() end
        publica()
    elseif cmd == "play_index" then
        local i = tonumber(arg)
        if i and fila[i] then comecaFaixa(i) end
    elseif cmd == "next" then
        if atual < #fila then comecaFaixa(atual + 1) end
    elseif cmd == "prev" then
        if atual > 1 then comecaFaixa(atual - 1) elseif atual == 1 then comecaFaixa(1) end
    elseif cmd == "stop" then
        paraFluxo() tocando = false atual = 0 publica()
    elseif cmd == "remove" then
        local i = tonumber(arg)
        if i and fila[i] then
            table.remove(fila, i)
            if i == atual then
                if fila[i] then comecaFaixa(i) else paraFluxo() tocando = false atual = 0 publica() end
            elseif i < atual then
                atual = atual - 1 publica()
            else
                publica()
            end
        end
    elseif cmd == "clear" then
        paraFluxo() fila = {} atual = 0 tocando = false publica()
    end
end

-- ---------------------------------------------------------------- laco

publica()
local batida = os.startTimer(BATIDA)

while true do
    local ev = { os.pullEvent() }
    local nome = ev[1]

    if nome == "mosaic:music_cmd" then
        comando(ev[2], ev[3])

    elseif nome == "speaker_audio_empty" then
        -- O evento diz QUAL alto-falante vagou; ignorar isso trava com mais de um.
        if st and st:owns(ev[2]) then
            alimenta()
            pedeBloco()
            if acabou() then proxima() end
        end

    elseif nome == "http_success" and ev[2] == pedindoAudio then
        pedindoAudio = nil
        tentativas = 0
        local h = ev[3]
        local dados = h and h.readAll()
        if h then h.close() end
        if dados and #dados > 0 then
            buffer[#buffer + 1] = dados
            proximoBloco = proximoBloco + 1
        else
            -- Corpo vazio = fim do arquivo pelo lado do relay.
            proximoBloco = math.huge
        end
        alimenta()
        pedeBloco()

    elseif nome == "http_failure" and ev[2] == pedindoAudio then
        pedindoAudio = nil
        tentativas = tentativas + 1
        if tentativas >= 3 then
            ultimoErro = "falha ao baixar o audio: " .. tostring(ev[3])
            log:error(ultimoErro)
            proxima()
        else
            pedeBloco()
        end

    elseif nome == "http_success" and ev[2] == pedindoMeta then
        pedindoMeta = nil
        local h = ev[3]
        local corpo = h and h.readAll()
        if h then h.close() end
        trataMeta(corpo or "")

    elseif nome == "http_failure" and ev[2] == pedindoMeta then
        pedindoMeta = nil
        -- O CC entrega a RESPOSTA que falhou no quarto argumento, e o relay poe o motivo de
        -- verdade no corpo do 502 ("falta instalar yt-dlp e ffmpeg"). Sem ler isso, a tela
        -- mostrava so' "Bad Gateway" e nao havia como a pessoa descobrir o que fazer.
        local h = ev[4]
        local corpo = h and h.readAll()
        if h then pcall(h.close) end
        local ok, doc = pcall(textutils.unserialiseJSON, corpo or "")
        ultimoErro = (ok and type(doc) == "table" and doc.erro)
            or ("o relay nao respondeu: " .. tostring(ev[3]))
        termoPendente, preparando = nil, nil
        publica()

    elseif nome == "timer" and ev[2] == batida then
        batida = os.startTimer(BATIDA)
        -- Alguem grudou o alto-falante depois: comeca a tocar sozinho, sem a pessoa ter que
        -- descobrir que precisa apertar Tocar de novo.
        if esperandoSom and audio.has() and fila[atual] then
            comecaFaixa(atual)
        end
        -- A batida existe porque `speaker_audio_empty` nao e' garantia de progresso: se um
        -- evento se perder na fila de 256 do CC, a musica pararia calada e para sempre.
        if tocando then
            alimenta()
            pedeBloco()
            if acabou() then proxima() end
        end
        -- Continua perguntando enquanto o relay prepara.
        if termoPendente and not pedindoMeta then pedeMeta(termoPendente) end
        if tocando or termoPendente then publica() end
    end
end
