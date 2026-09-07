-- Prospeccao: o que ha no chunk, o que ha por perto, e onde isso esta em tres dimensoes.
--
-- Tres perguntas diferentes, e por isso tres modos:
--   * ANALISE  le' o chunk inteiro e responde "vale a pena cavar aqui?";
--   * LISTA    le' um raio em volta do scanner e conta o que achou;
--   * 3D       mostra ONDE, com a turtle dentro da cena se ela for conhecida.
--
-- O scanner mede em volta de SI MESMO. Ligado por cabo ele e' uma estacao parada, entao as
-- posicoes saem relativas ao bloco dele - nao de quem olha a tela, e nao da turtle.
--
-- NUM MONITOR NAO HA TECLADO, e `monitor_touch` e' so' clique de botao direito: nao existe
-- arrastar nem tecla. Por isso a camera gira sozinha quando o app esta numa parede, e todo
-- filtro se resolve com um toque na legenda. Na janela o teclado manda, porque ali ele existe.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")
local pixel = mosaic.lib("pixel")
local three = mosaic.lib("three")
local geo = mosaic.lib("geo")
local geo3d = mosaic.lib("geo3d")

local f = ui.form()
local status, barra

local modo = "lista"               -- "lista" | "3d"
local raio, gratis = 8, nil
local itens = {}                   -- grupos da ultima leitura
local temPosicao = false           -- a leitura atual traz posicao? (analise nao traz)
local ligados = nil                -- nil = tudo ligado; senao { [nome] = true }
local faixaY = nil                 -- { min, max } ou nil
local rolagem = 0
local clicaveis = {}               -- y da tela -> indice em `itens`

local giro, altura, zoom = 0.7, 0.5, 1.0
local gira = false                 -- camera girando sozinha
local c3d, f3d, cw3d, ch3d

-- ---------------------------------------------------------------- a turtle na cena
--
-- A posicao da turtle vem em coordenada do MUNDO (ela conta os proprios passos); o scan vem
-- em coordenada relativa ao scanner. Para juntar as duas e' preciso saber onde o scanner
-- esta, e isso o Advanced Peripherals nao informa - nao ha `getPosition` nele.
--
-- Sem GPS no servidor, so' resta a ancora a mao: a pessoa le' o F3 uma vez e escreve. E' a
-- mesma solucao da turtle, pelo mesmo motivo.
local function ancora()
    local txt = settings.get("mosaic.geo.anchor")
    if type(txt) ~= "string" then return nil end
    local x, y, z = txt:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$")
    if not x then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

-- A turtle da frota, em coordenada de scan. Devolve tambem o motivo de nao dar, porque
-- "a turtle nao aparece" sem explicacao e' o tipo de coisa que ninguem consegue consertar.
local function turtleNaCena()
    local a = ancora()
    if not a then return nil, "ancore o scanner (F3) para situar a turtle" end
    if not mosaic.clusterNodes then return nil, "sem servico de rede" end
    local nos = mosaic.clusterNodes()
    for _, n in ipairs(nos) do
        if n.kind == "turtle" and type(n.pos) == "table" and n.online then
            return { x = n.pos.x - a.x, y = n.pos.y - a.y, z = n.pos.z - a.z },
                   nil, n.name, n.pos.certa
        end
    end
    return nil, "nenhuma turtle no ar na frota"
end

-- ---------------------------------------------------------------- estado da leitura

local function ligadoNome(nome) return ligados == nil or ligados[nome] == true end

local function alterna(i)
    local it = itens[i]
    if not it then return end
    if ligados == nil then
        -- Primeiro clique liga todos menos o clicado: e' o que a pessoa quer dizer com
        -- "tira esse daqui", e nao "deixa so' esse".
        ligados = {}
        for _, g in ipairs(itens) do ligados[g.nome] = true end
    end
    ligados[it.nome] = not ligados[it.nome]
    f.dirty = true
end

local function soMinerios()
    ligados = {}
    for _, g in ipairs(itens) do if g.minerio then ligados[g.nome] = true end end
    f.dirty = true
end

local function conta()
    local minerios, total, ligadosN = 0, 0, 0
    for _, it in ipairs(itens) do
        total = total + it.n
        if it.minerio then minerios = minerios + 1 end
        if ligadoNome(it.nome) then ligadosN = ligadosN + 1 end
    end
    return minerios, total, ligadosN
end

-- ---------------------------------------------------------------- lista

-- Barra proporcional ao MAIOR da lista, nao a um teto inventado: o que interessa e' comparar
-- os minerios entre si, e um teto fixo achataria todos contra a esquerda.
local function barraDe(n, maior, largura)
    if largura < 3 or not maior or maior <= 0 then return "" end
    local cheio = math.floor((n / maior) * largura + 0.5)
    if n > 0 and cheio == 0 then cheio = 1 end      -- 1 de 5000 nao pode sumir
    return string.rep("\149", cheio) .. string.rep(" ", largura - cheio)
end

local function desenhaLista(t, reserva)
    local tw, th = t.getSize()
    th = th - reserva
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.clear()
    clicaveis = {}

    if #itens == 0 then
        t.setCursorPos(2, 2)
        t.setTextColor(theme.mutedFg)
        t.write("Analisar le o chunk. Varrer le um raio.")
        return
    end

    local maior = 0
    for _, it in ipairs(itens) do if it.n > maior then maior = it.n end end
    local estreito = tw < 46
    local nomeW = estreito and 12 or 18
    local barW = math.max(0, tw - nomeW - 12)

    rolagem = math.max(0, math.min(rolagem, math.max(0, #itens - th)))
    for linha = 1, th do
        local i = linha + rolagem
        local it = itens[i]
        if not it then break end
        clicaveis[linha] = i
        t.setCursorPos(1, linha)
        -- A marca de ligado vem ANTES do nome: e' o que a pessoa procura quando esta
        -- filtrando, e no fim da linha ela se perde entre a barra e o numero.
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(ligadoNome(it.nome) and colors.lime or theme.mutedFg)
        t.write(ligadoNome(it.nome) and "[x] " or "[ ] ")
        -- Quadradinho na cor que a mesma veia tera no 3D: sem isso a legenda e o desenho
        -- sao dois mundos, e ninguem liga um ao outro.
        t.setBackgroundColor(geo3d.corDe(it.nome, i))
        t.write("  ")
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(it.minerio and colors.yellow or theme.mutedFg)
        t.write(" " .. strutil.ellipsis(it.curto, nomeW) ..
            string.rep(" ", math.max(0, nomeW - #strutil.ellipsis(it.curto, nomeW))))
        t.write(string.format("%5d ", it.n))
        t.setTextColor(geo3d.corDe(it.nome, i))
        t.write(barraDe(it.n, maior, barW))
    end
    if #itens > th then
        t.setCursorPos(tw, 1)
        t.setTextColor(theme.mutedFg)
        t.write("\24")
        t.setCursorPos(tw, th)
        t.write("\25")
    end
end

-- ---------------------------------------------------------------- 3D

local function desenha3D(t, reserva)
    local tw, th = t.getSize()
    th = th - reserva
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.clear()
    clicaveis = {}

    if not temPosicao then
        t.setCursorPos(2, 2)
        t.setTextColor(colors.orange)
        t.write("A analise do chunk nao traz posicao.")
        t.setCursorPos(2, 3)
        t.setTextColor(theme.mutedFg)
        t.write("Clique em Varrer para ter o 3D.")
        return
    end

    local alvo, motivo, nomeT = turtleNaCena()
    local cena = geo3d.cena(itens, {
        raio = raio,
        ligados = ligados,
        faixaY = faixaY,
        turtle = alvo,
    })

    -- Legenda ao lado quando ha largura, embaixo quando nao ha. E' o mesmo criterio do painel
    -- do reator: o desenho fica com o que sobra, e sobrar pouco e' pior que legenda embaixo.
    local legW = 0
    for _, r in ipairs(cena.legenda) do
        local n = #r.curto + 10
        if n > legW then legW = n end
    end
    legW = math.min(legW, 22)
    local aoLado = (tw - legW) >= 24
    local gw = aoLado and (tw - legW) or tw
    local gh = aoLado and th or math.max(3, th - math.min(#cena.legenda + 1, 6))

    if not c3d or cw3d ~= gw or ch3d ~= gh then
        c3d = pixel.new(gw, gh, colors.black)
        f3d = three.frame(c3d)
        -- 45 graus e nao os 70 de fabrica: com o campo aberto e a camera perto, a
        -- perspectiva entorta o cubo do chunk a ponto de ele deixar de parecer um cubo.
        f3d:setFoV(45)
        cw3d, ch3d = gw, gh
    end

    local meio = cena.tamanho / 2
    -- Enquadra pela esfera que envolve o cubo inteiro do scan, e nao pelos blocos achados:
    -- assim a cena nao pula de tamanho quando um filtro liga ou desliga.
    local raioCena = math.sqrt(3) * meio
    local dist = raioCena * f3d:begin().escala / (math.min(c3d.w, c3d.h) / 2) / zoom

    f3d:orbit({ 0, 0, 0 }, dist, giro, altura)
    -- Fundo cinza bem escuro, nao preto: o degrau mais escuro da rampa E' preto, e face que
    -- cai nele some no fundo. Ja custou um cubo virar losango neste projeto.
    f3d:clear(colors.black)

    -- A caixa do scan primeiro, para dar noção de escala mesmo com tudo filtrado.
    local m = -meio
    local cantos = {
        { m, m, m }, { -m, m, m }, { -m, m, -m }, { m, m, -m },
        { m, -m, m }, { -m, -m, m }, { -m, -m, -m }, { m, -m, -m },
    }
    local arestas = { {1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8} }
    local pre = f3d:begin()
    for _, a in ipairs(arestas) do
        local p1, p2 = cantos[a[1]], cantos[a[2]]
        local x1, y1, w1 = f3d:project(p1[1], p1[2], p1[3], pre)
        local x2, y2, w2 = f3d:project(p2[1], p2[2], p2[3], pre)
        if w1 and w2 then c3d:line(x1, y1, x2, y2, colors.gray) end
    end

    f3d:draw(cena.objetos)
    c3d:render(t, 1, 1)

    -- Legenda: quadradinho na cor, nome, contagem, e a marca de ligado. Sem ela o desenho e'
    -- so' cor bonita, e nao da' para saber o que se esta olhando.
    local lx = aoLado and (gw + 1) or 1
    local ly = aoLado and 1 or (gh + 1)
    local limite = aoLado and th or (th)
    for i, r in ipairs(cena.legenda) do
        if ly > limite then break end
        t.setCursorPos(lx, ly)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(r.ligado and colors.lime or theme.mutedFg)
        t.write(r.ligado and "x" or " ")
        t.setBackgroundColor(r.cor)
        t.write("  ")
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(r.ligado and theme.appFg or theme.mutedFg)
        local espaco = math.max(0, (aoLado and (tw - lx) or tw) - 3 - #tostring(r.n) - 2)
        t.write(" " .. strutil.ellipsis(r.curto, espaco) ..
            string.rep(" ", math.max(0, espaco - #strutil.ellipsis(r.curto, espaco))) ..
            tostring(r.n))
        clicaveis[ly] = i
        ly = ly + 1
    end
    if cena.legenda.turtle and ly <= limite then
        t.setCursorPos(lx, ly)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(colors.white)
        t.write(" [] " .. strutil.ellipsis(nomeT or "turtle", 14))
    elseif motivo and ly <= limite then
        t.setCursorPos(lx, ly)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(strutil.ellipsis(motivo, (aoLado and (tw - lx) or tw) - 1))
    end
    if cena.cortou then
        t.setCursorPos(1, th)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(colors.orange)
        t.write(" cena grande demais: filtre para ver tudo ")
    end
end

f.onDraw = function(_, t)
    if modo == "3d" then desenha3D(t, 2) else desenhaLista(t, 2) end
end

-- ---------------------------------------------------------------- acoes

local function resumo()
    local minerios, total, ligadosN = conta()
    if temPosicao then
        status.text = string.format(" Raio %d: %d tipos, %d minerios, %d ligados%s",
            raio, #itens, minerios, ligadosN,
            faixaY and string.format(" | y %d..%d", faixaY[1], faixaY[2]) or "")
    else
        status.text = string.format(" Chunk: %d tipos, %d minerios, %d blocos",
            #itens, minerios, total)
    end
    f.dirty = true
end

local function analisa()
    status.text = " Lendo o chunk..."
    f:draw()
    local lst, err = geo.analise()
    if not lst then itens = {} status.text = " " .. tostring(err) f.dirty = true return end
    itens, temPosicao, ligados, rolagem = lst, false, nil, 0
    modo = "lista"
    resumo()
end

local function varre()
    status.text = " Varrendo raio " .. raio .. "..."
    f:draw()
    local lst, quantos = geo.varre(raio)
    if not lst then itens = {} status.text = " " .. tostring(quantos) f.dirty = true return end
    itens, temPosicao, rolagem = lst, true, 0
    -- Comeca so' com minerio ligado: uma varredura traz milhares de blocos de pedra, e a
    -- cena com pedra nao mostra nada alem de um cubo macico.
    soMinerios()
    resumo()
end

local function mudaRaio()
    local texto = ui.prompt("Raio do scan (1 a 16):", tostring(raio), "Raio")
    if not texto then return end
    local n = tonumber(texto)
    if not n or n < 1 or n > 16 then
        status.text = " Raio tem de ser um numero de 1 a 16."
        f.dirty = true
        return
    end
    raio = math.floor(n)
    local custo = geo.custo(raio)
    if custo and custo > 0 then
        status.text = string.format(" Raio %d custa %d de energia (gratis ate %s).",
            raio, custo, tostring(gratis or "?"))
    else
        status.text = " Raio agora e' " .. raio .. ". Clique em Varrer."
    end
    f.dirty = true
end

local function mudaAncora()
    local a = ancora()
    local texto = ui.prompt("Onde esta o scanner? x y z (F3):",
        a and string.format("%d %d %d", a.x, a.y, a.z) or "", "Ancorar scanner")
    if not texto then return end
    if texto:match("^%s*$") then
        settings.unset("mosaic.geo.anchor") settings.save()
        status.text = " Ancora removida."
        f.dirty = true
        return
    end
    if not texto:match("^%s*-?%d+%s+-?%d+%s+-?%d+%s*$") then
        status.text = " Escreva tres numeros: 120 64 -30"
        f.dirty = true
        return
    end
    settings.set("mosaic.geo.anchor", texto:gsub("^%s+", ""):gsub("%s+$", ""))
    settings.save()
    status.text = " Scanner ancorado. A turtle aparece no 3D."
    f.dirty = true
end

local function mudaFatia()
    if faixaY then
        faixaY = nil
        status.text = " Altura: tudo."
        f.dirty = true
        return
    end
    local texto = ui.prompt("Faixa de altura, relativa ao scanner (ex: -3 3):",
        "-2 2", "Fatia")
    if not texto then return end
    local a, b = texto:match("^%s*(-?%d+)%s+(-?%d+)%s*$")
    if not a then
        status.text = " Escreva dois numeros: -2 2"
        f.dirty = true
        return
    end
    a, b = tonumber(a), tonumber(b)
    if a > b then a, b = b, a end
    faixaY = { a, b }
    resumo()
end

-- ---------------------------------------------------------------- layout

barra = ui.row(f, { bottom = 0, items = {
    { text = "&Analisar", onClick = analisa },
    { text = "&Varrer", onClick = varre },
    { text = "&3D", onClick = function()
        modo = (modo == "3d") and "lista" or "3d"
        f.dirty = true
    end },
    { text = "&Raio", alt = true, onClick = mudaRaio },
    { text = "&Fatia", alt = true, onClick = mudaFatia },
    { text = "A&ncora", alt = true, onClick = mudaAncora },
} })
status = f:add(ui.label { x = 1, above = barra, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

-- ---------------------------------------------------------------- eventos

local BATIDA = 0.2
local relogio = os.startTimer(BATIDA)

-- `mosaic.current()` devolve o ID, nao o processo - indexar aquilo custou um erro em
-- producao. Quem responde "estou numa parede?" e' o kernel, pela porta propria.
local function naParede()
    return mosaic.onMonitor and mosaic.onMonitor() ~= nil
end

-- Devolve true SO' se o clique caiu numa linha nossa.
--
-- Devolver true sempre engolia o evento antes de os botoes o verem: o `onEvent` do form roda
-- ANTES da distribuicao para os widgets, e `true` quer dizer "consumido". A barra inteira
-- ficou morta ate' o teste de clique no emulador apontar isso.
local function clique(y)
    local i = clicaveis[y]
    if not i then return false end
    alterna(i)
    return true
end

f.onEvent = function(_, ev, a, b, c)
    if ev == "timer" and a == relogio then
        relogio = os.startTimer(BATIDA)
        -- Gira sozinha na parede (la nao ha teclado) ou quando alguem ligou o giro. So'
        -- redesenha se a janela esta na frente: atras nao ha quem leia.
        if modo == "3d" and (gira or naParede()) then
            giro = (giro + 0.08) % (math.pi * 2)
            if naParede() or mosaic.focused() == mosaic.current() then f.dirty = true end
        end
        return true

    elseif ev == "monitor_touch" then
        -- Na parede o toque e' tudo que existe: sem teclado e sem arrastar. Ele liga e
        -- desliga o filtro da linha tocada, que e' a acao que mais rende ali.
        return clique(c)

    elseif ev == "mouse_click" and a == 1 then
        return clique(c)

    elseif ev == "mouse_scroll" and modo == "lista" then
        rolagem = math.max(0, rolagem + a)
        f.dirty = true
        return true

    elseif ev == "key" then
        if modo == "3d" then
            if a == keys.left then giro = giro - 0.15 f.dirty = true return true
            elseif a == keys.right then giro = giro + 0.15 f.dirty = true return true
            elseif a == keys.up then
                altura = math.min(1.4, altura + 0.12) f.dirty = true return true
            elseif a == keys.down then
                altura = math.max(-1.4, altura - 0.12) f.dirty = true return true
            elseif a == keys.equals or a == keys.numPadAdd then
                zoom = math.min(4, zoom * 1.2) f.dirty = true return true
            elseif a == keys.minus or a == keys.numPadSubtract then
                zoom = math.max(0.4, zoom / 1.2) f.dirty = true return true
            elseif a == keys.r then
                gira = not gira
                status.text = gira and " Girando sozinha." or " Giro parado."
                f.dirty = true
                return true
            end
        elseif modo == "lista" then
            if a == keys.up then rolagem = math.max(0, rolagem - 1) f.dirty = true return true
            elseif a == keys.down then rolagem = rolagem + 1 f.dirty = true return true
            end
        end
        if a == keys.m then soMinerios() status.text = " So minerios." return true
        elseif a == keys.t then
            ligados = nil
            status.text = " Tudo ligado."
            f.dirty = true
            return true
        end
    end
end

-- ---------------------------------------------------------------- inicio

local g = geo.find()
if g then
    -- Pergunta ao scanner ate' onde da' para ir de graca e ja comeca por ali: e' melhor
    -- oferecer o maior raio que FUNCIONA do que um numero redondo que falha.
    gratis = geo.limiteGratis()
    if gratis and gratis > 0 then raio = gratis end
    status.text = string.format(" Scanner pronto%s. Analisar ou Varrer.",
        (gratis and gratis > 0) and (", raio gratis ate " .. gratis) or "")
else
    status.text = " Nenhum Geo Scanner na rede deste computador."
end

f:run()
