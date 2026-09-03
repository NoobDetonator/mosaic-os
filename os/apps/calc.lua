-- Calculadora.
--
-- A conta em si mora no lib/expr; aqui e' so' a interface. O app tem abas (o campo `tab` de
-- cada widget, no mesmo esquema do apps/reactor.lua) e dois jeitos de digitar: o console, que
-- e' o padrao, e o teclado de botoes, que aparece por cima com F2.
local ui = mosaic.ui
local theme = mosaic.theme
local expr = mosaic.lib("expr")
local strutil = mosaic.lib("strutil")
local mcmath = mosaic.lib("mcmath")
local pixel = mosaic.lib("pixel")
local plot = mosaic.lib("plot")
local hal = mosaic.lib("hal")
local createlib = mosaic.lib("create")
local mesh = mosaic.lib("mesh")
local three = mosaic.lib("three")

local MAX_HIST = 200

local ctx = { vars = {}, deg = false }
local history = {}          -- { expr = , texto = , ok = }
local recall = nil          -- posicao na navegacao com a seta para cima
local mode = "conta"
local keypadOn = false

local f = ui.form()
local lista, box, estado, inserts
local formaDD, ocoCB, espBox, dimBox, estadoBlocos
local build, camada = nil, 1
local tresD, malha, cortadas = false, nil, 0
local giro, altura = 0.7, 0.5
local tresDCB
local fnBox, autoCB, estadoGraf
local view = { x0 = -10, x1 = 10, y0 = -5, y1 = 5 }
local curvas = {}
local gctx = { vars = { x = 0 }, deg = false }
local itensBox, stackDD, contDD, recBox, resBau, capBau, listaBau, estadoBaus
local rpmBox, chainBox, resCreate, listaCreate, estadoCreate
local cdata = createlib.load()
local abas = {}

-- ---------------------------------------------------------------- conta

local function refreshStatus()
    local partes = { "ans=" .. expr.format(ctx.vars.ans or 0) }
    local nomes = {}
    for k in pairs(ctx.vars) do if k ~= "ans" then nomes[#nomes + 1] = k end end
    table.sort(nomes)
    for _, k in ipairs(nomes) do partes[#partes + 1] = k .. "=" .. expr.format(ctx.vars[k]) end
    local s = " " .. table.concat(partes, "  ")
    local marca = ctx.deg and "DEG" or "RAD"
    -- O modo de angulo fica encostado a direita; se o resto nao couber, ele e' o que fica.
    local largura = tonumber(estado.w) or 20
    s = strutil.ellipsis(s, math.max(1, largura - #marca - 2))
    estado.text = strutil.pad(s, largura - #marca - 1) .. marca .. " "
end

local function push(texto, valor, ok)
    history[#history + 1] = { expr = texto, texto = valor, ok = ok,
        fg = (not ok) and colors.red or nil }
    if #history > MAX_HIST then table.remove(history, 1) end
    lista:setItems(history)
    -- Historico e' registro, nao lista de escolha: sem realce, so' rolando para o fim.
    lista.selected = nil
    lista.scroll = math.max(0, #history - (lista.h or 1))
    recall = nil
end

local function evaluate()
    local texto = box.text
    if texto:match("^%s*$") then return end
    local v, err, col, nome = expr.eval(texto, ctx)
    if v == nil then
        push(texto, "erro: " .. tostring(err) .. (col and (" (col " .. col .. ")") or ""), false)
    else
        ctx.vars.ans = v
        push(texto, (nome and (nome .. " = ") or "") .. expr.format(v), true)
    end
    box:setText("")
    refreshStatus()
    f.dirty = true
end

-- Seta para cima e para baixo andam pelo historico, como num terminal.
local function recallStep(dir)
    if #history == 0 then return end
    if recall == nil then
        recall = dir < 0 and #history + 1 or 0
    end
    local i = recall + dir
    if i < 1 then i = 1 end
    if i > #history then
        recall = #history + 1
        box:setText("")
        f.dirty = true
        return
    end
    recall = i
    box:setText(history[i].expr)
    f.dirty = true
end

-- ---------------------------------------------------------------- teclado e insercoes

local function insert(s)
    box:insert(s)
    f:setFocus(box)
    f.dirty = true
end

local function backspace()
    local t, c = box.text, box.cursor or #box.text
    if c > 0 then
        box:setText(t:sub(1, c - 1) .. t:sub(c + 1))
        box.cursor = c - 1
    end
    f:setFocus(box)
    f.dirty = true
end

-- Uma linha do teclado: os botoes ficam lado a lado a partir de x = 2, e o que nao couber
-- na largura some em vez de vazar pela borda.
local function keyRow(bottom, specs)
    local feitos = {}
    for _, spec in ipairs(specs) do
        local b = f:add(ui.button {
            x = 1, y = 1, bottom = bottom, text = spec[1], alt = spec[3], tab = "conta", pad = true,
            onClick = spec[2],
        })
        feitos[#feitos + 1] = b
    end
    -- Posiciona depois de existir: o `bottom` cuida do y, aqui so' o x.
    local linha = { buttons = feitos }
    linha.place = function(W)
        local x = 2
        for _, b in ipairs(feitos) do
            b.x = x
            b.visible = keypadOn and mode == "conta" and (x + b.w - 1) <= W
            x = x + b.w + 1
        end
    end
    return linha
end

-- ---------------------------------------------------------------- abas

local function setMode(m)
    mode = m
    for _, w in ipairs(f.widgets) do
        if w.tab then w.visible = (w.tab == m) end
    end
    for _, b in ipairs(abas) do b.alt = (b.modo ~= m) end
    f.scroll = 0
    f:layout()
    f.dirty = true
end

local function applyKeypad()
    for _, w in ipairs(f.widgets) do
        if w.pad then w.visible = keypadOn and mode == "conta" end
    end
    if inserts then
        inserts.visible = (not keypadOn) and mode == "conta"
        for _, b in ipairs(inserts.buttons) do b.visible = inserts.visible end
    end
    f:layout()
    f.dirty = true
end

-- ---------------------------------------------------------------- montagem

-- De baixo para cima: abas, estado, entrada, teclado (ou fila), e o historico no que sobrar.
local navX = 1
local function aba(label, m)
    local b
    b = f:add(ui.button { x = navX, bottom = 0, text = label, pinned = true,
        alt = (m ~= mode), onClick = function() setMode(m) end })
    b.modo = m
    navX = navX + b:width() + 1
    abas[#abas + 1] = b
    return b
end
aba("Conta", "conta")
aba("Blocos", "blocos")
aba("Grafico", "grafico")
aba("Baus", "baus")
aba("Create", "create")

estado = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "", tab = "conta",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
f:add(ui.label { x = 1, bottom = 2, text = ">", tab = "conta" })
box = f:add(ui.textbox { x = 3, bottom = 2, w = -3, tab = "conta",
    placeholder = "digite a conta e aperte Enter", onEnter = evaluate })

-- Fila curta do modo console: so' o que e' chato de digitar.
inserts = ui.row(f, { bottom = 3, items = {
    { text = "&Funcoes", onClick = function()
        local nomes = expr.functionNames()
        local opts = {}
        for _, n in ipairs(nomes) do
            opts[#opts + 1] = { text = " " .. n .. "  -  " .. expr.functions[n].help }
        end
        local idx = ui.menu(opts, 2, 2, 34, { maxH = 12 })
        f.dirty = true
        if idx then insert(nomes[idx] .. "(") end
    end },
    { text = "sqrt(", alt = true, onClick = function() insert("sqrt(") end },
    { text = "^", alt = true, onClick = function() insert("^") end },
    { text = "pi", alt = true, onClick = function() insert("pi") end },
    { text = "ans", alt = true, onClick = function() insert("ans") end },
    { text = "&Teclado", alt = true, onClick = function() keypadOn = true applyKeypad() end },
} })
for _, b in ipairs(inserts.buttons) do b.tab = "conta" end

-- Teclado: quatro linhas, digitos e operadores a esquerda, funcoes a direita.
local function ins(s) return function() insert(s) end end
local linhas = {
    keyRow(6, { { "7", ins("7") }, { "8", ins("8") }, { "9", ins("9") }, { "/", ins("/") },
                { "(", ins("("), true }, { ")", ins(")"), true }, { "^", ins("^"), true } }),
    keyRow(5, { { "4", ins("4") }, { "5", ins("5") }, { "6", ins("6") }, { "*", ins("*") },
                { "pi", ins("pi"), true }, { "ans", ins("ans"), true }, { "!", ins("!"), true } }),
    keyRow(4, { { "1", ins("1") }, { "2", ins("2") }, { "3", ins("3") }, { "-", ins("-") },
                { "sqrt(", ins("sqrt("), true }, { "sin(", ins("sin("), true } }),
    keyRow(3, { { "0", ins("0") }, { ".", ins(".") }, { "+", ins("+") },
                { "=", evaluate }, { "C", function() box:setText("") f.dirty = true end, true },
                { "<-", backspace, true },
                { "Fechar", function() keypadOn = false applyKeypad() end, true } }),
}

lista = f:add(ui.list {
    x = 1, y = 1, w = "fill", tab = "conta",
    render = function(it)
        local largura = (tonumber(lista.w) or 20) - 1
        if not it.ok then
            -- Corta no fim, nao no meio: o comeco da mensagem e' o que diz o que houve.
            return " " .. strutil.pad(it.expr .. "  " .. it.texto, largura)
        end
        local dir = it.texto
        local espaco = largura - #dir - 2
        if espaco < 6 then return " " .. strutil.ellipsis(it.expr .. " = " .. dir, largura) end
        return " " .. strutil.pad(strutil.ellipsis(it.expr, espaco), espaco) .. " " .. dir
    end,
})
-- A altura do historico depende do que esta em baixo, e isso muda com o teclado; nenhuma
-- ancora fixa daria conta, entao ela e calculada aqui.
lista.onLayout = function(self, W, H)
    for _, linha in ipairs(linhas) do linha.place(W) end
    -- A fila quebra em mais de uma linha quando a janela e' estreita; usar H - 3 fixo
    -- deixava a lista passar por cima dela.
    local base = keypadOn and (H - 6) or math.min(inserts.y or (H - 3), H - 3)
    self.h = math.max(1, base - self.y)
end

-- ---------------------------------------------------------------- aba Blocos

-- Quantos sub-pixels por bloco. Um bloco de 1 ponto vira ilegivel numa forma pequena, e
-- 4 pontos numa forma grande nao caberia: o desenho escolhe a maior escala que couber.
local function escala(canvas, r)
    return math.max(1, math.min(math.floor(canvas.w / r.w), math.floor(canvas.h / r.d), 4))
end

local PREVIEW_TOP = 3

-- A malha so' e' montada quando o 3D esta ligado: numa forma grande ela custa mais que o
-- desenho, e no modo de camadas ninguem olha para ela.
local function montarMalha()
    if not build then malha = nil return end
    local m, faltando = mesh.voxels(build.layers, build.w, build.h, build.d, { maxFaces = 6000 })
    m:center():normalizeScale()
    malha, cortadas = m, faltando
end

local function draw3D(t, cols, rows)
    if not malha then montarMalha() end
    if not malha then return end
    local canvas = pixel.new(cols, rows, colors.black)
    local frame = three.frame(canvas)
    frame:orbit({ 0, 0, 0 }, 2.2, giro, altura)
    frame:clear(colors.black)
    frame:draw({ { model = malha } })
    canvas:render(t, 1, PREVIEW_TOP)
end

local function drawPreview(t)
    local W, H = t.getSize()
    local cols, rows = W, H - PREVIEW_TOP - 1
    if not build or cols < 4 or rows < 2 then return end
    if tresD then return draw3D(t, cols, rows) end
    local canvas = pixel.new(cols, rows, colors.black)
    local grid = build.layers[camada]
    if grid then
        local s = escala(canvas, build)
        local ox = math.floor((canvas.w - build.w * s) / 2)
        local oy = math.floor((canvas.h - build.d * s) / 2)
        for z = 1, build.d do
            local linha = grid[z]
            for x = 1, build.w do
                if linha[x] then
                    for dy = 0, s - 1 do
                        for dx = 0, s - 1 do
                            canvas:set(ox + (x - 1) * s + dx + 1, oy + (z - 1) * s + dy + 1, colors.white)
                        end
                    end
                end
            end
        end
    end
    canvas:render(t, 1, PREVIEW_TOP)
end

local function statusBlocos()
    if not build then estadoBlocos.text = " nada gerado ainda" return end
    local partes = {
        build.total .. " blocos",
        mcmath.describe(build.total, mcmath.STACK, 27, "bau", "baus"),
        build.w .. "x" .. build.h .. "x" .. build.d,
    }
    if tresD then
        partes[#partes + 1] = (malha and malha:count() or 0) .. " tri"
        if cortadas > 0 then partes[#partes + 1] = "CORTOU " .. cortadas .. " faces" end
        partes[#partes + 1] = "setas giram"
    elseif build.h > 1 then
        partes[#partes + 1] = "camada " .. camada .. "/" .. build.h .. " (" .. build.perLayer[camada] .. ")"
    end
    estadoBlocos.text = " " .. strutil.ellipsis(table.concat(partes, " | "),
        (tonumber(estadoBlocos.w) or 40) - 2)
end

local function gerar()
    local shape = mcmath.shapes[formaDD.selected or 1]
    local r, motivo = mcmath.build(shape.id, {
        w = tonumber(dimBox.w.text), h = tonumber(dimBox.h.text), d = tonumber(dimBox.d.text),
        hollow = ocoCB.checked, thickness = tonumber(espBox.text),
    })
    if not r then ui.msgbox(tostring(motivo), "Blocos") return end
    build = r
    malha = nil
    camada = math.min(camada, r.h)
    -- Os campos voltam com o que a forma realmente usou: circulo ignora profundidade,
    -- esfera iguala os tres. Deixar o digitado na tela seria mentir sobre o desenho.
    dimBox.w:setText(tostring(r.w))
    dimBox.h:setText(tostring(r.h))
    dimBox.d:setText(tostring(r.d))
    statusBlocos()
    f.dirty = true
end

do
    local nomes = {}
    for _, sh in ipairs(mcmath.shapes) do nomes[#nomes + 1] = sh.name end

    f:add(ui.label { x = 1, y = 1, text = "Forma:", tab = "blocos" })
    formaDD = f:add(ui.dropdown { x = 8, y = 1, w = 12, items = nomes, selected = 3, tab = "blocos",
        onChange = function() gerar() end })
    ocoCB = f:add(ui.checkbox { x = 21, y = 1, text = "&Oco", tab = "blocos",
        onChange = function() gerar() end })
    f:add(ui.label { x = 29, y = 1, text = "Esp:", tab = "blocos" })
    espBox = f:add(ui.textbox { x = 34, y = 1, w = 5, text = "1", tab = "blocos",
        onEnter = function() gerar() end })
    tresDCB = f:add(ui.checkbox { x = 40, y = 1, text = "&3D", tab = "blocos",
        onChange = function(_, v)
            tresD = v
            if v and not malha then montarMalha() end
            statusBlocos()
            f.dirty = true
        end })

    dimBox = {}
    local x = 1
    for _, campo in ipairs({ { "w", "L:" }, { "h", "A:" }, { "d", "P:" } }) do
        f:add(ui.label { x = x, y = 2, text = campo[2], tab = "blocos" })
        dimBox[campo[1]] = f:add(ui.textbox { x = x + 3, y = 2, w = 6, text = "15", tab = "blocos",
            onEnter = function() gerar() end })
        x = x + 10
    end
    f:add(ui.button { x = x + 1, y = 2, text = "&Gerar", tab = "blocos", onClick = gerar })

    estadoBlocos = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "", tab = "blocos",
        bg = theme.taskbarBg, fg = theme.taskbarFg })
end

-- ---------------------------------------------------------------- aba Grafico

local GRAF_LEFT = 7          -- colunas 1..6 ficam para os numeros do eixo y
local CORES = { colors.lime, colors.yellow }

-- Rotulo de eixo curto: %.0f quando e' inteiro, duas casas quando nao, sem zero a toa.
local function eixoLabel(v)
    if math.abs(v) < 1e-9 then return "0" end
    if v == math.floor(v) and math.abs(v) < 1e5 then return string.format("%.0f", v) end
    local t = string.format("%.2f", v)
    t = (t:gsub("0+$", ""))
    return (t:gsub("%.$", ""))
end

-- Le as duas caixas e prepara as funcoes. So' roda quando o texto muda, nao a cada quadro.
local function compilar()
    curvas = {}
    for i, caixa in ipairs(fnBox) do
        local texto = caixa.text
        if texto and not texto:match("^%s*$") then
            local fn, err, col = expr.compile(texto)
            if not fn then
                ui.msgbox("y" .. i .. ": " .. tostring(err) .. " (col " .. tostring(col) .. ")", "Grafico")
            else
                curvas[#curvas + 1] = { cor = CORES[i] or colors.white, fn = function(x)
                    gctx.vars.x = x
                    gctx.deg = ctx.deg
                    return (fn(gctx))
                end }
            end
        end
    end
end

-- Quantas celulas o desenho ocupa. O rodape precisa do mesmo numero que o desenho, senao a
-- escala automatica que ele anuncia nao e' a que aparece na tela.
local function grafCells()
    local W, H = (f.term or term.current()).getSize()
    return W - GRAF_LEFT + 1, (H - 3) - 3 + 1
end

local function statusGraf()
    local cols, rows = grafCells()
    if autoCB.checked and #curvas > 0 and cols >= 8 and rows >= 2 then
        local serie = {}
        for _, c in ipairs(curvas) do serie[#serie + 1] = { fn = c.fn } end
        view.y0, view.y1 = plot.autoRange(serie, view, cols * 2)
    end
    local meio = (view.x0 + view.x1) / 2
    local partes = { "x " .. eixoLabel(view.x0) .. ".." .. eixoLabel(view.x1),
                     "y " .. eixoLabel(view.y0) .. ".." .. eixoLabel(view.y1),
                     "x=" .. eixoLabel(meio) }
    for i, c in ipairs(curvas) do
        local ok, v = pcall(c.fn, meio)
        partes[#partes + 1] = "y" .. i .. "=" .. ((ok and v) and expr.format(v) or "-")
    end
    estadoGraf.text = " " .. strutil.ellipsis(table.concat(partes, " | "),
        (tonumber(estadoGraf.w) or 40) - 2)
end

local function drawGrafico(t)
    local W, H = t.getSize()
    local topo, base = 3, H - 3
    local cols, rows = W - GRAF_LEFT + 1, base - topo + 1
    if cols < 8 or rows < 2 then return end

    local canvas = pixel.new(cols, rows, colors.black)
    local serie = {}
    for _, c in ipairs(curvas) do serie[#serie + 1] = { fn = c.fn, color = c.cor } end
    local marcas = plot.render(canvas, serie, view, { axis = colors.gray })

    -- Cruz de leitura no meio da janela: e' o "onde estou" sem inventar um modo novo.
    local meioPx = math.floor(canvas.w / 2)
    for y = 1, canvas.h, 2 do canvas:set(meioPx, y, colors.red) end
    canvas:render(t, GRAF_LEFT, topo)

    -- Numeros dos eixos, fora do canvas: celula com sub-pixel nao aceita texto.
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.mutedFg)
    local usada = {}
    for _, m in ipairs(marcas.yTicks) do
        local linha = topo + math.floor((m[2] - 1) / 3)
        if not usada[linha] and linha >= topo and linha <= base then
            usada[linha] = true
            t.setCursorPos(1, linha)
            t.write(strutil.pad(strutil.ellipsis(eixoLabel(m[1]), 6), 6, "right"))
        end
    end
    t.setCursorPos(1, base + 1)
    t.write(string.rep(" ", W))
    for _, m in ipairs(marcas.xTicks) do
        local col = GRAF_LEFT + math.floor((m[2] - 1) / 2)
        local rot = eixoLabel(m[1])
        local x = math.max(1, math.min(W - #rot, col - math.floor(#rot / 2)))
        t.setCursorPos(x, base + 1)
        t.write(rot)
    end
end

local function redesenhar()
    compilar()
    statusGraf()
    f.dirty = true
end

do
    fnBox = {}
    for i = 1, 2 do
        f:add(ui.label { x = 1, y = i, text = "y" .. i .. "=", tab = "grafico" })
        fnBox[i] = f:add(ui.textbox { x = 5, y = i, w = -18, tab = "grafico",
            text = i == 1 and "sin(x)" or "", placeholder = "funcao de x",
            onEnter = function() redesenhar() f:setFocus(nil) end })
    end
    autoCB = f:add(ui.checkbox { right = 1, y = 1, text = "&Auto", checked = true, tab = "grafico",
        onChange = function() redesenhar() end })
    f:add(ui.button { right = 1, y = 2, text = "&Desenhar", tab = "grafico",
        onClick = function() redesenhar() end })
    estadoGraf = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "", tab = "grafico",
        bg = theme.taskbarBg, fg = theme.taskbarFg })
end

-- Setas andam pelo grafico, PageUp e PageDown aproximam e afastam. So' quando o foco nao
-- esta numa caixa de texto, senao a seta andaria o cursor do texto.
local function noGrafico()
    if mode ~= "grafico" then return false end
    for _, c in ipairs(fnBox) do if f.focused == c then return false end end
    return true
end

local function pan(fx, fy)
    local lx, ly = view.x1 - view.x0, view.y1 - view.y0
    view.x0, view.x1 = view.x0 + lx * fx, view.x1 + lx * fx
    if not autoCB.checked then
        view.y0, view.y1 = view.y0 + ly * fy, view.y1 + ly * fy
    end
    statusGraf()
    f.dirty = true
end

local function zoom(k)
    local cx, cy = (view.x0 + view.x1) / 2, (view.y0 + view.y1) / 2
    local lx, ly = (view.x1 - view.x0) * k / 2, (view.y1 - view.y0) * k / 2
    view.x0, view.x1 = cx - lx, cx + lx
    if not autoCB.checked then view.y0, view.y1 = cy - ly, cy + ly end
    statusGraf()
    f.dirty = true
end

-- ---------------------------------------------------------------- aba Baus

local TAMANHOS = { "64", "16", "1" }

local function baseBau()
    local st = tonumber(TAMANHOS[stackDD.selected or 1]) or mcmath.STACK
    local c = mcmath.containers[contDD.selected or 1]
    return st, c
end

local function calcBaus()
    local st, c = baseBau()
    local n = math.max(0, math.floor(tonumber(itensBox.text) or 0))
    resBau.text = n .. " itens = " .. mcmath.describe(n, st, c.slots, c.name:lower(), c.plural)
    local quantos = math.max(0, math.floor(tonumber(recBox.text) or 0))
    capBau.text = "= " .. mcmath.capacity(quantos, st, c.slots) .. " itens"
    estadoBaus.text = string.format(" %s: %d slots x %d = %d itens por %s",
        c.name, c.slots, st, c.slots * st, c.name:lower())
    f.dirty = true
end

-- Le tudo que estiver ligado ao computador. O CC nao diz o tamanho de stack de cada item,
-- entao a conta usa o tamanho escolhido em cima, e nao o do jogo.
local function lerBaus()
    local st, c = baseBau()
    local ok, itens = pcall(hal.items)
    if not ok or type(itens) ~= "table" then
        ui.msgbox("Nao consegui ler: " .. tostring(itens), "Baus")
        return
    end
    local linhas = {}
    for id, info in pairs(itens) do
        linhas[#linhas + 1] = { nome = strutil.itemName(info.name or id), n = info.count or 0 }
    end
    table.sort(linhas, function(a, b) return a.n > b.n end)
    if #linhas == 0 then
        listaBau:setItems({ { nome = "nenhum inventario ligado no computador", n = -1 } })
    else
        listaBau:setItems(linhas)
    end
    f.dirty = true
end

do
    f:add(ui.label { x = 1, y = 1, text = "Itens:", tab = "baus" })
    itensBox = f:add(ui.textbox { x = 8, y = 1, w = 9, text = "1729", tab = "baus",
        onEnter = calcBaus, onChange = calcBaus })
    f:add(ui.label { x = 18, y = 1, text = "St:", tab = "baus" })
    stackDD = f:add(ui.dropdown { x = 22, y = 1, w = 6, items = TAMANHOS, tab = "baus",
        onChange = calcBaus })
    f:add(ui.label { x = 29, y = 1, text = "Rec:", tab = "baus" })
    do
        local nomes = {}
        for _, c in ipairs(mcmath.containers) do nomes[#nomes + 1] = c.name end
        contDD = f:add(ui.dropdown { x = 34, y = 1, w = 14, items = nomes, tab = "baus",
            onChange = calcBaus })
    end

    resBau = f:add(ui.label { x = 1, y = 2, w = "fill", text = "", tab = "baus",
        fg = theme.accent })

    f:add(ui.label { x = 1, y = 3, text = "Recip:", tab = "baus" })
    recBox = f:add(ui.textbox { x = 8, y = 3, w = 6, text = "3", tab = "baus",
        onEnter = calcBaus, onChange = calcBaus })
    capBau = f:add(ui.label { x = 15, y = 3, w = -30, text = "", tab = "baus" })
    f:add(ui.button { right = 1, y = 3, text = "&Ler baus", tab = "baus", onClick = lerBaus })

    estadoBaus = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "", tab = "baus",
        bg = theme.taskbarBg, fg = theme.taskbarFg })
    listaBau = f:add(ui.list { x = 1, y = 5, w = "fill", fillTo = estadoBaus, tab = "baus",
        items = { { nome = "clique em Ler baus para contar o que esta ligado no computador",
            n = -1 } },
        render = function(it)
            local largura = (tonumber(listaBau.w) or 40) - 1
            if it.n < 0 then return " " .. it.nome end
            local st, c = baseBau()
            local dir = mcmath.describe(it.n, st, c.slots, c.name:lower(), c.plural)
            local espaco = largura - #dir - 2
            if espaco < 6 then return " " .. strutil.ellipsis(it.nome .. " " .. dir, largura) end
            return " " .. strutil.pad(strutil.ellipsis(it.nome, espaco), espaco) .. " " .. dir
        end })
end

-- ---------------------------------------------------------------- aba Create

local function rpmFinal()
    local pares, motivo = createlib.parseChain(chainBox.text)
    if not pares then return nil, motivo end
    return createlib.speed(tonumber(rpmBox.text) or 0, pares)
end

local function calcCreate()
    local v, estourou = rpmFinal()
    if not v then
        resCreate.text = "engrenagens: " .. tostring(estourou)
        resCreate.fg = colors.red
        estadoCreate.text = " corrija a corrente de engrenagens"
        f.dirty = true
        return
    end
    resCreate.fg = estourou and colors.red or theme.accent
    resCreate.text = string.format("saida: %s RPM%s", expr.format(v),
        estourou and ("  ACIMA DO TETO DE " .. createlib.RPM_MAX) or "")

    local b = createlib.budget(cdata.items, v)
    local marca = b.aConferir > 0 and ("  (" .. b.aConferir .. " a conferir)") or ""
    estadoCreate.text = strutil.ellipsis(string.format(" gasta %s / aguenta %s | %s %s%s",
        expr.format(b.impacto), expr.format(b.capacidade),
        b.ok and "sobra" or "FALTA", expr.format(math.abs(b.saldo)), marca),
        (tonumber(estadoCreate.w) or 40) - 1)
    listaCreate:setItems(cdata.items, true)
    f.dirty = true
end

local function editarQtd()
    local it = listaCreate:getSelected()
    if not it then return end
    local novo = ui.prompt("Quantos '" .. it.name .. "'?", tostring(it.qty), "Quantidade")
    if novo then
        it.qty = math.max(0, math.floor(tonumber(novo) or 0))
        calcCreate()
    end
end

local function editarBase()
    local it = listaCreate:getSelected()
    if not it then return end
    local novo = ui.prompt(it.name .. " - SU por RPM (veja nos Oculos de Engenheiro):",
        tostring(it.base), "Valor base")
    if novo and tonumber(novo) then
        it.base = tonumber(novo)
        it.check = false          -- conferido por voce: para de aparecer com interrogacao
        calcCreate()
    end
end

do
    f:add(ui.label { x = 1, y = 1, text = "RPM:", tab = "create" })
    rpmBox = f:add(ui.textbox { x = 6, y = 1, w = 7, text = tostring(cdata.rpm), tab = "create",
        onEnter = calcCreate, onChange = calcCreate })
    f:add(ui.label { x = 15, y = 1, text = "Engrenagens:", tab = "create" })
    chainBox = f:add(ui.textbox { x = 28, y = 1, w = -28, text = cdata.chain, tab = "create",
        placeholder = "8:24, 24:8", onEnter = calcCreate, onChange = calcCreate })
    resCreate = f:add(ui.label { x = 1, y = 2, w = "fill", text = "", tab = "create",
        fg = theme.accent })

    local barra = ui.row(f, { bottom = 2, items = {
        { text = "&Quantidade", onClick = editarQtd },
        { text = "&Base", alt = true, onClick = editarBase },
        { text = "&Salvar", alt = true, onClick = function()
            cdata.rpm = tonumber(rpmBox.text) or cdata.rpm
            cdata.chain = chainBox.text
            if createlib.save(cdata) then mosaic.notify("Tabela do Create salva")
            else ui.msgbox("Nao consegui gravar.", "Create") end
        end },
        { text = "&Padrao", alt = true, onClick = function()
            if ui.confirm("Voltar a tabela de fabrica? Os valores que voce conferiu se perdem.",
                "Create") then
                cdata = createlib.load and createlib.load() or cdata
                fs.delete(createlib.FILE)
                cdata = createlib.load()
                rpmBox:setText(tostring(cdata.rpm))
                chainBox:setText(cdata.chain)
                calcCreate()
            end
        end },
    } })
    for _, b in ipairs(barra.buttons) do b.tab = "create" end
    barra.tab = "create"

    estadoCreate = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "", tab = "create",
        bg = theme.taskbarBg, fg = theme.taskbarFg })
    listaCreate = f:add(ui.list { x = 1, y = 3, w = "fill", fillTo = barra, tab = "create",
        items = cdata.items, render = function(it)
            local largura = (tonumber(listaCreate.w) or 40) - 1
            local v = rpmFinal() or 0
            local su = createlib.su(it.base, v) * it.qty
            local dir = string.format("x%d  base %s%s  %s SU", it.qty, expr.format(it.base),
                it.check and "?" or " ", expr.format(su))
            local marca = it.kind == "gerador" and "+" or "-"
            local espaco = largura - #dir - 3
            if espaco < 6 then return " " .. strutil.ellipsis(it.name .. " " .. dir, largura) end
            return " " .. marca .. " " .. strutil.pad(strutil.ellipsis(it.name, espaco), espaco) .. " " .. dir
        end })
    listaCreate.onActivate = editarQtd
end

f.onDraw = function(_, t)
    if mode == "blocos" then drawPreview(t)
    elseif mode == "grafico" then drawGrafico(t) end
end

-- ---------------------------------------------------------------- eventos

f.onEvent = function(_, ev, a)
    if ev == "key" then
        if a == keys.f2 and mode == "conta" then
            keypadOn = not keypadOn
            applyKeypad()
            return true
        elseif a == keys.f3 then
            ctx.deg = not ctx.deg
            refreshStatus()
            f.dirty = true
            return true
        elseif noGrafico() then
            if a == keys.left then pan(-0.2, 0) return true
            elseif a == keys.right then pan(0.2, 0) return true
            elseif a == keys.up then pan(0, 0.2) return true
            elseif a == keys.down then pan(0, -0.2) return true
            elseif a == keys.pageUp then zoom(0.5) return true
            elseif a == keys.pageDown then zoom(2) return true
            end
        elseif mode == "blocos" and tresD and build then
            local passo = 0.25
            if a == keys.left then giro = giro - passo f.dirty = true return true
            elseif a == keys.right then giro = giro + passo f.dirty = true return true
            elseif a == keys.up then
                altura = math.min(1.4, altura + passo) f.dirty = true return true
            elseif a == keys.down then
                altura = math.max(-1.4, altura - passo) f.dirty = true return true
            end
        elseif mode == "blocos" and build and build.h > 1 then
            if a == keys.pageUp then
                camada = math.min(build.h, camada + 1) statusBlocos() f.dirty = true return true
            elseif a == keys.pageDown then
                camada = math.max(1, camada - 1) statusBlocos() f.dirty = true return true
            end
        end
        if mode == "conta" and f.focused == box then
            if a == keys.up then recallStep(-1) return true
            elseif a == keys.down then recallStep(1) return true end
        end
    end
end

applyKeypad()
setMode("conta")
f:layout()
gerar()
redesenhar()
calcBaus()
calcCreate()
refreshStatus()
f:setFocus(box)
f:run()
