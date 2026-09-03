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

-- Caractere pronto para cada combinacao de bits, e a letra de blit de cada cor. As duas
-- tabelas sao montadas uma vez: string.char e colors.toBlit por celula, numa tela cheia,
-- eram 765 chamadas por quadro.
local CHARS = {}
for code = 0, 31 do CHARS[code] = string.char(128 + code) end

local TOBLIT = {}
for i = 0, 15 do TOBLIT[2 ^ i] = string.format("%x", i) end

-- Rascunho reaproveitado. Nada aqui faz yield, entao nao ha reentrancia para atrapalhar.
local ccount, corder = {}, {}

-- Reduz os 6 sub-pixels de uma celula a duas cores. Devolve caractere, frente e fundo.
-- A ordem e' superior-esq, superior-dir, meio-esq, meio-dir, inferior-esq, inferior-dir.
--
-- Recebe os seis valores soltos, e nao uma tabela: escrever e ler px[1..6] custava doze
-- operacoes de tabela por celula, e sao 765 celulas numa tela cheia.
function pixel.cell6(p1, p2, p3, p4, p5, p6)
    -- Conta quantas vezes cada cor aparece, guardando a ordem de aparicao para o empate ser
    -- previsivel. Desenrolado de proposito: um laco com `(i == 1 and p1) or ...` para pegar o
    -- valor certo custaria mais que a tabela que estamos evitando.
    local n, k = 0, nil
    k = ccount[p1] if k then ccount[p1] = k + 1 else ccount[p1] = 1 n = n + 1 corder[n] = p1 end
    k = ccount[p2] if k then ccount[p2] = k + 1 else ccount[p2] = 1 n = n + 1 corder[n] = p2 end
    k = ccount[p3] if k then ccount[p3] = k + 1 else ccount[p3] = 1 n = n + 1 corder[n] = p3 end
    k = ccount[p4] if k then ccount[p4] = k + 1 else ccount[p4] = 1 n = n + 1 corder[n] = p4 end
    k = ccount[p5] if k then ccount[p5] = k + 1 else ccount[p5] = 1 n = n + 1 corder[n] = p5 end
    k = ccount[p6] if k then ccount[p6] = k + 1 else ccount[p6] = 1 n = n + 1 corder[n] = p6 end

    local melhor, segunda, qm, qs = nil, nil, -1, -1
    for i = 1, n do
        local c = corder[i]
        local k = ccount[c]
        ccount[c] = nil                     -- limpa aqui: o rascunho e reaproveitado
        if k > qm then segunda, qs = melhor, qm melhor, qm = c, k
        elseif k > qs then segunda, qs = c, k end
    end
    if segunda == nil then segunda = melhor end

    local bg = (p6 == melhor or p6 == segunda) and p6 or melhor
    local fg = (bg == melhor) and segunda or melhor
    local code = 0
    if ((p1 == melhor or p1 == segunda) and p1 or melhor) ~= bg then code = code + 1 end
    if ((p2 == melhor or p2 == segunda) and p2 or melhor) ~= bg then code = code + 2 end
    if ((p3 == melhor or p3 == segunda) and p3 or melhor) ~= bg then code = code + 4 end
    if ((p4 == melhor or p4 == segunda) and p4 or melhor) ~= bg then code = code + 8 end
    if ((p5 == melhor or p5 == segunda) and p5 or melhor) ~= bg then code = code + 16 end
    return CHARS[code], fg, bg
end

-- Forma antiga, com os seis num vetor. Mantida porque e' a que se le melhor.
function pixel.cell(px)
    return pixel.cell6(px[1], px[2], px[3], px[4], px[5], px[6])
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

function Canvas:touch() self.blitCache = nil end

function Canvas:clear(color)
    self.blitCache = nil
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
    self.blitCache = nil
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

-- Rascunho das linhas: as tres tabelas sao reaproveitadas entre linhas e entre chamadas.
-- O table.concat leva o limite explicito para sobra de uma linha maior nao entrar.
local schars, sfgs, sbgs = {}, {}, {}

-- Uma linha de celulas vira as tres strings do blit.
local function linhaBlit(buf, by, cols)
    local r1, r2, r3 = buf[by + 1], buf[by + 2], buf[by + 3]
    for col = 1, cols do
        local bx = (col - 1) * 2
        local a, b = bx + 1, bx + 2
        local ch, fg, bg = pixel.cell6(r1[a], r1[b], r2[a], r2[b], r3[a], r3[b])
        schars[col] = ch
        sfgs[col] = TOBLIT[fg] or colors.toBlit(fg)
        sbgs[col] = TOBLIT[bg] or colors.toBlit(bg)
    end
    return table.concat(schars, "", 1, cols), table.concat(sfgs, "", 1, cols),
        table.concat(sbgs, "", 1, cols)
end

-- Desenha o canvas num terminal, a partir da celula (ox, oy).
function Canvas:render(t, ox, oy)
    ox, oy = ox or 1, oy or 1
    local buf, cols = self.buf, self.cols
    for row = 1, self.rows do
        local ch, fg, bg = linhaBlit(buf, (row - 1) * 3, cols)
        t.setCursorPos(ox, oy + row - 1)
        t.blit(ch, fg, bg)
    end
end

-- Congela o canvas em linhas de blit: { { texto, frente, fundo }, ... }.
-- Um icone e' estatico, entao requantizar 12x12 sub-pixels a cada quadro e' desperdicio.
-- O cache morre em qualquer set/clear/rect/line (ver Canvas:touch).
function Canvas:toBlit()
    if self.blitCache then return self.blitCache end
    local out, buf, cols = {}, self.buf, self.cols
    for row = 1, self.rows do
        local ch, fg, bg = linhaBlit(buf, (row - 1) * 3, cols)
        out[row] = { ch, fg, bg }
    end
    self.blitCache = out
    return out
end

-- Desenha usando o cache. Mesmo resultado do render, sem recalcular.
function Canvas:blitTo(t, ox, oy)
    ox, oy = ox or 1, oy or 1
    local rows = self:toBlit()
    for i = 1, #rows do
        t.setCursorPos(ox, oy + i - 1)
        t.blit(rows[i][1], rows[i][2], rows[i][3])
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

    local rows = c:toBlit()
    assert(#rows == c.rows, "toBlit devolveu numero de linhas errado")
    assert(#rows[1][1] == c.cols, "linha do toBlit com largura errada")
    assert(rows == c:toBlit(), "toBlit deveria devolver o mesmo cache")
    c:set(2, 2, W)
    assert(rows ~= c:toBlit(), "o cache do toBlit tinha de morrer depois do set")
    return true
end

return pixel
