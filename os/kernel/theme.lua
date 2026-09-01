-- Tema: cores nomeadas usadas pelo WM e pelos widgets.
-- Só usa as 16 cores padrão do CC para não mexer na paleta global.
local theme = {}

local themes = {
    default = {
        desktopBg = colors.cyan,      desktopFg = colors.white,
        titleBg = colors.blue,        titleFg = colors.white,       -- janela focada
        titleBgInactive = colors.gray, titleFgInactive = colors.lightGray,
        closeFg = colors.red,
        clientBg = colors.black,      clientFg = colors.white,      -- terminal/programas
        taskbarBg = colors.lightGray, taskbarFg = colors.black,
        taskbarActiveBg = colors.white, taskbarActiveFg = colors.black,
        startBg = colors.blue,        startFg = colors.white,
        appBg = colors.lightGray,     appFg = colors.black,         -- apps feitos com ui
        accent = colors.blue,         accentFg = colors.white,
        inputBg = colors.white,       inputFg = colors.black,
        buttonBg = colors.blue,       buttonFg = colors.white,
        buttonAltBg = colors.gray,    buttonAltFg = colors.white,
        selBg = colors.blue,          selFg = colors.white,
        dialogBg = colors.white,      dialogFg = colors.black,
        dialogTitleBg = colors.blue,  dialogTitleFg = colors.white,
        toastBg = colors.yellow,      toastFg = colors.black,
        errorBg = colors.red,         errorFg = colors.white,
        mutedFg = colors.gray,
    },
}
-- Tema escuro: mesma estrutura, base preta/cinza.
themes.dark = setmetatable({
    desktopBg = colors.black, desktopFg = colors.lightGray,
    titleBg = colors.gray, titleFg = colors.white,
    titleBgInactive = colors.black, titleFgInactive = colors.gray,
    taskbarBg = colors.gray, taskbarFg = colors.white,
    taskbarActiveBg = colors.lightGray, taskbarActiveFg = colors.black,
    appBg = colors.black, appFg = colors.white,
    dialogBg = colors.gray, dialogFg = colors.white,
    inputBg = colors.black, inputFg = colors.white,
    mutedFg = colors.lightGray,
}, { __index = themes.default })

theme.names = { "default", "dark" }
theme.current = themes.default
theme.name = "default"

function theme.load(name)
    theme.current = themes[name] or themes.default
    theme.name = themes[name] and name or "default"
    for k, v in pairs(themes.default) do theme[k] = theme.current[k] or v end
end

theme.load("default")
return theme
