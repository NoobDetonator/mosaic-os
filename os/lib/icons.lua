-- Icones em alta densidade. Cada icone e um .nfp de 12x12 em /os/share/icons, onde cada pixel
-- do arquivo vale um SUB-pixel: 12x12 sub-pixels = 6 x 4 celulas na tela.
--
--   local icons = mosaic.lib("icons")
--   icons.draw(term.current(), "files", 2, 3, theme.desktopBg)
--
-- O fundo entra no cache porque uma celula de sub-pixel so aceita duas cores: o transparente
-- do arquivo tem que virar a cor de tras na hora de montar o canvas, nao na hora de desenhar.
local pixel = require("lib.pixel")

local icons = {}
icons.DIR = "/os/share/icons"
icons.COLS, icons.ROWS = 6, 4        -- em celulas
icons.FALLBACK = "app"

local cache = {}

function icons.path(name)
    return icons.DIR .. "/" .. tostring(name) .. ".nfp"
end

function icons.exists(name)
    return fs.exists(icons.path(name))
end

-- Devolve o canvas do icone, ou nil se nao houver arquivo.
function icons.get(name, bg)
    if not name then return nil end
    bg = bg or colors.black
    local key = name .. ":" .. bg
    local hit = cache[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local path = icons.path(name)
    if not fs.exists(path) then cache[key] = false return nil end
    local ok, img = pcall(paintutils.loadImage, path)
    if not ok or type(img) ~= "table" or #img == 0 then cache[key] = false return nil end
    local canvas = pixel.fromImage(img, icons.COLS, icons.ROWS, bg)
    canvas:toBlit()                  -- congela agora: icone nao muda mais
    cache[key] = canvas
    return canvas
end

-- Desenha em (x, y) medido em CELULAS. Devolve true se desenhou.
function icons.draw(t, name, x, y, bg)
    local canvas = icons.get(name, bg) or icons.get(icons.FALLBACK, bg)
    if not canvas then return false end
    canvas:blitTo(t, x, y)
    return true
end

function icons.clearCache() cache = {} end

function icons.demo()
    assert(icons.COLS * 2 == 12 and icons.ROWS * 3 == 12, "grade do icone deveria dar 12x12 sub-pixels")
    if icons.exists("app") then
        local c = icons.get("app", colors.black)
        assert(c, "icone de reserva nao carregou")
        assert(c.cols == icons.COLS and c.rows == icons.ROWS, "canvas do icone com tamanho errado")
        assert(icons.get("app", colors.black) == c, "o cache do icone nao guardou")
        assert(icons.get("app", colors.white) ~= c, "o fundo tem de fazer parte da chave do cache")
    end
    assert(icons.get("nao-existe-esse-icone", colors.black) == nil, "icone inexistente deveria dar nil")
    return true
end

return icons
