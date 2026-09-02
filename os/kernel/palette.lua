-- Paleta: remapeia algumas das 16 cores do CC para os tons do Windows 95.
--
-- O CC deixa escolher QUAIS 16 cores aparecem, nunca QUANTAS. Uma tela cheia do Mosaic usa
-- umas 12 cores distintas, entao sobra folga: trocamos 7 slots e deixamos os outros 9 como
-- o CC entrega, para que .nfp antigos e programas da ROM continuem parecidos.
--
-- ATENCAO (custou caro descobrir): a API `window` do CC tira uma foto da paleta do pai quando
-- a janela e criada, e reempurra essa foto a cada `redraw()`. Entao a paleta tem que ser
-- aplicada no terminal raiz ANTES de `wm.init(root)` criar o canvas. Se for aplicada depois,
-- o proprio compositor desfaz a mudanca no quadro seguinte, em silencio.
local palette = {}

-- Cores oficiais do esquema "Windows Standard" do Win95.
palette.win95 = {
    [colors.white]     = 0xFFFFFF,  -- realce 3D (canto superior esquerdo do relevo)
    [colors.lightGray] = 0xC0C0C0,  -- face: fundo de janela, botao, menu, taskbar
    [colors.gray]      = 0x808080,  -- sombra 3D / titulo de janela inativa
    [colors.black]     = 0x000000,  -- sombra externa e texto
    [colors.blue]      = 0x000080,  -- barra de titulo ativa e selecao
    [colors.lightBlue] = 0x1084D0,  -- fim do degrade da barra de titulo
    [colors.cyan]      = 0x008080,  -- area de trabalho (o teal classico)
}
-- Intocados: orange, magenta, yellow, lime, pink, purple, brown, green, red.

function palette.apply(t, map)
    if not t or not t.setPaletteColour then return false end
    for color, rgb in pairs(map or palette.win95) do
        pcall(t.setPaletteColour, color, rgb)
    end
    return true
end

-- Devolve o terminal as cores de fabrica. `nativePaletteColour` e da 1.81 e nao existe no
-- emulador em JS, por isso a guarda: sem ela o self-check morre.
function palette.restore(t)
    if not t or not t.setPaletteColour or not t.nativePaletteColour then return false end
    for i = 0, 15 do
        local c = 2 ^ i
        local ok, r, g, b = pcall(t.nativePaletteColour, c)
        if ok and r then pcall(t.setPaletteColour, c, r, g, b) end
    end
    return true
end

function palette.enabled()
    return settings.get("mosaic.palette") ~= false
end

return palette
