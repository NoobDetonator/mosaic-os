-- Gerenciador de arquivos.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")
local strutil = mosaic.lib("strutil")

local dir = ""   -- convencao do fs.combine: raiz e "", nunca "/"
local w, h = term.getSize()
local f = ui.form()

local pathLabel = f:add(ui.label { x = 1, y = 1, w = w, text = "", bg = theme.accent, fg = theme.accentFg })
local list = f:add(ui.list {
    x = 1, y = 2, w = w, h = h - 3,
    render = function(item)
        if item.up then return " .. (voltar)" end
        local mark = item.isDir and "/" or " "
        local size = item.isDir and "" or strutil.bytes(item.size)
        local name = strutil.ellipsis(item.name, w - #size - 4)
        return mark .. strutil.pad(name, w - #size - 3) .. size
    end,
})
local status = f:add(ui.label { x = 1, y = h, w = w, text = "", bg = theme.taskbarBg, fg = theme.taskbarFg })

local function refresh(keep)
    local items = {}
    if dir ~= "" then items[1] = { up = true, name = "..", path = fs.getDir(dir), isDir = true } end
    for _, it in ipairs(fsx.listDetailed(dir)) do items[#items + 1] = it end
    list:setItems(items, keep)
    pathLabel.text = " /" .. dir
    status.text = string.format(" %d itens | %s livres", #items - (items[1] and items[1].up and 1 or 0),
        strutil.bytes(fs.getFreeSpace("/")))
    f.dirty = true
end

local function open(item)
    if not item then return end
    if item.isDir then
        dir = item.up and item.path or item.path
        refresh()
        return
    end
    local name = item.name:lower()
    if name:match("%.nfp$") then
        mosaic.launchWith({ title = "Paint" }, "/rom/programs/fun/advanced/paint.lua", item.path)
    elseif name:match("%.lua$") then
        local choices = { { text = "Executar" }, { text = "Editar" }, { text = "Cancelar" } }
        local idx = ui.menu(choices, 4, 4, 14)
        if idx == 1 then mosaic.launch("/" .. item.path)
        elseif idx == 2 then mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", item.path) end
    else
        mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", item.path)
    end
end

list.onActivate = function(_, item) open(item) end

list.onContext = function(_, item, _, lx, ly)
    if not item or item.up then return end
    local actions = {
        { text = "Abrir", run = function() open(item) end },
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

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h - 1, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("Abrir", function() open(list:getSelected()) end)
addBtn("Nova pasta", function()
    local name = ui.prompt("Nome da pasta:", "", "Nova pasta")
    if name and #name > 0 then fs.makeDir(fs.combine(dir, name)) refresh() end
end, true)
addBtn("Novo arquivo", function()
    local name = ui.prompt("Nome do arquivo:", "novo.lua", "Novo arquivo")
    if name and #name > 0 then
        local path = fs.combine(dir, name)
        if not fs.exists(path) then fsx.write(path, "") end
        mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", path)
        refresh()
    end
end, true)
addBtn("Ir para", function()
    local p = ui.prompt("Caminho:", "/" .. dir, "Ir para")
    if p then
        local clean = p:gsub("^/", "")
        if fs.isDir(clean) then dir = clean refresh() else ui.msgbox("Pasta nao encontrada.", "Ops") end
    end
end, true)

f.onEvent = function(_, ev, code)
    if ev == "key" and code == keys.backspace and dir ~= "" then
        dir = fs.getDir(dir)
        refresh()
        return true
    elseif ev == "term_resize" then
        w, h = term.getSize()
        pathLabel.w = w
        list.w, list.h = w, h - 3
        status.y, status.w = h, w
        refresh(true)
        return true
    end
end

refresh()
f:run()
