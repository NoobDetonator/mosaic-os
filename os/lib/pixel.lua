-- Canvas de sub-pixels usando os caracteres de teletexto do CC (2 x 3 por celula).
-- Uma tela de 51x19 vira 102x57 "pixels". Cada celula so aceita DUAS cores e nenhum
-- texto legivel: isto serve para imagem e desenho, nao para caber mais interface.
--
--   local pixel = mosaic.lib("pixel")
--   local c = pixel.new(51, 19)        -- em CELULAS; o buffer fica 102 x 57
--   c:clear(colors.blue)
--   c:set(10, 20, colors.white)
--   c:render(term.current(), 1, 1)

local pixel = {}

local Canvas = {}
Canvas.__index = Canvas

-- Peso de cada sub-pixel no codigo do caractere, na ordem
-- superior-esq, superior-dir, meio-esq, meio-dir, inferior-esq.
-- O inferior-direito nao tem bit: na faixa 128..159 do CC ele e sempre o fundo,
-- e e por isso que a cor de fundo da celula sai dele.
local BIT = { 1, 2, 4, 8, 16 }

-- Reduz os 6 sub-pixels de uma celula a duas cores. Devolve caractere, frente e fundo.
-- px vem na ordem dos BIT acima, com o inferior-direito em px[6].
function pixel.cell(px)
    local counts, order = {}, {}
    for i = 1, 6 do
        local c = px[i]
        if counts[c] then counts[c] = counts[c] + 1
        else counts[c] = 1 order[#order + 1] = c end
    end
    -- Duas cores dominantes. Percorre em ordem de aparicao para o empate ser previsivel.
    local best, second
    for _, c in ipairs(order) do
        if not best or counts[c] > counts[best] then second = best best = c
        elseif not second or counts[c] > counts[second] then second = c end
    end
    second = second or best
    local function near(c) return (c == best or c == second) and c or best end

    local bg = near(px[6])
    local fg = (bg == best) and second or best
    local code = 0
    for i = 1, 5 do
        if near(px[i]) ~= bg then code = code + BIT[i] end
    end
    return string.char(128 + code), fg, bg
end

function pixel.new(cols, rows, fill)
    local self = setmetatable({
        cols = cols, rows = rows,
        w = cols * 2, h = rows * 3,
        buf = {},
    }, Canvas)
    self:clear(fill or colors.black)
    return self
end

function Canvas:clear(color)
    for y = 1, self.h do
        local row = {}
        for x = 1, self.w do row[x] = color end
        self.buf[y] = row
    end
end

function Canvas:set(x, y, color)
    x, y = math.floor(x), math.floor(y)
    if x < 1 or y < 1 or x > self.w or y > self.h then return end
    self.buf[y][x] = color
end

function Canvas:get(x, y)
    if x < 1 or y < 1 or x > self.w or y > self.h then return nil end
    return self.buf[y][x]
end

function Canvas:rect(x, y, w, h, color, outline)
    for iy = y, y + h - 1 do
        for ix = x, x + w - 1 do
            if not outline or ix == x or ix == x + w - 1 or iy == y or iy == y + h - 1 then
                self:set(ix, iy, color)
            end
        end
    end
end

function Canvas:line(x0, y0, x1, y1, color)
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        self:set(x0, y0, color)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy x0 = x0 + sx end
        if e2 <= dx then err = err + dx y0 = y0 + sy end
    end
end

-- Desenha o canvas num terminal, a partir da celula (ox, oy).
function Canvas:render(t, ox, oy)
    ox, oy = ox or 1, oy or 1
    local px = {}
    for row = 1, self.rows do
        local chars, fgs, bgs = {}, {}, {}
        local by = (row - 1) * 3
        for col = 1, self.cols do
            local bx = (col - 1) * 2
            px[1] = self.buf[by + 1][bx + 1]
            px[2] = self.buf[by + 1][bx + 2]
            px[3] = self.buf[by + 2][bx + 1]
            px[4] = self.buf[by + 2][bx + 2]
            px[5] = self.buf[by + 3][bx + 1]
            px[6] = self.buf[by + 3][bx + 2]
            local ch, fg, bg = pixel.cell(px)
            chars[col] = ch
            fgs[col] = colors.toBlit(fg)
            bgs[col] = colors.toBlit(bg)
        end
        t.setCursorPos(ox, oy + row - 1)
        t.blit(table.concat(chars), table.concat(fgs), table.concat(bgs))
    end
end

-- Monta um canvas a partir de uma imagem do paintutils, tratando cada pixel do
-- arquivo como um SUB-pixel. Um .nfp de 102x57 vira uma tela cheia em alta resolucao.
function pixel.fromImage(img, cols, rows, fill)
    local c = pixel.new(cols, rows, fill)
    for y = 1, math.min(#img, c.h) do
        local row = img[y]
        for x = 1, math.min(#row, c.w) do
            if row[x] and row[x] ~= 0 then c:set(x, y, row[x]) end
        end
    end
    return c
end

-- Self-check: a codificacao da celula e o unico ponto com logica de verdade aqui.
function pixel.demo()
    local R, W, B = colors.red, colors.white, colors.blue

    local ch, fg, bg = pixel.cell({ R, R, R, R, R, R })
    assert(ch == string.char(128), "celula de uma cor so deveria dar o caractere 128")
    assert(bg == R, "fundo da celula uniforme errado")

    ch, fg, bg = pixel.cell({ W, R, R, R, R, R })
    assert(ch == string.char(129), "bit do sub-pixel superior-esquerdo errado")
    assert(fg == W and bg == R, "frente/fundo trocados")

    -- O inferior-direito manda no fundo: se ele e o diferente, os outros 5 acendem.
    ch, fg, bg = pixel.cell({ R, R, R, R, R, W })
    assert(bg == W, "o sub-pixel inferior-direito tem de virar o fundo")
    assert(ch == string.char(128 + 31), "os outros cinco deveriam estar todos acesos")
    assert(fg == R, "cor de frente errada quando o fundo veio do canto")

    -- Metade de cima numa cor, metade de baixo na outra.
    ch, fg, bg = pixel.cell({ W, W, R, R, R, R })
    assert(ch == string.char(128 + 1 + 2), "linha de cima deveria acender os bits 1 e 2")

    -- Tres cores: a menos frequente e absorvida pela dominante, sem estourar.
    ch, fg, bg = pixel.cell({ B, R, R, R, W, R })
    assert(fg ~= bg or fg == R, "quantizacao devolveu cor fora das duas dominantes")
    assert(#ch == 1 and ch:byte() >= 128 and ch:byte() <= 159, "caractere fora da faixa de teletexto")

    local c = pixel.new(3, 2)
    assert(c.w == 6 and c.h == 6, "tamanho do buffer errado: " .. c.w .. "x" .. c.h)
    c:set(1, 1, W)
    assert(c:get(1, 1) == W, "set/get nao bateram")
    c:set(999, 999, W)            -- fora do canvas nao pode estourar
    assert(c:get(999, 999) == nil, "get fora do canvas deveria dar nil")
    c:line(1, 1, 6, 1, B)
    assert(c:get(6, 1) == B, "linha horizontal nao chegou ao fim")
    return true
end

return pixel
