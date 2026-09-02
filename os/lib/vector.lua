-- Desenho vetorial: figuras descritas por coordenadas, rasterizadas em qualquer tamanho.
--
-- Serve para o que precisa MUDAR de tamanho: logo, marca d'agua, grafico, papel de parede.
-- Para os icones pequenos da area de trabalho o caminho continua sendo o .nfp de lib/icons:
-- num desenho de 12x12 cada ponto e uma decisao, e rasterizar sempre borra.
--
-- Formato (tabela Lua pura, sem parser):
--   {
--     vb = { 0, 0, 16, 16 },                       -- caixa de coordenadas do desenho
--     { fill = colors.blue, d = { "M",1,1, "L",15,1, "L",8,14, "Z" } },
--     { fill = colors.white, rule = "eo", d = { ... } },   -- "eo" = par-impar, senao nao-zero
--     { rect = { 2, 2, 6, 4 }, fill = colors.red },
--     { circle = { 8, 8, 5 }, fill = colors.lime },
--     { line = { 1, 1, 15, 15 }, stroke = colors.black },
--   }
--
--   local vector = mosaic.lib("vector")
--   vector.draw(term.current(), shape, 1, 1, 10, 6)   -- x, y, largura e altura em CELULAS
local pixel = require("lib.pixel")

local vector = {}

local cache = {}

-- Circulo vira poligono: numero de lados conforme o raio, para nao gastar a toa.
local function circlePath(cx, cy, r)
    local n = math.max(8, math.floor(r * 4))
    local d = { "M", cx + r, cy }
    for i = 1, n - 1 do
        local a = i * 2 * math.pi / n
        d[#d + 1] = "L"
        d[#d + 1] = cx + r * math.cos(a)
        d[#d + 1] = cy + r * math.sin(a)
    end
    d[#d + 1] = "Z"
    return d
end

-- Quebra o caminho em segmentos { x0, y0, x1, y1 }. Fecha cada subcaminho no "Z".
local function edgesOf(d, sx, sy, ox, oy)
    local edges = {}
    local i, cx, cy, startX, startY = 1, 0, 0, 0, 0
    local function put(x0, y0, x1, y1)
        if y0 ~= y1 then edges[#edges + 1] = { x0, y0, x1, y1 } end
    end
    while i <= #d do
        local op = d[i]
        if op == "M" then
            cx, cy = ox + d[i + 1] * sx, oy + d[i + 2] * sy
            startX, startY = cx, cy
            i = i + 3
        elseif op == "L" then
            local nx, ny = ox + d[i + 1] * sx, oy + d[i + 2] * sy
            put(cx, cy, nx, ny)
            cx, cy = nx, ny
            i = i + 3
        elseif op == "Z" then
            put(cx, cy, startX, startY)
            cx, cy = startX, startY
            i = i + 1
        else
            i = i + 1     -- comando desconhecido: ignora em vez de estourar
        end
    end
    return edges
end

-- Preenchimento por varredura: para cada linha de sub-pixels, acha onde as arestas cruzam
-- e pinta entre os cruzamentos. `rule` decide o que e "dentro" quando o caminho se cruza.
local function fillPath(canvas, edges, color, rule)
    if #edges == 0 then return end
    local hits = {}
    for py = 1, canvas.h do
        local yc = py - 0.5          -- amostra no meio do sub-pixel
        local n = 0
        for k = 1, #edges do
            local e = edges[k]
            local y0, y1 = e[2], e[4]
            local lo, hi = y0, y1
            if lo > hi then lo, hi = hi, lo end
            -- Intervalo semi-aberto: um vertice nao pode contar duas vezes.
            if yc >= lo and yc < hi then
                n = n + 1
                local t = (yc - y0) / (y1 - y0)
                hits[n] = { x = e[1] + t * (e[3] - e[1]), w = (y1 > y0) and 1 or -1 }
            end
        end
        if n > 1 then
            local list = {}
            for k = 1, n do list[k] = hits[k] end
            table.sort(list, function(a, b) return a.x < b.x end)
            if rule == "eo" then
                for k = 1, n - 1, 2 do
                    for x = math.floor(list[k].x + 0.5), math.floor(list[k + 1].x - 0.5) do
                        canvas:set(x + 1, py, color)
                    end
                end
            else
                local acc = 0
                for k = 1, n - 1 do
                    acc = acc + list[k].w
                    if acc ~= 0 then
                        for x = math.floor(list[k].x + 0.5), math.floor(list[k + 1].x - 0.5) do
                            canvas:set(x + 1, py, color)
                        end
                    end
                end
            end
        end
    end
end

-- Rasteriza `shape` num canvas novo de `cols` x `rows` CELULAS.
function vector.rasterize(shape, cols, rows, bg)
    local canvas = pixel.new(cols, rows, bg or colors.black)
    local vb = shape.vb or { 0, 0, 16, 16 }
    local vw, vh = vb[3] - vb[1], vb[4] - vb[2]
    if vw <= 0 or vh <= 0 then return canvas end
    -- Mesma escala nos dois eixos, centrado: desenho torto e pior que desenho pequeno.
    local s = math.min(canvas.w / vw, canvas.h / vh)
    local ox = (canvas.w - vw * s) / 2 - vb[1] * s
    local oy = (canvas.h - vh * s) / 2 - vb[2] * s

    for _, part in ipairs(shape) do
        local d = part.d
        if part.rect then
            local x, y, w, h = part.rect[1], part.rect[2], part.rect[3], part.rect[4]
            d = { "M", x, y, "L", x + w, y, "L", x + w, y + h, "L", x, y + h, "Z" }
        elseif part.circle then
            d = circlePath(part.circle[1], part.circle[2], part.circle[3])
        elseif part.line then
            local l = part.line
            canvas:line(ox + l[1] * s + 1, oy + l[2] * s + 1, ox + l[3] * s + 1, oy + l[4] * s + 1,
                part.stroke or part.fill or colors.black)
        end
        if d and part.fill then
            fillPath(canvas, edgesOf(d, s, s, ox, oy), part.fill, part.rule)
        end
    end
    return canvas
end

-- Desenha em (x, y), com `cols` x `rows` CELULAS. Guarda por tamanho e fundo, do mesmo jeito
-- que o papel de parede: rasterizar de novo a cada quadro seria desperdicio.
function vector.draw(t, shape, x, y, cols, rows, bg)
    local key = tostring(shape) .. ":" .. cols .. "x" .. rows .. ":" .. tostring(bg)
    local canvas = cache[key]
    if not canvas then
        canvas = vector.rasterize(shape, cols, rows, bg)
        canvas:toBlit()
        cache[key] = canvas
    end
    canvas:blitTo(t, x, y)
    return canvas
end

function vector.clearCache() cache = {} end

-- Carrega um desenho de arquivo (uma tabela Lua devolvida por `return { ... }`).
function vector.load(path)
    if not fs.exists(path) then return nil, "nao existe: " .. tostring(path) end
    local fn, err = loadfile(path, "t", { colors = colors, colours = colours, math = math })
    if not fn then
        -- Antes da 1.109 o loadfile do CC nao aceita modo/ambiente; cai para a forma antiga.
        fn, err = loadfile(path)
    end
    if not fn then return nil, err end
    local ok, shape = pcall(fn)
    if not ok or type(shape) ~= "table" then return nil, tostring(shape) end
    return shape
end

function vector.demo()
    -- Um quadrado que cobre a caixa inteira tem de pintar tudo.
    local square = { vb = { 0, 0, 10, 10 }, { fill = colors.red, d = { "M", 0, 0, "L", 10, 0, "L", 10, 10, "L", 0, 10, "Z" } } }
    -- 4x4 celulas = 8 x 12 sub-pixels; a caixa e' quadrada, entao sobra margem em cima e
    -- embaixo (a escala e' a mesma nos dois eixos, de proposito).
    local c = vector.rasterize(square, 4, 4, colors.black)
    assert(c:get(4, 6) == colors.red, "o quadrado nao preencheu o meio")
    assert(c:get(1, 6) == colors.red, "o quadrado nao chegou na borda esquerda")
    assert(c:get(4, 1) == colors.black, "a margem de cima deveria ficar com o fundo")

    -- Retangulo e caminho tem de dar o mesmo resultado.
    local viaRect = vector.rasterize({ vb = { 0, 0, 10, 10 }, { rect = { 0, 0, 10, 10 }, fill = colors.red } }, 4, 4, colors.black)
    assert(viaRect:get(4, 6) == colors.red, "a forma rect nao preencheu")

    -- Fora do desenho continua com o fundo.
    local small = vector.rasterize({ vb = { 0, 0, 10, 10 }, { rect = { 0, 0, 2, 2 }, fill = colors.red } }, 5, 5, colors.blue)
    assert(small:get(10, 14) == colors.blue, "pintou fora do desenho")

    -- Circulo: o centro pinta, o canto nao.
    local circ = vector.rasterize({ vb = { 0, 0, 10, 10 }, { circle = { 5, 5, 4 }, fill = colors.lime } }, 6, 6, colors.black)
    assert(circ:get(6, 9) == colors.lime, "o circulo nao preencheu o centro")
    assert(circ:get(1, 1) == colors.black, "o circulo vazou para o canto")

    -- Cache: mesmo tamanho devolve o mesmo canvas.
    local t = { setCursorPos = function() end, blit = function() end }
    local a = vector.draw(t, square, 1, 1, 4, 4, colors.black)
    local b = vector.draw(t, square, 1, 1, 4, 4, colors.black)
    assert(a == b, "o cache do vetor nao guardou")
    assert(vector.draw(t, square, 1, 1, 5, 5, colors.black) ~= a, "tamanho faz parte da chave do cache")
    return true
end

return vector
