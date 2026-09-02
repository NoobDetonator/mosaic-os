-- Primitivas de desenho do chrome: o relevo 3D do Windows 95.
--
-- A ideia do Win95 e simular luz vindo de cima e da esquerda. Um botao "alto" tem quina clara
-- em cima/esquerda e escura embaixo/direita; ao ser pressionado as quinas trocam e ele parece
-- afundar. Fundo de campo de texto e sempre "afundado".
--
-- Duas espessuras:
--   * celula inteira (`frame`/`bevel`) para chrome grande, onde sobra espaco;
--   * meia celula (`caps`) para widget de uma linha so, usando o caractere teletext \149, que
--     divide a celula em duas metades verticais exatas. O botao ja gastava uma celula de
--     espacamento de cada lado, entao o relevo sai de graca, sem roubar largura do texto.
--
-- Limite que vale para tudo aqui: uma celula com caractere teletext aceita 2 cores e nenhum
-- texto. Por isso o relevo nunca invade a celula onde tem letra.
local theme = require("kernel.theme")

local draw = {}

-- Metade esquerda acesa (bits superior-esq + meio-esq + inferior-esq = 1+4+16 = 21).
draw.HALF = string.char(128 + 21)

function draw.fill(t, x, y, w, h, bg)
    if w < 1 or h < 1 then return end
    t.setBackgroundColor(bg)
    local line = string.rep(" ", w)
    for i = 0, h - 1 do
        t.setCursorPos(x, y + i)
        t.write(line)
    end
end

function draw.hline(t, x, y, w, bg) draw.fill(t, x, y, w, 1, bg) end
function draw.vline(t, x, y, h, bg) draw.fill(t, x, y, 1, h, bg) end

-- Moldura de 1 celula, sem preencher o miolo.
-- Os cantos sao um compromisso: a celula superior-direita quer a cor de cima e a da direita ao
-- mesmo tempo, e so cabe uma. O Win95 original tem o mesmo problema e resolve igual.
function draw.frame(t, x, y, w, h, topLeft, bottomRight)
    if w < 2 or h < 2 then return end
    draw.hline(t, x, y, w - 1, topLeft)                    -- topo
    draw.vline(t, x, y, h - 1, topLeft)                    -- esquerda
    draw.hline(t, x + 1, y + h - 1, w - 1, bottomRight)    -- base
    draw.vline(t, x + w - 1, y, h, bottomRight)            -- direita
end

-- raised = luz em cima/esquerda. Afundado inverte.
function draw.bevel(t, x, y, w, h, raised)
    if raised then
        draw.frame(t, x, y, w, h, theme.highlight, theme.darkShadow)
    else
        draw.frame(t, x, y, w, h, theme.shadow, theme.highlight)
    end
end

-- Relevo de meia celula nas pontas de um widget de uma linha.
-- `face` e a cor de fundo do proprio widget, para a outra metade da celula sumir nele.
function draw.caps(t, x, y, w, face, raised)
    if w < 2 then return end
    -- Meia celula aqui e' proporcionalmente muito mais grossa que o 1 pixel do Win95, entao a
    -- quina escura usa o cinza de sombra e nao o preto: com preto a borda vira uma barra.
    local left = raised and theme.highlight or theme.shadow
    local right = raised and theme.shadow or theme.highlight
    local f = colors.toBlit(face)
    t.setCursorPos(x, y)
    t.blit(draw.HALF, colors.toBlit(left), f)      -- metade esquerda acesa = quina esquerda
    t.setCursorPos(x + w - 1, y)
    t.blit(draw.HALF, f, colors.toBlit(right))     -- fundo na metade esquerda = quina direita
end

-- Self-check: roda com `require("kernel.draw").demo()`.
function draw.demo()
    assert(#draw.HALF == 1, "HALF tem que ser um caractere so")
    assert(draw.HALF:byte() == 149, "HALF deveria ser 149, veio " .. draw.HALF:byte())
    local calls = {}
    local fake = {
        setBackgroundColor = function() end,
        setCursorPos = function(x, y) calls[#calls + 1] = { x, y } end,
        write = function() end,
        blit = function() end,
    }
    draw.frame(fake, 1, 1, 4, 3)
    assert(#calls > 0, "frame nao desenhou nada")
    calls = {}
    draw.frame(fake, 1, 1, 1, 1)
    assert(#calls == 0, "frame nao pode desenhar em area menor que 2x2")
    return true
end

return draw
