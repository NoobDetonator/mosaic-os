-- Tocador de musica. A fila e o som moram no servico `musicd`; isto aqui e' so' a cara.
--
-- Fechar esta janela nao para a musica, de proposito: quem para e' o botao Parar.
local ui = mosaic.ui
local theme = mosaic.theme

local function cmd(c, a) os.queueEvent("mosaic:music_cmd", c, a) end

local function status()
    return (mosaic.musicStatus and mosaic.musicStatus()) or nil
end

local function tempo(seg)
    seg = math.max(0, math.floor(tonumber(seg) or 0))
    return string.format("%d:%02d", math.floor(seg / 60), seg % 60)
end

local f = ui.form()

local titulo = f:add(ui.label { x = 1, y = 1, w = "fill", text = "" })
local autor = f:add(ui.label { x = 1, y = 2, w = "fill", text = "", fg = theme.mutedFg })
local barraTempo = f:add(ui.progress { x = 1, y = 3, w = -12, value = 0, max = 1 })
-- `right = 0` e nao `x = -11`: x NAO e' chave de ancoragem, e um x negativo desenha fora da
-- tela em silencio.
local relogio = f:add(ui.label { right = 0, y = 3, w = 11, text = "", fg = theme.mutedFg })
local recado = f:add(ui.label { x = 1, y = 4, w = "fill", text = "", fg = theme.mutedFg })

local botoes = ui.row(f, { bottom = 0, items = {
    { text = "&Tocar", onClick = function() cmd("play") end },
    { text = "&Pausar", onClick = function() cmd("pause") end },
    { text = "&Proxima", alt = true, onClick = function() cmd("next") end },
    { text = "&Parar", alt = true, onClick = function() cmd("stop") end },
} })

local caixa, lista

local function adicionar()
    local t = (caixa.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return end
    cmd("add", t)
    caixa.text = ""
    caixa.cursor = 1
    f.dirty = true
end

caixa = f:add(ui.textbox {
    x = 1, w = -13, above = botoes, placeholder = "link ou nome da musica",
    onEnter = adicionar,
})
f:add(ui.button { text = "&Adicionar", right = 0, above = botoes, onClick = adicionar })

lista = f:add(ui.list {
    x = 1, y = 5, w = "fill", fillTo = caixa, items = {},
    onActivate = function(_, _, idx) cmd("play_index", idx) end,
})

-- Del na lista tira da fila. E' o jeito de mexer na fila sem menu, e menu aqui seria uma
-- janela em cima de uma janela numa tela de 51 colunas.
--
-- O onKey original vem da CLASSE List (setas, Enter, PageUp...). Trocar a funcao na
-- instancia sem chamar a de tras mataria a navegacao inteira em silencio.
local listaOnKey = lista.onKey
lista.onKey = function(self, code)
    if code == keys.delete then
        if self.selected then cmd("remove", self.selected) end
        return
    end
    return listaOnKey(self, code)
end

local function atualiza()
    local s = status()
    if not s then
        titulo.text = "Servico de musica nao esta rodando"
        recado.text = "Reinicie o computador para ligar o musicd"
        f.dirty = true
        return
    end

    local faixa = s.faixa
    titulo.text = faixa and faixa.titulo or (s.termo and ("Preparando: " .. s.termo) or "Nada tocando")
    autor.text = faixa and faixa.autor or ""

    local dur = (faixa and faixa.duracao or 0)
    barraTempo.max = math.max(1, dur)
    barraTempo.value = math.min(s.segundos or 0, barraTempo.max)
    relogio.text = faixa and (tempo(s.segundos) .. "/" .. tempo(dur)) or ""

    -- Um recado so', e o mais urgente primeiro: sem isto a pessoa fica olhando uma tela
    -- parada sem saber se o problema e' o relay, o alto-falante ou a musica.
    if s.erro then
        recado.text = s.erro
    elseif not s.relay then
        recado.text = "Relay nao configurado (Configuracoes > Relay)"
    elseif not s.temSom then
        -- Diz o que fazer, nao so' o que falta: e' o recado que mais aparece para quem esta
        -- comecando, e "sem alto-falante" sozinho nao ensina nada.
        recado.text = #(s.fila or {}) > 0
            and "Falta o alto-falante. Encoste um e ele toca."
            or "Encoste um alto-falante no computador."
    elseif s.preparando then
        recado.text = "Preparando no relay: " .. tostring(s.preparando) .. "..."
    elseif s.tocando then
        recado.text = ""
    elseif #(s.fila or {}) > 0 then
        recado.text = "Parado. Tocar para continuar."
    else
        recado.text = "Cole um link ou digite o nome e tecle Enter."
    end

    local itens = {}
    for i, m in ipairs(s.fila or {}) do
        local marca = (i == s.atual) and (s.tocando and ">" or "=") or " "
        itens[#itens + 1] = { text = string.format("%s %d. %s", marca, i, m.titulo or "?") }
    end
    lista.items = itens
    if lista.selected and lista.selected > #itens then lista.selected = #itens > 0 and #itens or nil end
    f.dirty = true
end

local BATIDA = 0.5
local t = os.startTimer(BATIDA)

f.onEvent = function(_, ev, a)
    if ev == "mosaic:music_state" then
        atualiza()
        return true
    elseif ev == "timer" and a == t then
        t = os.startTimer(BATIDA)
        -- Redesenha so' quando a janela esta na frente: o servico continua tocando atras.
        if mosaic.focused() == mosaic.current() then atualiza() end
        return true
    end
end

atualiza()
f:run()
