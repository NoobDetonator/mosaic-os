-- Area de trabalho: a pasta /home/desktop desenhada como grade de icones.
--
-- Antes daqui a grade vinha de registry.builtin e nao dava para tirar nem acrescentar
-- nada. Agora e' uma pasta de verdade: o que estiver dentro dela aparece, e as mesmas
-- operacoes do Arquivos valem aqui, pelo lib/fileops.
local ui = mosaic.ui
local theme = mosaic.theme
local registry = mosaic.require("apps.registry")
local fileops = mosaic.lib("fileops")

local DIR = registry.DESKTOP_DIR

-- Instalacao vinda de uma versao anterior (ou /home perdido) nao tem as pastas: cria e
-- semeia do zero, senao a area de trabalho abriria vazia sem explicacao. Aqui e' reseed
-- e nao seed porque o seeded.json pode ter sobrevivido a perda da pasta, e ai o seed
-- comum se recusaria a recriar o que ele acha que ja criou uma vez.
if not fs.isDir(DIR) then
    fs.makeDir(DIR)
    if not fs.isDir(registry.PROGRAMS_DIR) then fs.makeDir(registry.PROGRAMS_DIR) end
    registry.reseed()
end

-- Montar o canvas de sub-pixels custa 102x57 entradas; guarda o resultado por
-- caminho+tamanho para nao refazer a cada redesenho da area de trabalho.
local wallCache = nil

local function drawWallpaper(t, w, h)
    local path = settings.get("mosaic.wallpaper")
    if not path or not fs.exists(path) then wallCache = nil return end
    local key = path .. ":" .. w .. "x" .. h
    if not wallCache or wallCache.key ~= key then
        wallCache = { key = key }
        local ok, img = pcall(paintutils.loadImage, path)
        if ok and type(img) == "table" and #img > 0 then
            -- Imagem maior que a grade de caracteres = arquivo em alta resolucao: cada
            -- pixel do arquivo vira um sub-pixel. Menor que isso e um .nfp normal.
            if #img > h or #(img[1] or {}) > w then
                wallCache.canvas = mosaic.lib("pixel").fromImage(img, w, h, theme.desktopBg)
            else
                wallCache.img = img
            end
        end
    end
    if wallCache.canvas then
        wallCache.canvas:render(t, 1, 1)
    elseif wallCache.img then
        local prev = term.current()
        term.redirect(t)
        paintutils.drawImage(wallCache.img, 1, 1)
        term.redirect(prev)
    end
end

-- Sobre: mostra o logo em vetor, que o lib/vector escala para o tamanho da caixa.
-- E' o unico lugar do OS onde o desenho precisa mudar de tamanho; icone pequeno continua .nfp.
local function showAbout()
    local vector = mosaic.lib("vector")
    local shape = vector.load("/os/share/vectors/logo.lua")
    local v = mosaic.version
    local lines = {
        v.name .. " " .. v.version .. " (" .. v.codename .. ")",
        tostring(_HOST),
        "Computador #" .. os.getComputerID(),
        math.floor(fs.getFreeSpace("/") / 1024) .. " KB livres",
    }
    if not shape then ui.msgbox(table.concat(lines, "\n"), "Sobre") return end
    ui.dialog {
        title = "Sobre", w = 40, h = 9,
        build = function(form, dlg)
            form.onDraw = function(_, t)
                t.setBackgroundColor(theme.dialogTitleBg)
                t.setTextColor(theme.dialogTitleFg)
                t.setCursorPos(1, 1)
                t.write(ui.pad(" Sobre", dlg.w))
                vector.draw(t, shape, 2, 3, 6, 4, theme.dialogBg)
            end
            local y = dlg.contentY + 1
            for _, line in ipairs(lines) do
                form:add(ui.label { x = 10, y = y, w = dlg.w - 11, text = line })
                y = y + 1
            end
            form:add(ui.button { x = dlg.w - 6, y = dlg.h - 1, text = "&OK",
                onClick = function() dlg.close(true) end })
            form.defaultButton = form.widgets[#form.widgets]
        end,
    }
end

local f = ui.form { bg = theme.desktopBg, fg = theme.desktopFg }

f.onDraw = function(_, t)
    local w, h = t.getSize()
    drawWallpaper(t, w, h)
    local label = os.getComputerLabel() or ("Computador #" .. os.getComputerID())
    t.setCursorPos(math.max(1, w - #label), 1)
    t.setBackgroundColor(theme.desktopBg)
    t.setTextColor(theme.desktopFg)
    t.write(label)
end

-- Linha 1 fica para o nome do computador; a grade ocupa o resto e as ancoras a
-- reposicionam sozinhas quando a tela muda de tamanho.
local view = f:add(ui.iconview {
    x = 1, y = 2, w = "fill", h = -1,
    bg = theme.desktopBg, fg = theme.desktopFg,
})

local function refresh(onlyDraw)
    if not onlyDraw then view:setEntries(fileops.entries(DIR), true) end
    f.dirty = true
end

local ctx = {
    dir = DIR,
    desktop = true,
    refresh = refresh,
    extra = {
        { text = "Novo programa", run = function()
            local name = ui.prompt("Nome do programa (sem .lua):", "", "Novo programa")
            if name and #name > 0 then
                registry.openEditor("/apps/" .. name .. ".lua")
            end
        end },
        { text = "Terminal", run = function() mosaic.shell() end },
        { text = "Configuracoes", run = function()
            mosaic.launchWith({ title = "Configuracoes" }, "/os/apps/settings.lua")
        end },
        { text = "Sobre", run = showAbout },
    },
}

view.onActivate = function(_, entry) fileops.open(entry) end
view.onContext = function(_, entry, _, x, y) fileops.itemMenu(ctx, entry, x, y) end
view.onEmpty = function(_, btn, x, y)
    if btn == 2 then fileops.emptyMenu(ctx, x, y) end
end

f.onEvent = function(_, ev, a)
    if ev == "mosaic:apps_changed" then
        -- Programa novo em /apps ganha atalho em Programas sem precisar reiniciar.
        registry.seed()
        refresh()
        return true
    elseif ev == "disk" then
        mosaic.notify("Disquete inserido em " .. tostring(a))
        return true
    elseif ev == "disk_eject" then
        mosaic.notify("Disquete removido de " .. tostring(a))
        return true
    elseif ev == "terminate" then
        return true   -- a area de trabalho nao fecha
    end
end

refresh()
f:run()
