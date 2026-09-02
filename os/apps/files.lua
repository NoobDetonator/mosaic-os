-- Gerenciador de arquivos.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")
local strutil = mosaic.lib("strutil")
local registry = mosaic.require("apps.registry")

local dir = ""   -- convencao do fs.combine: raiz e "", nunca "/"
local f = ui.form()

-- Tudo ancorado: o form resolve as posicoes a cada mudanca de tamanho, e nenhum widget
-- precisa ser reposicionado na mao no term_resize.
local pathLabel = f:add(ui.label { x = 1, y = 1, w = "fill", text = "",
    bg = theme.inputBg, fg = theme.inputFg })
local status = f:add(ui.label { x = 1, bottom = 0, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

local list, refresh, open

-- A fila entra antes da lista: o fillTo da lista precisa saber onde a fila comeca, e a fila
-- so sabe disso depois de descobrir se quebrou em uma ou duas linhas.
local bar = ui.row(f, { bottom = 1, items = {
    { text = "&Abrir", onClick = function() open(list:getSelected()) end },
    { text = "Nova &pasta", alt = true, onClick = function()
        local name = ui.prompt("Nome da pasta:", "", "Nova pasta")
        if name and #name > 0 then fs.makeDir(fs.combine(dir, name)) refresh() end
    end },
    { text = "&Novo arquivo", alt = true, onClick = function()
        local name = ui.prompt("Nome do arquivo:", "novo.lua", "Novo arquivo")
        if name and #name > 0 then
            local path = fs.combine(dir, name)
            if not fs.exists(path) then fsx.write(path, "") end
            mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", path)
            refresh()
        end
    end },
    { text = "&Ir para", alt = true, onClick = function()
        local p = ui.prompt("Caminho:", "/" .. dir, "Ir para")
        if p then
            local clean = p:gsub("^/", "")
            if fs.isDir(clean) then dir = clean refresh() else ui.msgbox("Pasta nao encontrada.", "Ops") end
        end
    end },
} })

list = f:add(ui.list {
    x = 1, y = 2, w = "fill", fillTo = bar,
    render = function(item)
        if item.up then return " .. (voltar)" end
        local mark = item.isDir and "/" or " "
        local size = item.isDir and "" or strutil.bytes(item.size)
        local width = list.w
        local name = strutil.ellipsis(item.name, width - #size - 4)
        return mark .. strutil.pad(name, width - #size - 3) .. size
    end,
})

function refresh(keep)
    local items = {}
    if dir ~= "" then items[1] = { up = true, name = "..", path = fs.getDir(dir), isDir = true } end
    for _, it in ipairs(fsx.listDetailed(dir)) do items[#items + 1] = it end
    list:setItems(items, keep)
    pathLabel.text = " /" .. dir
    status.text = string.format(" %d itens | %s livres", #items - (items[1] and items[1].up and 1 or 0),
        strutil.bytes(fs.getFreeSpace("/")))
    f.dirty = true
end

function open(item, x, y)
    if not item then return end
    if item.isDir then
        dir = item.path
        refresh()
        return
    end
    registry.openFile(item.path, x, y)
end

list.onActivate = function(_, item) open(item) end

list.onContext = function(_, item, _, lx, ly)
    if not item or item.up then return end
    local actions = {
        { text = "Abrir", run = function() open(item, lx + 2, ly + 2) end },
        { text = "Renomear", run = function()
            local novo = ui.prompt("Novo nome:", item.name, "Renomear")
            if novo and #novo > 0 then
                local ok, err = pcall(fs.move, item.path, fs.combine(dir, novo))
                if not ok then ui.msgbox(tostring(err), "Erro") end
                refresh()
            end
        end },
        { text = "Copiar", run = function()
            local ok, err = pcall(fs.copy, item.path, fsx.uniqueName(item.path))
            if not ok then ui.msgbox(tostring(err), "Erro") end
            refresh()
        end },
        { text = "Excluir", run = function()
            if ui.confirm("Excluir " .. item.name .. "?", "Confirmar") then
                local ok, err = pcall(fs.delete, item.path)
                if not ok then ui.msgbox(tostring(err), "Erro") end
                refresh()
            end
        end },
        { text = "Detalhes", run = function()
            local size = item.isDir and fsx.treeSize(item.path) or item.size
            ui.msgbox(string.format("%s\nCaminho: /%s\nTamanho: %s\nSomente leitura: %s",
                item.name, item.path, strutil.bytes(size), item.readOnly and "sim" or "nao"), "Detalhes")
        end },
    }
    local idx = ui.menu(actions, lx + 2, ly + 2, 14)
    f.dirty = true
    if idx then actions[idx].run() end
end

f.onEvent = function(_, ev, code)
    if ev == "key" and code == keys.backspace and dir ~= "" then
        dir = fs.getDir(dir)
        refresh()
        return true
    elseif ev == "term_resize" then
        refresh(true)   -- o form ja reposicionou tudo; aqui so o texto do rodape muda
        return true
    end
end

refresh()
f:run()
