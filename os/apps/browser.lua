-- Navegador. A pagina chega do relay ja em blocos; aqui so' se quebra linha e desenha.
--
-- Link vira numero, como no lynx: "leia mais [7]". Em 51 colunas isso ganha de cor e de
-- linha extra, e da para escolher pelo teclado - digite 7 na barra de endereco e Enter.
local ui = mosaic.ui
local theme = mosaic.theme
local httpx = mosaic.lib("httpx")
local strutil = mosaic.lib("strutil")

local doc                       -- documento atual { titulo, blocos, links }
local historico = {}
local carregando = false

local f = ui.form()

local endereco, lista, recado

-- Cor por tipo de bloco. Titulo em destaque, codigo apagado, o resto normal. Sem negrito
-- nem fonte: o CC so' tem 16 cores e uma fonte.
local COR = {
    h1 = theme.selBg, h2 = theme.selBg, h3 = theme.accent,
    code = theme.mutedFg, quote = theme.mutedFg, img = theme.mutedFg,
}
local PREFIXO = { li = "- ", quote = "| ", img = "[img] " }

local function status(texto)
    recado.text = texto or ""
    f.dirty = true
end

-- Blocos -> linhas. A quebra e' feita aqui e nao no relay porque so' o app sabe a largura da
-- janela, e a janela pode ser redimensionada ou ir para um monitor.
local function renderiza()
    local itens = {}
    if not doc then lista.items = itens return end
    -- -1 pela coluna da barra de rolagem, que a lista desenha por cima do texto.
    local w = math.max(10, (tonumber(lista.w) or 20) - 1)
    for _, b in ipairs(doc.blocos or {}) do
        if b.t == "hr" then
            itens[#itens + 1] = { separator = true }
        else
            local texto = (PREFIXO[b.t] or "") .. (b.s or "")
            for _, linha in ipairs(strutil.wrap(texto, w)) do
                itens[#itens + 1] = { text = linha, fg = COR[b.t], n = b.n }
            end
            if b.t == "h1" or b.t == "h2" then itens[#itens + 1] = { text = "" } end
        end
    end
    if doc.cortado then
        itens[#itens + 1] = { separator = true }
        itens[#itens + 1] = { text = "(pagina cortada: era grande demais)", fg = theme.mutedFg }
    end
    lista.items = itens
    lista.scroll = 0
    lista.selected = 1
    f.dirty = true
end

local abre   -- declarado antes por causa da recursao com `ir`

-- Sem relay: da para abrir texto puro e JSON por http.get direto. E' pouco, mas e' honesto -
-- melhor do que uma janela que nao abre nada e nao explica por que.
local function abreDireto(url)
    local corpo, code = httpx.get(url)
    if not corpo then return nil, tostring(code) end
    local blocos = {}
    for _, linha in ipairs(strutil.split(corpo:gsub("\r", ""), "\n")) do
        blocos[#blocos + 1] = { t = "code", s = linha }
        if #blocos >= 600 then break end
    end
    return { url = url, titulo = url, blocos = blocos, links = {} }
end

abre = function(url, semHistorico)
    if carregando then return end
    if not url or url == "" then return end
    carregando = true
    if doc and not semHistorico then historico[#historico + 1] = doc end
    status("Carregando " .. strutil.ellipsis(url, 34) .. "...")
    f:draw()          -- pinta o recado ANTES de bloquear no pedido

    local novo, err
    if httpx.gateway() then
        novo, err = httpx.gatewayJSON("/api/web", { url = url })
    else
        novo, err = abreDireto(url)
        if not novo then err = (err or "") .. " (sem relay: so texto puro)" end
    end
    carregando = false

    if not novo then
        if not semHistorico then table.remove(historico) end
        status("Nao abriu: " .. tostring(err))
        return
    end
    doc = novo
    endereco.text = doc.url or url
    endereco.cursor = #endereco.text + 1
    renderiza()
    status(string.format("%s  |  %d links", strutil.ellipsis(doc.titulo or "", 30), #(doc.links or {})))
end

local function busca(termo)
    if carregando then return end
    if not httpx.gateway() then
        status("Busca precisa do relay (Configuracoes > Relay)")
        return
    end
    carregando = true
    if doc then historico[#historico + 1] = doc end
    status("Buscando \"" .. strutil.ellipsis(termo, 24) .. "\"...")
    f:draw()
    local novo, err = httpx.gatewayJSON("/api/busca", { q = termo })
    carregando = false
    if not novo then
        table.remove(historico)
        status("Busca falhou: " .. tostring(err))
        return
    end
    doc = novo
    renderiza()
    status(#(doc.links or {}) .. " resultados")
end

-- A barra de endereco aceita as tres coisas que a pessoa naturalmente digita.
local function ir()
    local t = strutil.trim(endereco.text or "")
    if t == "" then return end
    -- So' um numero: e' o link daquele numero na pagina atual (jeito do lynx).
    local n = t:match("^%[?(%d+)%]?$")
    if n and doc and doc.links and doc.links[tonumber(n)] then
        abre(doc.links[tonumber(n)])
        return
    end
    -- Parece endereco? Abre. Senao, busca. "tem ponto e nao tem espaco" acerta
    -- exemplo.com e erra pouco - e quando erra, buscar pelo texto e' o que a pessoa queria.
    if t:match("^https?://") then
        abre(t)
    elseif t:match("^[%w%-%.]+%.%a%a+") and not t:find(" ") then
        abre("https://" .. t)
    else
        busca(t)
    end
end

local function voltar()
    local anterior = table.remove(historico)
    if not anterior then status("Nao ha para onde voltar") return end
    doc = anterior
    endereco.text = doc.url or ""
    renderiza()
    status(strutil.ellipsis(doc.titulo or "", 40))
end

-- ---------------------------------------------------------------- tela

endereco = f:add(ui.textbox {
    x = 1, y = 1, w = -6, text = "", placeholder = "endereco, busca, ou numero do link",
    onEnter = ir,
})
f:add(ui.button { text = "&Ir", right = 0, y = 1, onClick = ir })

local barra = ui.row(f, { bottom = 0, items = {
    { text = "&Voltar", onClick = voltar },
    { text = "&Buscar", alt = true, onClick = function() f:setFocus(endereco) end },
    { text = "&Monitor", alt = true, onClick = function()
        -- Ler uma pagina na parede: e' o motivo de existir do multi-tela.
        local mons = mosaic.lib("hal").monitors()
        if #mons == 0 then status("Nenhum monitor conectado") return end
        -- mosaic.current() devolve o ID do processo, nao o processo.
        os.queueEvent("mosaic:window_menu", mosaic.current(), "monitor", mons[1].name)
    end },
} })

recado = f:add(ui.label { x = 1, above = barra, w = "fill", text = "", fg = theme.mutedFg })

lista = f:add(ui.list {
    x = 1, y = 3, w = "fill", fillTo = recado, items = {},
    bg = theme.appBg, fg = theme.appFg,
    onActivate = function(self)
        local it = self.items[self.selected]
        if it and it.n and doc and doc.links and doc.links[it.n] then abre(doc.links[it.n]) end
    end,
})

f:layout()
renderiza()

if httpx.gateway() then
    status("Digite um endereco ou uma busca e tecle Enter.")
else
    status("Sem relay: so abre texto puro. Veja Configuracoes > Relay.")
end
f:setFocus(endereco)
f:run()
