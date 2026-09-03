-- Janela de pasta: a mesma grade da area de trabalho, para o conteudo de uma pasta.
-- Recebe o caminho por argumento (registry.openFolder chama assim).
local ui = mosaic.ui
local theme = mosaic.theme
local registry = mosaic.require("apps.registry")
local fileops = mosaic.lib("fileops")
local strutil = mosaic.lib("strutil")

local args = { ... }
local dir = "/" .. fs.combine(args[1] or "/home", "")

local f = ui.form()

-- Ordem importa: cada ancora so enxerga widget ja adicionado, entao o rodape entra
-- antes da grade que se estende ate ele.
local rodape = f:add(ui.label { x = 1, bottom = 0, w = "fill",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
local view = f:add(ui.iconview { x = 1, y = 1, w = "fill", fillTo = rodape })

local function refresh(onlyDraw)
    if not onlyDraw then view:setEntries(fileops.entries(dir), true) end
    local n = #(view.entries or {})
    rodape.text = string.format(" %s  |  %d %s", strutil.ellipsis(dir, 30), n, n == 1 and "item" or "itens")
    f.dirty = true
end

local ctx = { dir = dir, refresh = refresh }

view.onActivate = function(_, entry) fileops.open(entry) end
view.onContext = function(_, entry, _, x, y) fileops.itemMenu(ctx, entry, x, y) end
view.onEmpty = function(_, btn, x, y)
    if btn == 2 then fileops.emptyMenu(ctx, x, y) end
end

f.onEvent = function(_, ev, a)
    if ev == "key" then
        if a == keys.backspace then
            -- Sobe um nivel na MESMA janela; abrir outra a cada nivel entulharia a taskbar.
            local pai = "/" .. fs.combine(dir, "..")
            if pai ~= dir then
                dir = pai
                ctx.dir = dir
                mosaic.setTitle(nil, fs.getName(dir) ~= "" and fs.getName(dir) or "Disco")
                view.selected = 1
                view.scroll = 0
                refresh()
            end
            return true
        elseif a == keys.f5 then
            refresh()
            return true
        end
    end
end

refresh()
f:run()
