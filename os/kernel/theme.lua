-- Tema: cores nomeadas usadas pelo WM e pelos widgets.
--
-- Os nomes aqui sao papeis, nao cores: `face` e o cinza do chrome, `highlight` e a quina que
-- pega luz, `shadow` a que fica na sombra. Quem escolhe o tom de cada um e o kernel/palette,
-- que remapeia os slots do CC para os tons do Win95. Trocar a paleta muda o visual inteiro
-- sem tocar em widget nenhum.
local theme = {}

local themes = {
    -- Windows 95. Com kernel/palette ligado: lightGray=#C0C0C0, white=#FFFFFF, gray=#808080,
    -- blue=#000080, cyan=#008080. Sem ele, ainda funciona: fica com as cores padrao do CC.
    win95 = {
        -- relevo 3D: a base de todo o chrome
        face = colors.lightGray,      faceFg = colors.black,
        highlight = colors.white,     -- quina iluminada (cima/esquerda no relevo alto)
        shadow = colors.gray,         -- quina em sombra (baixo/direita)
        darkShadow = colors.black,    -- contorno externo e sombra da janela

        desktopBg = colors.cyan,      desktopFg = colors.white,
        titleBg = colors.blue,        titleFg = colors.white,        -- janela focada
        titleGrad = colors.lightBlue, -- fim do degrade da barra de titulo
        titleBgInactive = colors.gray, titleFgInactive = colors.lightGray,
        closeFg = colors.white,
        clientBg = colors.black,      clientFg = colors.white,       -- terminal e programas da ROM
        taskbarBg = colors.lightGray, taskbarFg = colors.black,
        taskbarActiveBg = colors.lightGray, taskbarActiveFg = colors.black,
        startBg = colors.lightGray,   startFg = colors.black,
        appBg = colors.lightGray,     appFg = colors.black,          -- apps feitos com ui
        accent = colors.blue,         accentFg = colors.white,
        inputBg = colors.white,       inputFg = colors.black,
        buttonBg = colors.lightGray,  buttonFg = colors.black,       -- botao Win95: face cinza
        buttonAltBg = colors.lightGray, buttonAltFg = colors.black,
        selBg = colors.blue,          selFg = colors.white,
        dialogBg = colors.lightGray,  dialogFg = colors.black,
        dialogTitleBg = colors.blue,  dialogTitleFg = colors.white,
        toastBg = colors.yellow,      toastFg = colors.black,
        errorBg = colors.red,         errorFg = colors.white,
        -- Texto secundario: o cinza #808080 sobre a face #C0C0C0 da contraste ~2:1 e some.
        -- Escolhemos legibilidade em vez de fidelidade e usamos o azul-marinho.
        mutedFg = colors.blue,
        shadowBg = colors.black,      -- sombra da janela sobre a area de trabalho
    },
}

-- Cores originais do CC, para quem nao quiser o remapeamento de paleta.
themes.classic = setmetatable({
    titleBg = colors.blue, closeFg = colors.red,
    taskbarActiveBg = colors.white,
    startBg = colors.blue, startFg = colors.white,
    buttonBg = colors.blue, buttonFg = colors.white,
    buttonAltBg = colors.gray, buttonAltFg = colors.white,
    dialogBg = colors.white, dialogFg = colors.black,
    mutedFg = colors.gray,
}, { __index = themes.win95 })

-- Tema escuro: mesma estrutura, base preta/cinza.
themes.dark = setmetatable({
    face = colors.gray, faceFg = colors.white,
    highlight = colors.lightGray, shadow = colors.black, darkShadow = colors.black,
    desktopBg = colors.black, desktopFg = colors.lightGray,
    titleBg = colors.gray, titleFg = colors.white,
    titleBgInactive = colors.black, titleFgInactive = colors.gray,
    taskbarBg = colors.gray, taskbarFg = colors.white,
    taskbarActiveBg = colors.gray, taskbarActiveFg = colors.white,
    startBg = colors.gray, startFg = colors.white,
    appBg = colors.gray, appFg = colors.white,
    buttonBg = colors.gray, buttonFg = colors.white,
    buttonAltBg = colors.gray, buttonAltFg = colors.white,
    dialogBg = colors.gray, dialogFg = colors.white,
    inputBg = colors.black, inputFg = colors.white,
    mutedFg = colors.lightGray,
    shadowBg = colors.black,
}, { __index = themes.win95 })

theme.names = { "win95", "classic", "dark" }
theme.current = themes.win95
theme.name = "win95"

function theme.load(name)
    theme.current = themes[name] or themes.win95
    theme.name = themes[name] and name or "win95"
    -- Percorre o tema base para nao perder chave que so exista nele.
    for k in pairs(themes.win95) do theme[k] = theme.current[k] end
end

theme.load("win95")
return theme
