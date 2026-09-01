-- Area de trabalho: icones dos apps + menu de contexto + papel de parede.
local ui = mosaic.ui
local theme = mosaic.theme
local registry = mosaic.require("apps.registry")

local ICON_W, ICON_H = 12, 3   -- largura 12 = 11 col. de nome, o suficiente para "Perifericos"

local icons = {}

local function layout()
    local w, h = term.getSize()
    icons = {}
    local cols = math.max(1, math.floor((w - 1) / ICON_W))
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
        t.setCursorPos(ic.x + math.floor((ICON_W - 4) / 2), ic.y)
        t.setBackgroundColor(app.color or colors.white)
        t.setTextColor(app.color == colors.black and colors.white or colors.black)
        t.write(ui.pad(app.icon or "?", 3, "center"))
        t.setCursorPos(ic.x, ic.y + 1)
        t.setBackgroundColor(theme.desktopBg)
        t.setTextColor(theme.desktopFg)
        t.write(ui.pad(app.name, ICON_W - 1, "center"))
    end
    local label = (os.getComputerLabel() or ("Computador #" .. os.getComputerID()))
    t.setCursorPos(w - #label, 1)
    t.setBackgroundColor(theme.desktopBg)
    t.setTextColor(theme.desktopFg)
    t.write(label)
end

local function iconAt(x, y)
    for _, ic in ipairs(icons) do
        if x >= ic.x and x < ic.x + ICON_W - 1 and y >= ic.y and y <= ic.y + 1 then return ic end
    end
end

f.onEvent = function(_, ev, btn, x, y)
    if ev == "mouse_click" then
        local ic = iconAt(x, y)
        if btn == 1 and ic then
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
                { text = "Sobre", run = function()
                    ui.msgbox(mosaic.version.name .. " " .. mosaic.version.version .. " (" .. mosaic.version.codename .. ")\n" ..
                        "CC:Tweaked " .. tostring(_HOST) .. "\nComputador #" .. os.getComputerID(), "Sobre")
                end },
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
