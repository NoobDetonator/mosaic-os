-- Prospeccao: o que ha no chunk e o que ha por perto, pelo Geo Scanner.
--
-- Duas perguntas diferentes, e por isso dois modos:
--   * ANALISE le' o chunk inteiro e responde "vale a pena cavar aqui?";
--   * RAIO le' um cubo em volta do scanner e responde "onde exatamente esta a veia?".
--
-- O scanner mede em volta de SI MESMO. Ligado por cabo ele e' uma estacao parada, entao as
-- posicoes do raio saem relativas ao bloco dele - nao de quem esta olhando a tela.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")
local geo = mosaic.lib("geo")

local W = select(1, term.getSize())
local ESTREITO = W < 46

local f = ui.form()
local lista, status, barra, cabecalho
local raio = 8
local itens = {}

-- Barra proporcional ao maior valor da lista, nao a um teto inventado: o que interessa e'
-- comparar os minerios entre si, e um teto fixo achataria todos contra a esquerda.
local function barraDe(n, maior, largura)
    if largura < 3 or not maior or maior <= 0 then return "" end
    local cheio = math.floor((n / maior) * largura + 0.5)
    if n > 0 and cheio == 0 then cheio = 1 end      -- 1 de 5000 nao pode sumir
    return string.rep("\149", cheio) .. string.rep(" ", largura - cheio)
end

local function desenha()
    local maior = 0
    for _, it in ipairs(itens) do if it.n > maior then maior = it.n end end
    local largura = tonumber(lista and lista.w) or W
    local nomeW = ESTREITO and 14 or 20
    local barW = math.max(0, largura - nomeW - 8)
    local linhas = {}
    for _, it in ipairs(itens) do
        linhas[#linhas + 1] = {
            it = it,
            text = string.format(" %-" .. nomeW .. "s %5d %s",
                strutil.ellipsis(it.curto, nomeW), it.n, barraDe(it.n, maior, barW)),
            -- Minerio em cor, resto apagado: a lista tem 46 linhas e so' uma duzia importa.
            fg = it.minerio and colors.yellow or theme.mutedFg,
        }
    end
    lista:setItems(linhas, true)
    f.dirty = true
end

local function conta()
    local minerios, total = 0, 0
    for _, it in ipairs(itens) do
        total = total + it.n
        if it.minerio then minerios = minerios + 1 end
    end
    return minerios, total
end

-- ---------------------------------------------------------------- acoes

local function analisa()
    status.text = " Lendo o chunk..."
    f:draw()
    local lst, err = geo.analise()
    if not lst then
        itens = {}
        desenha()
        status.text = " " .. tostring(err)
        f.dirty = true
        return
    end
    itens = lst
    desenha()
    local minerios, total = conta()
    status.text = string.format(" Chunk: %d tipos, %d minerios, %d blocos",
        #itens, minerios, total)
    f.dirty = true
end

local function varre()
    status.text = " Varrendo raio " .. raio .. "..."
    f:draw()
    local lst, quantos = geo.varre(raio)
    if not lst then
        itens = {}
        desenha()
        status.text = " " .. tostring(quantos)
        f.dirty = true
        return
    end
    itens = lst
    desenha()
    local minerios = conta()
    status.text = string.format(" Raio %d: %d blocos, %d tipos, %d minerios",
        raio, quantos or 0, #itens, minerios)
    f.dirty = true
end

local function ondeEsta()
    local it = lista:getSelected()
    if not it or not it.it then return end
    local g = it.it
    if not g.pontos or #g.pontos == 0 then
        ui.msgbox("Esta lista veio da analise do chunk, que nao traz posicao.\n"
            .. "Use Varrer para saber onde estao.", g.curto)
        return
    end
    -- Mostra as mais PROXIMAS do scanner, nao as primeiras da lista: quem pergunta "onde
    -- esta" quer a que da' menos trabalho de alcancar.
    local pts = {}
    for _, p in ipairs(g.pontos) do
        pts[#pts + 1] = { p = p, d = math.abs(p.x) + math.abs(p.y) + math.abs(p.z) }
    end
    table.sort(pts, function(a, b) return a.d < b.d end)
    local linhas = { g.n .. " no raio " .. raio .. ", relativo ao scanner:" }
    for i = 1, math.min(#pts, 8) do
        local p = pts[i].p
        linhas[#linhas + 1] = string.format("  x%+d  y%+d  z%+d", p.x or 0, p.y or 0, p.z or 0)
    end
    if #pts > 8 then linhas[#linhas + 1] = "  ... e mais " .. (#pts - 8) end
    ui.msgbox(table.concat(linhas, "\n"), g.curto)
end

-- ---------------------------------------------------------------- layout

cabecalho = f:add(ui.label { x = 2, y = 1, w = -2, text = "" })

barra = ui.row(f, { bottom = 0, items = {
    { text = "&Analisar", onClick = analisa },
    { text = "&Varrer", onClick = varre },
    { text = "&Raio", alt = true, onClick = function()
        local texto = ui.prompt("Raio do scan (1 a 16):", tostring(raio), "Raio")
        if not texto then return end
        local n = tonumber(texto)
        if not n or n < 1 or n > 16 then
            status.text = " Raio tem de ser um numero de 1 a 16."
            f.dirty = true
            return
        end
        raio = math.floor(n)
        status.text = " Raio agora e' " .. raio .. ". Clique em Varrer."
        f.dirty = true
    end },
    { text = "&Onde", alt = true, onClick = ondeEsta },
} })
status = f:add(ui.label { x = 1, above = barra, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
lista = f:add(ui.list { x = 1, y = 2, w = "fill", fillTo = status, items = {},
    onActivate = ondeEsta })

local g = geo.find()
if g then
    cabecalho.text = "Geo Scanner pronto. Analisar le o chunk; Varrer, um raio."
    status.text = " Clique em Analisar para comecar."
else
    cabecalho.text = "Nenhum Geo Scanner na rede deste computador."
    status.text = " Ligue um Geo Scanner por cabo ou modem."
    cabecalho.fg = colors.orange
end

f:run()
