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

-- Rampa de cinza para 3D. NAO substitui a paleta do Win95: PREENCHE os buracos dela.
--
-- A rampa de sombreamento que a paleta do Win95 oferece e' preto, cinza, cinza claro e branco,
-- ou 0, 128, 192 e 255 de luminancia — o primeiro degrau e' o dobro dos outros dois, e a
-- sombra fecha em faixa dura. Aqui quatro cores que o tema nao usa (marrom, roxo, magenta e
-- rosa) viram tons intermediarios, e a rampa passa a ser:
--
--   0, 48, 90, 128, 160, 192, 224, 255   — oito degraus, o maior salto de 48 em vez de 128.
--
-- Preto, cinza, cinza claro e branco continuam onde estavam, entao a barra de tarefas, o
-- relevo dos botoes e a barra de titulo NAO mudam de cor. O que muda e' icone que use essas
-- quatro cores, e ele esta atras da janela em tela cheia.
palette.render3d = {
    [colors.brown]   = 0x303030,
    [colors.purple]  = 0x5A5A5A,
    [colors.magenta] = 0xA0A0A0,
    [colors.pink]    = 0xE0E0E0,
}

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

-- Cores de fabrica do CC, para devolver slot a slot quando `nativePaletteColour` nao existe
-- (ele e' da 1.81 e o emulador em JS nao tem).
palette.ccDefaults = {
    [colors.white] = 0xF0F0F0, [colors.orange] = 0xF2B233, [colors.magenta] = 0xE57FD8,
    [colors.lightBlue] = 0x99B2F2, [colors.yellow] = 0xDEDE6C, [colors.lime] = 0x7FCC19,
    [colors.pink] = 0xF2B2CC, [colors.gray] = 0x4C4C4C, [colors.lightGray] = 0x999999,
    [colors.cyan] = 0x4C99B2, [colors.purple] = 0xB266E5, [colors.blue] = 0x3366CC,
    [colors.brown] = 0x7F664C, [colors.green] = 0x57A64E, [colors.red] = 0xCC4C4C,
    [colors.black] = 0x111111,
}

-- Devolve ao normal SO' os slots de um mapa, e nao a paleta inteira. Serve para quem aplicou
-- um mapa por cima (o `render3d`) e quer sair sem derrubar o resto do tema.
function palette.restoreSlots(t, map, base)
    if not t or not t.setPaletteColour then return false end
    base = base or palette.win95
    for color in pairs(map or {}) do
        local rgb = base[color] or palette.ccDefaults[color]
        if rgb then pcall(t.setPaletteColour, color, rgb) end
    end
    return true
end

function palette.enabled()
    return settings.get("mosaic.palette") ~= false
end

return palette
