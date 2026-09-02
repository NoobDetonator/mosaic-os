-- Area de trabalho: icones dos apps + menu de contexto + papel de parede.
local ui = mosaic.ui
local theme = mosaic.theme
local registry = mosaic.require("apps.registry")
local iconlib = mosaic.lib("icons")

-- Largura 12 deixa 11 colunas para o nome, o suficiente para "Perifericos". O icone tem
-- 6 celulas e fica centrado nelas. Altura: 4 do icone + 1 do nome.
local ICON_W, ICON_H = 12, 5
local ICON_DX = math.floor((ICON_W - 1 - iconlib.COLS) / 2)

local icons = {}
local sel = 1
local cols = 1

local function layout()
    local w, h = term.getSize()
    icons = {}
    cols = math.max(1, math.floor((w - 1) / ICON_W))
    local i = 0
    for _, app in ipairs(registry.all()) do
        if app.desktop then
            local col, row = i % cols, math.floor(i / cols)
            local y = 2 + row * ICON_H   -- linha 1 e do nome do computador
            if y + ICON_H - 1 <= h then
                icons[#icons + 1] = { app = app, x = 2 + col * ICON_W, y = y }
            end
            i = i + 1
        end
    end
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

local f = ui.form { bg = theme.desktopBg, fg = theme.desktopFg }

f.onDraw = function(_, t)
    local w, h = t.getSize()
    drawWallpaper(t, w, h)
    for _, ic in ipairs(icons) do
        local app = ic.app
        -- Icone de verdade quando existe arquivo; senao a plaquinha de duas letras, que e o
        -- que ainda cabe em tela pequena.
        if not iconlib.draw(t, app.icon_file or app.id, ic.x + ICON_DX, ic.y, theme.desktopBg) then
            t.setCursorPos(ic.x + math.floor((ICON_W - 4) / 2), ic.y)
            t.setBackgroundColor(app.color or colors.white)
            t.setTextColor(app.color == colors.black and colors.white or colors.black)
            t.write(ui.pad(app.icon or "?", 3, "center"))
        end
        t.setCursorPos(ic.x, ic.y + iconlib.ROWS)
        local selected = ic == icons[sel]
        t.setBackgroundColor(selected and theme.selBg or theme.desktopBg)
        t.setTextColor(selected and theme.selFg or theme.desktopFg)
        t.write(ui.pad(app.name, ICON_W - 1, "center"))
    end

    local label = (os.getComputerLabel() or ("Computador #" .. os.getComputerID()))
    t.setCursorPos(w - #label, 1)
    t.setBackgroundColor(theme.desktopBg)
    t.setTextColor(theme.desktopFg)
    t.write(label)
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

local function iconAt(x, y)
    for i, ic in ipairs(icons) do
        if x >= ic.x and x < ic.x + ICON_W - 1 and y >= ic.y and y <= ic.y + iconlib.ROWS then
            return ic, i
        end
    end
end

f.onEvent = function(_, ev, btn, x, y)
    if ev == "key" then
        -- Setas andam pela grade, Enter abre. E' o caminho de teclado para a area de trabalho.
        local n = #icons
        if n == 0 then return false end
        if btn == keys.left then sel = math.max(1, sel - 1)
        elseif btn == keys.right then sel = math.min(n, sel + 1)
        elseif btn == keys.up then sel = math.max(1, sel - cols)
        elseif btn == keys.down then sel = math.min(n, sel + cols)
        elseif btn == keys.home then sel = 1
        elseif btn == keys["end"] then sel = n
        elseif btn == keys.enter or btn == keys.numPadEnter then
            registry.open(icons[sel].app)
            return true
        else return false end
        f.dirty = true
        return true
    elseif ev == "mouse_click" then
        local ic, idx = iconAt(x, y)
        if btn == 1 and ic then
            sel = idx
            registry.open(ic.app)
            return true
        elseif btn == 2 then
            local opts = {
                { text = "Terminal", run = function() mosaic.shell() end },
                { text = "Novo programa", run = function()
                    local name = ui.prompt("Nome do programa (sem .lua):", "", "Novo programa")
                    if name and #name > 0 then
                        mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", "/apps/" .. name .. ".lua")
                    end
                end },
                { text = "Atualizar icones", run = function() layout() f.dirty = true end },
                { text = "Configuracoes", run = function() mosaic.launchWith({ title = "Configuracoes" }, "/os/apps/settings.lua") end },
                { text = "Sobre", run = function() showAbout() end },
            }
            local idx = ui.menu(opts, x, y, 18)
            f.dirty = true
            if idx then opts[idx].run() end
            return true
        end
    elseif ev == "term_resize" then
        layout()
        f.dirty = true
        return true
    elseif ev == "mosaic:apps_changed" then
        layout()
        f.dirty = true
        return true
    elseif ev == "terminate" then
        return true
    end
end

layout()
f:run()
