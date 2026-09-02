-- Graficos de linha em sub-pixel, para painel de monitor ou janela.
-- Usa lib/pixel (teletext 2x3), entao um grafico de 25 x 6 celulas tem 50 x 18 pontos.
--
--   local chart = mosaic.lib("chart")
--   chart.line(term.current(), { x = 2, y = 3, w = 25, h = 6, data = historico,
--                                min = 0, fg = colors.lime, fill = true })
--
-- Serie com menos pontos que a largura e interpolada; com mais, e reamostrada.
-- Nos dois casos toda coluna recebe um ponto, entao a linha nunca sai tracejada.

local pixel = require("lib.pixel")

local chart = {}

-- Menor e maior valor da serie, para quando min/max nao vem de fora.
local function extent(data, n)
    local lo, hi = data[1], data[1]
    for i = 2, n do
        if data[i] < lo then lo = data[i] end
        if data[i] > hi then hi = data[i] end
    end
    return lo, hi
end

-- o: x, y, w, h em CELULAS; data (array de numeros); min, max (opcionais);
--    fg, bg (cores); fill (area preenchida em vez de so a linha).
function chart.line(t, o)
    local canvas = pixel.new(o.w, o.h, o.bg or colors.black)
    local data, fg = o.data or {}, o.fg or colors.lime
    local n = #data
    if n == 0 then
        canvas:render(t, o.x or 1, o.y or 1)
        return
    end

    local pw, ph = canvas.w, canvas.h
    local dlo, dhi = extent(data, n)
    local lo = o.min or dlo
    local hi = o.max or dhi
    if hi <= lo then hi = lo + 1 end   -- serie constante ainda tem de desenhar

    local function rowOf(v)
        local f = (v - lo) / (hi - lo)
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        -- linha 1 e o topo do canvas, entao valor alto = linha baixa
        return ph - math.floor(f * (ph - 1) + 0.5)
    end

    local prev
    for cx = 1, pw do
        -- Posicao fracionaria dentro da serie para esta coluna de pixels.
        local f = (n == 1) and 1 or (1 + (cx - 1) * (n - 1) / (pw - 1))
        local i0 = math.floor(f)
        local i1 = math.min(n, i0 + 1)
        local v = data[i0] + (data[i1] - data[i0]) * (f - i0)
        local cy = rowOf(v)
        if o.fill then
            for y = cy, ph do canvas:set(cx, y, fg) end
        else
            -- Liga com a coluna anterior, senao degrau vira linha pontilhada.
            local from = prev or cy
            local step = (cy >= from) and 1 or -1
            for y = from, cy, step do canvas:set(cx, y, fg) end
        end
        prev = cy
    end
    canvas:render(t, o.x or 1, o.y or 1)
end

-- Historico de tamanho fixo: empurra e descarta o mais antigo.
-- Serve para alimentar chart.line com uma janela deslizante de amostras.
function chart.history(size)
    return {
        size = size, n = 0, data = {},
        push = function(self, v)
            self.data[#self.data + 1] = v
            while #self.data > self.size do table.remove(self.data, 1) end
            self.n = #self.data
            return self
        end,
        last = function(self) return self.data[#self.data] end,
        -- Queda por minuto na janela, dado o intervalo entre amostras em segundos.
        -- nil com amostras de menos para valer alguma coisa; 0 quando nao esta caindo
        -- (subindo nao e' "queda negativa": seria projecao sem sentido).
        fallPerMin = function(self, intervalSecs)
            if #self.data < 5 then return nil end
            local queda = self.data[1] - self.data[#self.data]
            if queda <= 0 then return 0 end
            return queda / ((#self.data - 1) * intervalSecs) * 60
        end,
        -- Media da janela, para suavizar leitura que oscila muito.
        mean = function(self)
            if #self.data == 0 then return 0 end
            local s = 0
            for i = 1, #self.data do s = s + self.data[i] end
            return s / #self.data
        end,
    }
end

function chart.demo()
    -- Escala: serie constante nao pode estourar na divisao por zero.
    local flat = { 5, 5, 5, 5 }
    local lo, hi = extent(flat, 4)
    assert(lo == 5 and hi == 5, "extent errado em serie constante")

    local lo2, hi2 = extent({ 3, -1, 9, 4 }, 4)
    assert(lo2 == -1 and hi2 == 9, "extent errado: " .. lo2 .. ".." .. hi2)

    -- Desenha numa janela de verdade e confere que saiu tinta na tela.
    -- Atencao: no teletexto a cor cai no FUNDO quando o sub-pixel inferior-direito e dela,
    -- entao procurar so no primeiro plano da falso negativo. Olha os dois.
    local win = window.create(term.current(), 1, 1, 10, 4, false)
    local function paints(row, color)
        local _, fgs, bgs = win.getLine(row)
        local c = colors.toBlit(color)
        return fgs:find(c, 1, true) ~= nil or bgs:find(c, 1, true) ~= nil
    end

    chart.line(win, { x = 1, y = 1, w = 10, h = 4, data = { 0, 5, 10 }, bg = colors.black, fg = colors.lime })
    assert(paints(1, colors.lime), "grafico nao pintou nada na linha do topo")

    -- Serie constante desenha na base, sem sumir nem dividir por zero.
    chart.line(win, { x = 1, y = 1, w = 10, h = 4, data = flat, bg = colors.black, fg = colors.red })
    assert(paints(4, colors.red), "serie constante nao desenhou")
    assert(not paints(1, colors.red), "serie constante vazou para o topo")

    local h = chart.history(3)
    h:push(1):push(2):push(3):push(4)
    assert(#h.data == 3 and h.data[1] == 2, "history nao descartou o mais antigo")
    assert(h:last() == 4, "history:last errado")
    assert(h:mean() == 3, "history:mean errado: " .. h:mean())

    -- Ritmo de queda: 5 amostras de 2 em 2 segundos = 8 s de janela.
    local q = chart.history(10)
    assert(q:fallPerMin(2) == nil, "com historico vazio nao da para estimar ritmo")
    q:push(100):push(90):push(80):push(70)
    assert(q:fallPerMin(2) == nil, "4 amostras ainda e pouco para estimar")
    q:push(60)                              -- caiu 40 em 8 s = 300 por minuto
    assert(q:fallPerMin(2) == 300, "ritmo de queda errado: " .. tostring(q:fallPerMin(2)))

    -- Subindo nao vira projecao: seria dizer que "acaba" um valor que esta crescendo.
    local sobe = chart.history(10)
    sobe:push(1):push(2):push(3):push(4):push(5)
    assert(sobe:fallPerMin(2) == 0, "serie subindo devia dar queda 0")

    -- Estavel tambem e zero, nao divisao por zero mais adiante.
    local flat2 = chart.history(10)
    for _ = 1, 6 do flat2:push(7) end
    assert(flat2:fallPerMin(2) == 0, "serie estavel devia dar queda 0")
    return true
end

return chart
