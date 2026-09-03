-- Calculadora.
--
-- A conta em si mora no lib/expr; aqui e' so' a interface. O app tem abas (o campo `tab` de
-- cada widget, no mesmo esquema do apps/reactor.lua) e dois jeitos de digitar: o console, que
-- e' o padrao, e o teclado de botoes, que aparece por cima com F2.
local ui = mosaic.ui
local theme = mosaic.theme
local expr = mosaic.lib("expr")
local strutil = mosaic.lib("strutil")

local MAX_HIST = 200

local ctx = { vars = {}, deg = false }
local history = {}          -- { expr = , texto = , ok = }
local recall = nil          -- posicao na navegacao com a seta para cima
local mode = "conta"
local keypadOn = false

local f = ui.form()
local lista, box, estado, inserts, teclado
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
    local largura = estado.w or 20
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

estado = f:add(ui.label { x = 1, bottom = 1, w = "fill", text = "",
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
        local largura = (lista.w or 20) - 1
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
        elseif mode == "conta" and f.focused == box then
            if a == keys.up then recallStep(-1) return true
            elseif a == keys.down then recallStep(1) return true end
        end
    end
end

applyKeypad()
setMode("conta")
f:layout()
refreshStatus()
f:setFocus(box)
f:run()
