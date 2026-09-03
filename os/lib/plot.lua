-- Grafico de funcao: eixos, marcacoes e a curva, desenhados num canvas de sub-pixel.
--
-- O lib/chart e' serie temporal e nao tem eixo nem zero; este e' `y = f(x)`.
--
--   local plot = mosaic.lib("plot")
--   local canvas = pixel.new(40, 12, colors.black)
--   plot.render(canvas, { { fn = math.sin, color = colors.lime } },
--               { x0 = -6.28, x1 = 6.28, y0 = -1.2, y1 = 1.2 })
--
-- Os rotulos dos eixos NAO saem daqui: celula com sub-pixel so' aceita duas cores e nenhum
-- texto, entao quem desenha numero e' o app, em volta do canvas. O plot devolve onde cada
-- marcacao caiu para o app saber em que linha escrever.
local plot = {}

-- Passo bonito de escala: 1, 2 ou 5 vezes uma potencia de dez.
function plot.step(span, alvo)
    alvo = math.max(1, alvo or 5)
    if span <= 0 then return 1 end
    local bruto = span / alvo
    local mag = 10 ^ math.floor(math.log(bruto) / math.log(10))
    local norm = bruto / mag
    local passo
    if norm < 1.5 then passo = 1
    elseif norm < 3 then passo = 2
    elseif norm < 7 then passo = 5
    else passo = 10 end
    return passo * mag
end

-- Valores de marcacao dentro de [lo, hi].
function plot.ticks(lo, hi, alvo)
    if hi <= lo then return { lo } end
    local passo = plot.step(hi - lo, alvo)
    local out = {}
    local t = math.ceil(lo / passo - 1e-9) * passo
    local guarda = 0
    while t <= hi + passo * 1e-9 and guarda < 1000 do
        -- Tira o lixo do acumulado: 0.30000000000000004 viraria rotulo.
        out[#out + 1] = math.abs(t) < passo * 1e-9 and 0 or t
        t = t + passo
        guarda = guarda + 1
    end
    return out
end

-- Coordenada do mundo para ponto do canvas (1-based, y crescendo para baixo).
function plot.toPixel(canvas, view, x, y)
    local sx = view.x1 - view.x0
    local sy = view.y1 - view.y0
    if sx == 0 or sy == 0 then return nil end
    local px = (x - view.x0) / sx * (canvas.w - 1) + 1
    local py = canvas.h - (y - view.y0) / sy * (canvas.h - 1)
    return px, py
end

-- Ponto do canvas de volta para o mundo. Serve para o cursor de leitura.
function plot.toWorld(canvas, view, px, py)
    local x = view.x0 + (px - 1) / math.max(1, canvas.w - 1) * (view.x1 - view.x0)
    local y = view.y0 + (canvas.h - py) / math.max(1, canvas.h - 1) * (view.y1 - view.y0)
    return x, y
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Uma amostra por coluna de ponto. `fn(x)` pode devolver nil quando nao existe valor.
function plot.sample(fn, view, largura)
    local pts = {}
    for i = 1, largura do
        local x = view.x0 + (i - 1) / math.max(1, largura - 1) * (view.x1 - view.x0)
        local ok, y = pcall(fn, x)
        pts[i] = (ok and finite(y)) and y or nil
    end
    return pts
end

-- Faixa de y que cabe as curvas. Descarta o que estourou, senao uma assintota sozinha
-- achataria o grafico inteiro numa linha.
function plot.autoRange(series, view, largura)
    local lo, hi = math.huge, -math.huge
    for _, s in ipairs(series) do
        for _, y in pairs(plot.sample(s.fn, view, largura)) do
            if y < lo then lo = y end
            if y > hi then hi = y end
        end
    end
    if lo > hi then return -1, 1 end
    if hi - lo < 1e-9 then lo, hi = lo - 1, hi + 1 end
    local folga = (hi - lo) * 0.08
    return lo - folga, hi + folga
end

-- Desenha eixos e curvas. Devolve { xTicks = { {valor, px}, ... }, yTicks = { {valor, py} } }
-- para o app escrever os numeros em volta.
function plot.render(canvas, series, view, opts)
    opts = opts or {}
    canvas:clear(opts.bg or colors.black)
    local corEixo = opts.axis or colors.gray
    local marcas = { xTicks = {}, yTicks = {} }

    -- Eixos: no zero quando ele aparece, encostados na borda quando nao.
    local _, py0 = plot.toPixel(canvas, view, view.x0, 0)
    local px0 = select(1, plot.toPixel(canvas, view, 0, view.y0))
    local eixoY = math.max(1, math.min(canvas.h, math.floor((py0 or canvas.h) + 0.5)))
    local eixoX = math.max(1, math.min(canvas.w, math.floor((px0 or 1) + 0.5)))

    for _, v in ipairs(plot.ticks(view.x0, view.x1, opts.xTicks or 4)) do
        local px = select(1, plot.toPixel(canvas, view, v, 0))
        if px then
            local col = math.floor(px + 0.5)
            marcas.xTicks[#marcas.xTicks + 1] = { v, col }
            for y = 1, canvas.h, 3 do canvas:set(col, y, opts.grid or corEixo) end
        end
    end
    for _, v in ipairs(plot.ticks(view.y0, view.y1, opts.yTicks or 3)) do
        local _, py = plot.toPixel(canvas, view, 0, v)
        if py then
            local lin = math.floor(py + 0.5)
            marcas.yTicks[#marcas.yTicks + 1] = { v, lin }
            for x = 1, canvas.w, 3 do canvas:set(x, lin, opts.grid or corEixo) end
        end
    end

    canvas:line(1, eixoY, canvas.w, eixoY, corEixo)
    canvas:line(eixoX, 1, eixoX, canvas.h, corEixo)

    -- Salto maior que a tela inteira e' assintota, nao curva: corta em vez de riscar.
    local limite = canvas.h
    for _, s in ipairs(series) do
        local pts = plot.sample(s.fn, view, canvas.w)
        local ppx, ppy
        for i = 1, canvas.w do
            local y = pts[i]
            if y == nil then
                ppx, ppy = nil, nil
            else
                local px, py = plot.toPixel(canvas, view,
                    view.x0 + (i - 1) / math.max(1, canvas.w - 1) * (view.x1 - view.x0), y)
                px, py = math.floor(px + 0.5), math.floor(py + 0.5)
                if ppx and math.abs(py - ppy) <= limite then
                    canvas:line(ppx, ppy, px, py, s.color or colors.lime)
                else
                    canvas:set(px, py, s.color or colors.lime)
                end
                ppx, ppy = px, py
            end
        end
    end
    return marcas
end

function plot.demo()
    local pixel = require("lib.pixel")

    -- passo e marcacoes
    assert(plot.step(10, 5) == 2, "passo de 10 em 5 pedacos deveria ser 2, deu " .. plot.step(10, 5))
    local t = plot.ticks(0, 10, 5)
    assert(#t == 6 and t[1] == 0 and t[6] == 10, "marcacoes de 0 a 10 sairam erradas: " .. #t)
    local t2 = plot.ticks(-1, 1, 4)
    assert(t2[1] == -1 and t2[#t2] == 1, "marcacoes de -1 a 1 nao pegaram as pontas")
    local zero = false
    for _, v in ipairs(t2) do if v == 0 then zero = true end end
    assert(zero, "a marcacao do zero tem de existir exatamente, sem sobra de virgula")
    assert(#plot.ticks(5, 5) == 1, "faixa de tamanho zero deveria dar uma marcacao so")

    -- ida e volta entre mundo e tela
    local canvas = pixel.new(20, 6, colors.black)
    local view = { x0 = -10, x1 = 10, y0 = -10, y1 = 10 }
    local px, py = plot.toPixel(canvas, view, -10, 10)
    assert(px == 1 and py == 1, "o canto de cima a esquerda deveria ser 1,1, deu " .. px .. "," .. py)
    local wx, wy = plot.toWorld(canvas, view, px, py)
    assert(math.abs(wx + 10) < 1e-9 and math.abs(wy - 10) < 1e-9, "a volta para o mundo nao fechou")

    -- a curva pinta alguma coisa
    local marcas = plot.render(canvas, { { fn = function(x) return x end, color = colors.white } }, view)
    assert(#marcas.xTicks > 0 and #marcas.yTicks > 0, "o render deveria devolver as marcacoes")
    local pintou = false
    for y = 1, canvas.h do
        for x = 1, canvas.w do
            if canvas:get(x, y) == colors.white then pintou = true end
        end
    end
    assert(pintou, "a reta y = x nao pintou nenhum ponto")

    -- buraco na funcao vira buraco no desenho, nao risco vertical
    local canvas2 = pixel.new(20, 6, colors.black)
    plot.render(canvas2, { { fn = function(x) if x > 0 then return nil end return 0 end,
        color = colors.white } }, view)
    local direita = 0
    for y = 1, canvas2.h do
        for x = math.floor(canvas2.w * 0.75), canvas2.w do
            if canvas2:get(x, y) == colors.white then direita = direita + 1 end
        end
    end
    assert(direita == 0, "onde a funcao nao existe nao pode ter curva desenhada")

    -- escala automatica
    local lo, hi = plot.autoRange({ { fn = math.sin } }, { x0 = 0, x1 = 6.28 }, 40)
    assert(lo < -0.9 and hi > 0.9, "a escala do seno deveria chegar perto de -1 e 1")
    assert(lo > -2 and hi < 2, "a escala do seno nao deveria abrir tanto: " .. lo .. " a " .. hi)

    return true
end

return plot
